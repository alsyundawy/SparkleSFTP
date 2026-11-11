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

BUILD_JOBS="${SPARKLE_BUILD_JOBS:-4}"

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

cp "${REPO_ROOT}/App/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
if [[ -f "${REPO_ROOT}/App/Resources/AppIcon.icns" ]]; then
  cp "${REPO_ROOT}/App/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi
if [[ -f "${REPO_ROOT}/App/Resources/AppIcon.png" ]]; then
  cp "${REPO_ROOT}/App/Resources/AppIcon.png" "${RESOURCES_DIR}/AppIcon.png"
fi

SPARKLE_FW="$(find "${REPO_ROOT}/.build/artifacts" -path "*/macos-*/*.framework" -type d -name "Sparkle.framework" | head -n 1 || true)"
if [[ -n "${SPARKLE_FW}" && -d "${SPARKLE_FW}" ]]; then
  cp -R "${SPARKLE_FW}" "${FRAMEWORKS_DIR}/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/SparkleSFTP" 2>/dev/null || true
fi

codesign --force --deep --sign "${DEVELOPER_ID_APP:--}" "${APP_BUNDLE}"
codesign --verify --deep --strict "${APP_BUNDLE}"
printf 'Built universal bundle: %s\n' "${APP_BUNDLE}"

printf 'Universal 2 bundle ready at %s\n' "${APP_BUNDLE}"
