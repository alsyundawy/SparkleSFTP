#!/usr/local/bin/bash
# ==============================================================================
# Tools/Lint/generate-sonarqube-report.sh
# Generates SonarQube Generic Issue Import JSON from SwiftLint diagnostics (TD-08).
# Adheres to bash-pro defensive programming guidelines.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

REPORTS_DIR="${PROJECT_ROOT}/reports"
OUTPUT_FILE="${REPORTS_DIR}/swiftlint-sonarqube.json"

mkdir -p "${REPORTS_DIR}"

echo "==> Generating SonarQube SwiftLint report at: ${OUTPUT_FILE}"

cd "${PROJECT_ROOT}"

# Run SwiftLint with sonarqube reporter
if ! swiftlint lint --reporter sonarqube src Tests >"${OUTPUT_FILE}"; then
  echo "==> Note: SwiftLint reported issues, verifying output file integrity..."
fi

if [[ -f "${OUTPUT_FILE}" ]] && [[ -s "${OUTPUT_FILE}" ]]; then
  python3 -m json.tool "${OUTPUT_FILE}" >/dev/null
  ISSUE_COUNT="$(python3 -c "import json; data = json.load(open('${OUTPUT_FILE}')); print(len(data.get('issues', [])))")"
  echo "==> SonarQube report generated successfully (${ISSUE_COUNT} issues documented)."
else
  echo "{\"issues\": []}" >"${OUTPUT_FILE}"
  echo "==> Clean report generated with 0 issues."
fi
