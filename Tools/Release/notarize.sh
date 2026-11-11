#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
APP_BUNDLE="${1:-${REPO_ROOT}/dist/SparkleSFTP.app}"
ENTITLEMENTS="${REPO_ROOT}/src/App/SparkleSFTP.entitlements"

: "${DEVELOPER_ID_APP:?Set DEVELOPER_ID_APP (e.g. Developer ID Application: Name (TEAMID))}"
: "${APPLE_NOTARY_PROFILE:?Set APPLE_NOTARY_PROFILE for xcrun notarytool keychain profile}"

if [[ ! -d "${APP_BUNDLE}" ]]; then
  printf 'App bundle not found: %s\n' "${APP_BUNDLE}" >&2
  exit 1
fi

codesign --deep --force --verify --verbose --timestamp \
  --options runtime \
  --entitlements "${ENTITLEMENTS}" \
  --sign "${DEVELOPER_ID_APP}" \
  "${APP_BUNDLE}"

ZIP_PATH="${REPO_ROOT}/dist/SparkleSFTP-notarize.zip"
rm -f "${ZIP_PATH}"
ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

xcrun notarytool submit "${ZIP_PATH}" --keychain-profile "${APPLE_NOTARY_PROFILE}" --wait
xcrun stapler staple "${APP_BUNDLE}"
spctl -a -vv -t exec "${APP_BUNDLE}"
rm -f "${ZIP_PATH}"

printf 'Signed and notarized successfully: %s\n' "${APP_BUNDLE}"
