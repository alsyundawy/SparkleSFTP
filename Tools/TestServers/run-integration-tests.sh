#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.test.yml"

cleanup() {
  if command -v docker >/dev/null 2>&1; then
    docker compose -f "${COMPOSE_FILE}" down --remove-orphans >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if ! command -v docker >/dev/null 2>&1; then
  printf 'Docker is required to run live SFTP/FTPS integration fixtures.\n' >&2
  exit 1
fi

printf 'Starting SparkleSFTP Docker test fixtures...\n'
docker compose -f "${COMPOSE_FILE}" up -d --wait

cd "${REPO_ROOT}"
SPARKLESFTP_LIVE_DOCKER_TESTS=1 swift test
