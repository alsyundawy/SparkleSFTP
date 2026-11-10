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

cd "${REPO_ROOT}"

printf 'Building arm64 release binary...\n'
swift build -c release --arch arm64

printf 'Building x86_64 release binary...\n'
swift build -c release --arch x86_64

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

SPARKLE_FW="$(find "${REPO_ROOT}/.build/artifacts" -path "*/macos-*/*.framework" -type d -name "Sparkle.framework" | head -n 1 || true)"
if [[ -n "${SPARKLE_FW}" && -d "${SPARKLE_FW}" ]]; then
  cp -R "${SPARKLE_FW}" "${FRAMEWORKS_DIR}/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/SparkleSFTP" 2>/dev/null || true
fi

printf 'Universal 2 bundle ready at %s\n' "${APP_BUNDLE}"
