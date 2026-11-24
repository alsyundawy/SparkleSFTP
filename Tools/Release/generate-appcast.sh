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
  DMG_TARGET="$(
    python3 - "${DIST_DIR}" <<'PY'
import glob
import os
import re
import sys

dist_dir = sys.argv[1]
pattern = os.path.join(dist_dir, "SparkleSFTP-*-universal.dmg")
candidates = [p for p in glob.glob(pattern) if os.path.isfile(p)]

def sort_key(path: str):
    name = os.path.basename(path)
    match = re.match(r"^SparkleSFTP-(\d+)\.(\d+)\.(\d+)(?:-([A-Za-z0-9.]+))?-universal\.dmg$", name)
    if not match:
        return (0, 0, 0, 0, name)
    nums = (int(match.group(1)), int(match.group(2)), int(match.group(3)))
    prerelease = match.group(4)
    return (*nums, 1 if prerelease is None else 0, prerelease or "")

if candidates:
    print(sorted(candidates, key=sort_key)[-1])
PY
  )"
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
if [[ -n "${SPARKLE_ED25519_PRIVATE_KEY:-}" ]]; then
  if [[ -z "${SIGN_UPDATE_BIN}" || ! -x "${SIGN_UPDATE_BIN}" ]]; then
    printf 'Error: SPARKLE_ED25519_PRIVATE_KEY is set, but Sparkle sign_update binary was not found in .build.\n' >&2
    exit 1
  fi
  printf 'Signing DMG with Sparkle Ed25519 key...\n'
  ED_SIGNATURE="$(printf '%s' "${SPARKLE_ED25519_PRIVATE_KEY}" | "${SIGN_UPDATE_BIN}" -s - "${DMG_TARGET}")"
fi

if [[ -z "${ED_SIGNATURE}" ]]; then
  ED_SIGNATURE="SIGNATURE_PLACEHOLDER_FOR_RELEASE_NOTARIZATION"
fi

python3 - "${APPCAST_XML}" "${VERSION}" "${PUB_DATE}" "${RELEASE_PREFIX}" "${DMG_NAME}" "${ED_SIGNATURE}" "${DMG_SIZE}" <<'PY'
import sys
from xml.sax.saxutils import escape, quoteattr

out_path, version, pub_date, release_prefix, dmg_name, ed_sig, dmg_size = sys.argv[1:8]
xml_body = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>SparkleSFTP Changelog</title>
    <link>https://github.com/alsyundawy/SparkleSFTP</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
    <item>
      <title>Version {escape(version)}</title>
      <sparkle:releaseNotesLink>{escape(f"https://github.com/alsyundawy/SparkleSFTP/releases/tag/v{version}")}</sparkle:releaseNotesLink>
      <pubDate>{escape(pub_date)}</pubDate>
      <enclosure
        url={quoteattr(f"{release_prefix}/{dmg_name}")}
        sparkle:edSignature={quoteattr(ed_sig)}
        sparkle:version={quoteattr(version)}
        sparkle:shortVersionString={quoteattr(version)}
        length={quoteattr(dmg_size)}
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
"""
with open(out_path, "w", encoding="utf-8") as fh:
    fh.write(xml_body)
PY

printf 'Generated appcast feed: %s\n' "${APPCAST_XML}"
