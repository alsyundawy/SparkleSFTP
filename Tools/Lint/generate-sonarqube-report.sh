#!/usr/bin/env bash
# ==============================================================================
# Tools/Lint/generate-sonarqube-report.sh
# Generates SonarQube Generic Issue Import JSON from SwiftLint diagnostics (TD-08).
# Adheres to bash-pro defensive programming guidelines.
# ==============================================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

REPORTS_DIR="${PROJECT_ROOT}/reports"
OUTPUT_FILE="${REPORTS_DIR}/swiftlint-sonarqube.json"

if ! command -v swiftlint >/dev/null 2>&1; then
  printf 'Error: swiftlint not found on PATH.\n' >&2
  exit 1
fi

mkdir -p "${REPORTS_DIR}"

printf '==> Generating SonarQube SwiftLint report at: %s\n' "${OUTPUT_FILE}"

cd "${PROJECT_ROOT}"

# Run SwiftLint with sonarqube reporter
SWIFTLINT_STATUS=0
swiftlint lint --reporter sonarqube src Tests >"${OUTPUT_FILE}" || SWIFTLINT_STATUS=$?

if [[ ! -s "${OUTPUT_FILE}" ]]; then
  printf 'Error: SwiftLint produced empty output (exit=%s).\n' "${SWIFTLINT_STATUS}" >&2
  exit 1
fi

python3 - "${OUTPUT_FILE}" <<'PY'
import json
import sys

output_path = sys.argv[1]
with open(output_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
count = len(data.get("issues", []))
print(f"==> SonarQube report generated successfully ({count} issues documented).")
PY

if [[ "${SWIFTLINT_STATUS}" -ne 0 ]]; then
  exit "${SWIFTLINT_STATUS}"
fi
