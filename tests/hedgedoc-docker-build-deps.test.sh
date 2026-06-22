#!/usr/bin/env bash
# Static checks: vibe-hedgedoc Dockerfiles include Alpine toolchain for native yarn deps (e.g. better-sqlite3).
# Resolves repo path from HEDGEDOC_ROOT or sibling ../vibe-hedgedoc/vibe-hedgedoc; skips if not found.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSISTANT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

resolve_hedgedoc_root() {
  if [[ -n "${HEDGEDOC_ROOT:-}" ]]; then
    printf '%s\n' "$(cd "${HEDGEDOC_ROOT}" && pwd)"
    return 0
  fi
  local sibling=""
  sibling="$(cd "$(dirname "${ASSISTANT_ROOT}")" && pwd)/vibe-hedgedoc/vibe-hedgedoc"
  if [[ -f "${sibling}/backend/docker/Dockerfile" ]]; then
    printf '%s\n' "${sibling}"
    return 0
  fi
  return 1
}

assert_apk_has_native_toolchain() {
  local file="$1"
  local label="$2"

  [[ -f "${file}" ]] || fail "missing ${label}: ${file}"

  grep -q 'apk add' "${file}" || fail "${label}: expected 'apk add' instruction"
  grep -qE '(^|[^a-zA-Z0-9])python3([^a-zA-Z0-9]|$)' "${file}" || fail "${label}: expected python3 in apk/toolchain"
  grep -qE '(^|[^a-zA-Z0-9])make([^a-zA-Z0-9]|$)' "${file}" || fail "${label}: expected make in apk/toolchain"
  grep -qE '(^|[^a-zA-Z0-9])g\+\+([^a-zA-Z0-9]|$)' "${file}" || fail "${label}: expected g++ in apk/toolchain"
}

HEDGEDOC_ROOT=""
if ! HEDGEDOC_ROOT="$(resolve_hedgedoc_root)"; then
  printf 'SKIP: hedgedoc-docker-build-deps (set HEDGEDOC_ROOT or place repo at ../vibe-hedgedoc/vibe-hedgedoc)\n'
  exit 0
fi

BE_DF="${HEDGEDOC_ROOT}/backend/docker/Dockerfile"
FE_DF="${HEDGEDOC_ROOT}/frontend/docker/Dockerfile"

assert_apk_has_native_toolchain "${BE_DF}" "backend/docker/Dockerfile"
assert_apk_has_native_toolchain "${FE_DF}" "frontend/docker/Dockerfile"

printf 'PASS: hedgedoc-docker-build-deps (root=%s)\n' "${HEDGEDOC_ROOT}"
