#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# SparkleSFTP — Automated Sparkle Ed25519 Appcast Feed Generator (Task 18.2)
# Strictly adheres to bash-pro defensive scripting guidelines.
# ==============================================================================

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
DIST_DIR="${REPO_ROOT}/dist"
APPCAST_XML="${DIST_DIR}/appcast.xml"
RELEASE_PREFIX="https://github.com/alsyundawy/SparkleSFTP/releases/latest/download"

SIGN_UPDATE_BIN="$(find "${REPO_ROOT}/.build" -type f -path "*/bin/sign_update" 2>/dev/null | head -n 1 || true)"

mkdir -p "${DIST_DIR}"

DMG_TARGET="${1:-}"
if [[ -z "${DMG_TARGET}" ]]; then
  DMG_TARGET="$(find "${DIST_DIR}" -maxdepth 1 -name "SparkleSFTP-*-universal.dmg" -type f 2>/dev/null | sort -V | tail -n 1 || true)"
fi

if [[ -z "${DMG_TARGET}" || ! -f "${DMG_TARGET}" ]]; then
  printf 'Error: Target DMG not found in %s. Please run create-dmg.sh first.\n' "${DIST_DIR}" >&2
  exit 1
fi

DMG_NAME="$(basename -- "${DMG_TARGET}")"
DMG_SIZE="$(stat -f%z "${DMG_TARGET}" 2>/dev/null || stat -c%s "${DMG_TARGET}")"
PUB_DATE="$(date -u +"%a, %d %b %Y %H:%M:%S +0000")"
VERSION="$(echo "${DMG_NAME}" | sed -E 's/^SparkleSFTP-([0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?)-universal\.dmg$/\1/')"

if [[ -z "${VERSION}" || "${VERSION}" == "${DMG_NAME}" ]]; then
  VERSION="0.7.0"
fi

printf 'Generating appcast for %s (version: %s, size: %s bytes)...\n' "${DMG_NAME}" "${VERSION}" "${DMG_SIZE}"

ED_SIGNATURE=""
if [[ -n "${SIGN_UPDATE_BIN}" && -x "${SIGN_UPDATE_BIN}" && -n "${SPARKLE_ED25519_PRIVATE_KEY:-}" ]]; then
  printf 'Signing DMG with Sparkle Ed25519 key...\n'
  ED_SIGNATURE="$(printf '%s' "${SPARKLE_ED25519_PRIVATE_KEY}" | "${SIGN_UPDATE_BIN}" -s - "${DMG_TARGET}" 2>/dev/null || true)"
fi

if [[ -z "${ED_SIGNATURE}" ]]; then
  ED_SIGNATURE="SIGNATURE_PLACEHOLDER_FOR_RELEASE_NOTARIZATION"
fi

cat <<EOF > "${APPCAST_XML}"
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>SparkleSFTP Changelog</title>
    <link>https://github.com/alsyundawy/SparkleSFTP</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <sparkle:releaseNotesLink>https://github.com/alsyundawy/SparkleSFTP/releases/tag/v${VERSION}</sparkle:releaseNotesLink>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure
        url="${RELEASE_PREFIX}/${DMG_NAME}"
        sparkle:edSignature="${ED_SIGNATURE}"
        sparkle:version="${VERSION}"
        sparkle:shortVersionString="${VERSION}"
        length="${DMG_SIZE}"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

printf 'Generated appcast feed: %s\n' "${APPCAST_XML}"
