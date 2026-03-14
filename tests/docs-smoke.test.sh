#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSISTANT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
USAGE_DOC="${ASSISTANT_ROOT}/docs/usage.md"
EXAMPLE_DOC="${ASSISTANT_ROOT}/docs/claude-code-hub-example.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_doc_contains() {
  local path="$1"
  local needle="$2"
  local message="$3"

  grep -q "${needle}" "${path}" || fail "${message}: missing '${needle}' in ${path}"
}

[[ -f "${USAGE_DOC}" ]] || fail "usage doc should exist"
[[ -f "${EXAMPLE_DOC}" ]] || fail "claude-code-hub example doc should exist"

assert_doc_contains "${USAGE_DOC}" "独立于具体研发项目" "usage doc should explain assistant positioning"
assert_doc_contains "${USAGE_DOC}" "remote.env" "usage doc should explain remote config"
assert_doc_contains "${USAGE_DOC}" "projects.yaml" "usage doc should explain project registry"
assert_doc_contains "${USAGE_DOC}" "Harbor" "usage doc should mention Harbor"
assert_doc_contains "${USAGE_DOC}" "远端" "usage doc should explain remote login responsibility"

assert_doc_contains "${EXAMPLE_DOC}" "claude-code-hub" "example doc should mention project name"
assert_doc_contains "${EXAMPLE_DOC}" "deploy/Dockerfile" "example doc should mention dockerfile path"
assert_doc_contains "${EXAMPLE_DOC}" "build_context" "example doc should mention build context"

printf 'PASS: docs smoke test\n'
