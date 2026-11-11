#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
APP_BUNDLE="${1:-${REPO_ROOT}/dist/SparkleSFTP.app}"
VERSION="${2:-0.2.0}"
if [[ ! "${VERSION}" =~ ^[0-9]+(\.[0-9]+)*([-.][A-Za-z0-9.-]+)?$ ]]; then
  printf 'Invalid version string: %s\n' "${VERSION}" >&2
  exit 1
fi

DMG_PATH="${REPO_ROOT}/dist/SparkleSFTP-${VERSION}-universal.dmg"
STAGING_DIR="${REPO_ROOT}/dist/dmg-staging"

cleanup() {
  rm -rf "${STAGING_DIR}"
}
trap cleanup EXIT

if [[ ! -d "${APP_BUNDLE}" ]]; then
  printf 'App bundle not found: %s\n' "${APP_BUNDLE}" >&2
  exit 1
fi

rm -rf "${STAGING_DIR}" "${DMG_PATH}" "${DMG_PATH}.sha256"
mkdir -p "${STAGING_DIR}"
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create -volname "SparkleSFTP ${VERSION}" \
  -srcfolder "${STAGING_DIR}" \
  -ov -format UDZO \
  "${DMG_PATH}"

if [[ -n "${DEVELOPER_ID_APP:-}" ]]; then
  codesign --force --timestamp --sign "${DEVELOPER_ID_APP}" "${DMG_PATH}"
fi

(
  cd -- "$(dirname -- "${DMG_PATH}")"
  shasum -a 256 "$(basename -- "${DMG_PATH}")" >"$(basename -- "${DMG_PATH}").sha256"
)

printf 'Created DMG: %s\n' "${DMG_PATH}"
