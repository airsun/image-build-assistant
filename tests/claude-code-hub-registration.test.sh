#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSISTANT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
PROJECTS_FILE="${ASSISTANT_ROOT}/config/projects.yaml"

# shellcheck source=../lib/project-resolver.sh
source "${ASSISTANT_ROOT}/lib/project-resolver.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"

  if [[ "${actual}" != "${expected}" ]]; then
    fail "${message}: expected '${expected}', got '${actual}'"
  fi
}

test_claude_code_hub_registration() {
  project_resolver_clear
  resolve_project_by_name "${PROJECTS_FILE}" "claude-code-hub"

  assert_eq "${PROJECT_NAME}" "claude-code-hub" "should resolve registered project name"
  assert_eq "${DOCKERFILE_PATH}" "deploy/Dockerfile" "should keep dockerfile path contract"
  assert_eq "${BUILD_CONTEXT}" "." "should keep root build context contract"
  [[ -d "${SOURCE_DIR}" ]] || fail "registered source dir should exist: ${SOURCE_DIR}"
  [[ -f "${SOURCE_DIR}/deploy/Dockerfile" ]] || fail "registered dockerfile should exist under source dir"
}

test_claude_code_hub_registration
printf 'PASS: claude-code-hub registration test\n'
