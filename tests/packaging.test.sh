#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSISTANT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"

# shellcheck source=../lib/packaging.sh
source "${ASSISTANT_ROOT}/lib/packaging.sh"

TEST_TMPDIR="$(mktemp -d "/tmp/packaging-test.XXXXXX")"
trap 'rm -rf "${TEST_TMPDIR}"' EXIT

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

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "${message}: missing '${needle}' in '${haystack}'"
  fi
}

create_case_project() {
  local root="$1"

  mkdir -p "${root}/deploy" "${root}/app" "${root}/.git" "${root}/node_modules" "${root}/.next"
  : > "${root}/deploy/Dockerfile"
  : > "${root}/package.json"
  : > "${root}/app/main.ts"
}

test_resolve_build_context_root() {
  local source_dir="${TEST_TMPDIR}/root-project"

  create_case_project "${source_dir}"

  assert_eq "$(resolve_build_context_path "${source_dir}" ".")" "${source_dir}" "root build context should resolve to source dir"
}

test_resolve_build_context_subdir() {
  local source_dir="${TEST_TMPDIR}/subdir-project"

  create_case_project "${source_dir}"

  assert_eq "$(resolve_build_context_path "${source_dir}" "app")" "${source_dir}/app" "subdir build context should resolve under source dir"
}

test_resolve_build_context_missing_fails() {
  local source_dir="${TEST_TMPDIR}/missing-context-project"

  create_case_project "${source_dir}"

  if resolve_build_context_path "${source_dir}" "missing-dir" >"${TEST_TMPDIR}/missing-context.out" 2>&1; then
    fail "missing build context should fail"
  fi

  grep -q "Build context directory not found" "${TEST_TMPDIR}/missing-context.out" || fail "missing build context failure should explain missing path"
}

test_resolve_build_context_rejects_path_escape() {
  local source_dir="${TEST_TMPDIR}/escape-context-project"

  create_case_project "${source_dir}"
  mkdir -p "${TEST_TMPDIR}/shared-context"

  if resolve_build_context_path "${source_dir}" "../shared-context" >"${TEST_TMPDIR}/escape-context.out" 2>&1; then
    fail "path-escaping build context should fail"
  fi

  grep -q "Build context must stay within source directory" "${TEST_TMPDIR}/escape-context.out" || fail "path-escaping build context failure should explain source-dir boundary"
}

test_create_build_context_archive_uses_root_context_contract() {
  local source_dir="${TEST_TMPDIR}/archive-root-project"
  local archive_path="${TEST_TMPDIR}/root-context.tar.gz"
  local tar_log="${TEST_TMPDIR}/root-tar.log"

  create_case_project "${source_dir}"

  tar() {
    printf '%s\n' "$*" > "${tar_log}"
  }

  create_build_context_archive "${source_dir}" "." "${archive_path}" >/dev/null
  unset -f tar

  assert_contains "$(cat "${tar_log}")" "-C ${source_dir}" "root context should archive from the source dir itself"
  assert_contains "$(cat "${tar_log}")" " ." "root context should archive the source dir contents"
  assert_contains "$(cat "${tar_log}")" "--exclude=./.git" "root context should exclude git directory"
  assert_contains "$(cat "${tar_log}")" "--exclude=./node_modules" "root context should exclude node_modules"
  assert_contains "$(cat "${tar_log}")" "--exclude=./.next" "root context should exclude next build output"
}

test_create_build_context_archive_uses_subdir_context_contract() {
  local source_dir="${TEST_TMPDIR}/archive-subdir-project"
  local archive_path="${TEST_TMPDIR}/subdir-context.tar.gz"
  local tar_log="${TEST_TMPDIR}/subdir-tar.log"

  create_case_project "${source_dir}"

  tar() {
    printf '%s\n' "$*" > "${tar_log}"
  }

  create_build_context_archive "${source_dir}" "app" "${archive_path}" >/dev/null
  unset -f tar

  assert_contains "$(cat "${tar_log}")" "-C ${source_dir}" "subdir context should archive relative to source dir"
  assert_contains "$(cat "${tar_log}")" "app" "subdir context should archive only requested subdir"
}

run_all_tests() {
  test_resolve_build_context_root
  test_resolve_build_context_subdir
  test_resolve_build_context_missing_fails
  test_resolve_build_context_rejects_path_escape
  test_create_build_context_archive_uses_root_context_contract
  test_create_build_context_archive_uses_subdir_context_contract
  printf 'PASS: packaging tests\n'
}

run_all_tests
