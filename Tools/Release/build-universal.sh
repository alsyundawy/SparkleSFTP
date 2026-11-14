#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
DIST_DIR="${REPO_ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/SparkleSFTP.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

BUILD_JOBS="${SPARKLE_BUILD_JOBS:-2}"
if [[ -z "${CC:-}" ]] || ! "${CC}" --version >/dev/null 2>&1; then
  export CC="/usr/bin/clang"
fi
if [[ -z "${CXX:-}" ]] || ! "${CXX}" --version >/dev/null 2>&1; then
  export CXX="/usr/bin/clang++"
fi

sign_embedded_frameworks() {
  local identity="$1"
  local fw_dir="$2"
  local runtime_flags=("$3")
  if [[ ! -d "${fw_dir}/Sparkle.framework" ]]; then
    return 0
  fi
  local sparkle_fw="${fw_dir}/Sparkle.framework"
  local versions_b="${sparkle_fw}/Versions/B"
  local -a targets=()
  if [[ -d "${versions_b}" ]]; then
    for xpc in "${versions_b}"/XPCServices/*.xpc; do
      [[ -e "${xpc}" ]] && targets+=("${xpc}")
    done
    [[ -e "${versions_b}/Updater.app" ]] && targets+=("${versions_b}/Updater.app")
    [[ -e "${versions_b}/Autoupdate" ]] && targets+=("${versions_b}/Autoupdate")
  fi
  targets+=("${sparkle_fw}")
  for target in "${targets[@]}"; do
    if [[ -n "${runtime_flags[0]}" ]]; then
      codesign --force --timestamp --options runtime --sign "${identity}" "${target}"
    else
      codesign --force --sign "${identity}" "${target}"
    fi
  done
}

cd "${REPO_ROOT}"

printf 'Building arm64 release binary (jobs=%s)...\n' "${BUILD_JOBS}"
nice -n 10 swift build -c release --arch arm64 -j "${BUILD_JOBS}"

printf 'Building x86_64 release binary (jobs=%s)...\n' "${BUILD_JOBS}"
nice -n 10 swift build -c release --arch x86_64 -j "${BUILD_JOBS}"

ARM64_BIN="${REPO_ROOT}/.build/arm64-apple-macosx/release/SparkleSFTP"
X64_BIN="${REPO_ROOT}/.build/x86_64-apple-macosx/release/SparkleSFTP"

if [[ ! -f "${ARM64_BIN}" || ! -f "${X64_BIN}" ]]; then
  printf 'Expected release binaries missing.\n' >&2
  exit 1
fi

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${FRAMEWORKS_DIR}" "${RESOURCES_DIR}"

lipo -create "${ARM64_BIN}" "${X64_BIN}" -output "${MACOS_DIR}/SparkleSFTP"
chmod +x "${MACOS_DIR}/SparkleSFTP"
lipo -archs "${MACOS_DIR}/SparkleSFTP"

cp "${REPO_ROOT}/src/App/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || date +%s)"
BUILD_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${CONTENTS_DIR}/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${BUILD_NUMBER}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SparkleSFTPCommitHash ${GIT_COMMIT}" "${CONTENTS_DIR}/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :SparkleSFTPCommitHash string ${GIT_COMMIT}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SparkleSFTPBuildDate ${BUILD_DATE}" "${CONTENTS_DIR}/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :SparkleSFTPBuildDate string ${BUILD_DATE}" "${CONTENTS_DIR}/Info.plist"
if [[ -f "${REPO_ROOT}/src/App/Resources/AppIcon.icns" ]]; then
  cp "${REPO_ROOT}/src/App/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi
if [[ -f "${REPO_ROOT}/src/App/Resources/AppIcon.png" ]]; then
  cp "${REPO_ROOT}/src/App/Resources/AppIcon.png" "${RESOURCES_DIR}/AppIcon.png"
fi

for bundle_path in "${REPO_ROOT}/.build/arm64-apple-macosx/release/"SparkleSFTP_*.bundle; do
  if [[ -d "${bundle_path}" ]]; then
    cp -R "${bundle_path}" "${RESOURCES_DIR}/"
  fi
done

SPARKLE_FW="$(find "${REPO_ROOT}/.build/artifacts" -path "*/macos-*/*.framework" -type d -name "Sparkle.framework" | head -n 1 || true)"
if [[ -z "${SPARKLE_FW}" || ! -d "${SPARKLE_FW}" ]]; then
  printf 'Expected Sparkle.framework artifact missing under .build/artifacts.\n' >&2
  exit 1
fi
cp -R "${SPARKLE_FW}" "${FRAMEWORKS_DIR}/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/SparkleSFTP" 2>/dev/null || true

SIGN_ID="${DEVELOPER_ID_APP:--}"
if [[ "${SIGN_ID}" == "-" ]]; then
  sign_embedded_frameworks "${SIGN_ID}" "${FRAMEWORKS_DIR}" ""
  codesign --force --sign "${SIGN_ID}" "${APP_BUNDLE}"
else
  sign_embedded_frameworks "${SIGN_ID}" "${FRAMEWORKS_DIR}" "--options runtime"
  codesign --force --timestamp --options runtime --entitlements "${REPO_ROOT}/src/App/SparkleSFTP.entitlements" --sign "${SIGN_ID}" "${APP_BUNDLE}"
fi
codesign --verify --deep --strict "${APP_BUNDLE}"
printf 'Built universal bundle: %s\n' "${APP_BUNDLE}"

printf 'Universal 2 bundle ready at %s\n' "${APP_BUNDLE}"
