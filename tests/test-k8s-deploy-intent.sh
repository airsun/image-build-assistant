#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSISTANT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
PROJECTS_PATH="${ASSISTANT_ROOT}/image-builder/projects.yaml"

# shellcheck source=../image-builder/scripts/project-resolver.sh
source "${ASSISTANT_ROOT}/image-builder/scripts/project-resolver.sh"

TEST_TMPDIR="$(mktemp -d "/tmp/test-k8s-deploy-intent.XXXXXX")"
trap 'rm -rf "${TEST_TMPDIR}"' EXIT

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
FAIL_MESSAGE=""
RUN_OUTPUT=""
RUN_STATUS=0

fail_test() {
  FAIL_MESSAGE="$*"
  return 1
}

assert_eq() {
  local actual="${1-}"
  local expected="${2-}"
  local message="${3-assert_eq failed}"

  if [[ "${actual}" != "${expected}" ]]; then
    fail_test "${message}: expected '${expected}', got '${actual}'"
  fi
}

assert_empty() {
  local value="${1-}"
  local message="${2-assert_empty failed}"

  if [[ -n "${value}" ]]; then
    fail_test "${message}: expected empty value, got '${value}'"
  fi
}

assert_contains() {
  local haystack="${1-}"
  local needle="${2-}"
  local message="${3-assert_contains failed}"

  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail_test "${message}: missing '${needle}' in '${haystack}'"
  fi
}

assert_file_exists() {
  local path="${1-}"
  local message="${2-assert_file_exists failed}"

  if [[ ! -f "${path}" ]]; then
    fail_test "${message}: missing file '${path}'"
  fi
}

assert_file_nonempty() {
  local path="${1-}"
  local message="${2-assert_file_nonempty failed}"

  if [[ ! -s "${path}" ]]; then
    fail_test "${message}: expected non-empty file '${path}'"
  fi
}

assert_executable() {
  local path="${1-}"
  local message="${2-assert_executable failed}"

  if [[ ! -x "${path}" ]]; then
    fail_test "${message}: expected executable path '${path}'"
  fi
}

run_test() {
  local description="$1"
  shift

  TEST_COUNT=$((TEST_COUNT + 1))
  FAIL_MESSAGE=""

  if "$@"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf 'ok %s - %s\n' "${TEST_COUNT}" "${description}"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf 'not ok %s - %s\n' "${TEST_COUNT}" "${description}"
    if [[ -n "${FAIL_MESSAGE}" ]]; then
      printf '# %s\n' "${FAIL_MESSAGE}"
    fi
  fi
}

resolve_project_fixture() {
  local project_name="$1"

  project_resolver_clear
  if ! resolve_project_by_name "${PROJECTS_PATH}" "${project_name}" >/dev/null 2>&1; then
    fail_test "failed to resolve project '${project_name}' from ${PROJECTS_PATH}"
  fi
}

run_deploy_shell() {
  local mode="$1"
  shift
  local output=""
  local status=0

  if output="$(
    bash -c '
      set -euo pipefail
      repo_root="$1"
      mode="$2"
      shift 2

      source "${repo_root}/image-builder/deploy.sh"

      set +e +u

      case "${mode}" in
        validate_path_segment)
          deploy_push_validate_path_segment "${1-}" "${2-label}"
          exit $?
          ;;
        validate_inputs)
          REQUESTED_DEPLOY_DIR="${1-}"
          deploy_push_validate_inputs
          exit $?
          ;;
        resolve_project_gate)
          PROJECTS_PATH="${repo_root}/image-builder/projects.yaml"
          REQUESTED_PROJECT="${1-}"
          deploy_push_resolve_project
          status=$?
          if [[ ${status} -eq 0 ]]; then
            printf "%s\n" "${DEPLOY_INTENT}"
          fi
          exit ${status}
          ;;
        *)
          printf "unknown mode: %s\n" "${mode}" >&2
          exit 2
          ;;
      esac
    ' bash "${ASSISTANT_ROOT}" "${mode}" "$@" 2>&1
  )"; then
    RUN_OUTPUT="${output}"
    RUN_STATUS=0
    return 0
  fi

  status=$?
  RUN_OUTPUT="${output}"
  RUN_STATUS=${status}
  return "${status}"
}

test_t1_resolve_claude_code_hub_neo_deploy_fields() {
  resolve_project_fixture "claude-code-hub-neo" || return 1
  assert_eq "${DEPLOY_INTENT}" "k8s" "claude-code-hub-neo DEPLOY_INTENT should match" || return 1
  assert_eq "${DEPLOY_NAMESPACE}" "claude-hub" "claude-code-hub-neo DEPLOY_NAMESPACE should match" || return 1
  assert_eq "${DEPLOY_CLUSTER}" "default" "claude-code-hub-neo DEPLOY_CLUSTER should match" || return 1
  assert_eq "${DEPLOY_DOMAIN}" "hub.ai.internal" "claude-code-hub-neo DEPLOY_DOMAIN should match" || return 1
  assert_eq "${DEPLOY_CONTAINER_PORT}" "3000" "claude-code-hub-neo DEPLOY_CONTAINER_PORT should match" || return 1
}

test_t1_resolve_claude_code_hub_empty_deploy_fields() {
  resolve_project_fixture "claude-code-hub" || return 1
  assert_empty "${DEPLOY_INTENT}" "claude-code-hub DEPLOY_INTENT should be empty" || return 1
  assert_empty "${DEPLOY_NAMESPACE}" "claude-code-hub DEPLOY_NAMESPACE should be empty" || return 1
  assert_empty "${DEPLOY_CLUSTER}" "claude-code-hub DEPLOY_CLUSTER should be empty" || return 1
  assert_empty "${DEPLOY_DOMAIN}" "claude-code-hub DEPLOY_DOMAIN should be empty" || return 1
  assert_empty "${DEPLOY_CONTAINER_PORT}" "claude-code-hub DEPLOY_CONTAINER_PORT should be empty" || return 1
}

test_t1_resolve_vl_demo_empty_deploy_fields() {
  resolve_project_fixture "vl-demo" || return 1
  assert_empty "${DEPLOY_INTENT}" "vl-demo DEPLOY_INTENT should be empty" || return 1
  assert_empty "${DEPLOY_NAMESPACE}" "vl-demo DEPLOY_NAMESPACE should be empty" || return 1
  assert_empty "${DEPLOY_CLUSTER}" "vl-demo DEPLOY_CLUSTER should be empty" || return 1
  assert_empty "${DEPLOY_DOMAIN}" "vl-demo DEPLOY_DOMAIN should be empty" || return 1
  assert_empty "${DEPLOY_CONTAINER_PORT}" "vl-demo DEPLOY_CONTAINER_PORT should be empty" || return 1
}

test_t1_existing_build_fields_claude_code_hub() {
  resolve_project_fixture "claude-code-hub" || return 1
  assert_eq "${IMAGE_NAME}" "claude-code-hub" "claude-code-hub IMAGE_NAME should still resolve" || return 1
  assert_eq "${VERSION}" "1.0.2" "claude-code-hub VERSION should still resolve" || return 1
  assert_eq "${HARBOR_PROJECT}" "ai.infra" "claude-code-hub HARBOR_PROJECT should still resolve" || return 1
}

test_t1_existing_build_fields_claude_code_hub_neo() {
  resolve_project_fixture "claude-code-hub-neo" || return 1
  assert_eq "${IMAGE_NAME}" "claude-code-hub-neo" "claude-code-hub-neo IMAGE_NAME should still resolve" || return 1
  assert_eq "${VERSION}" "0.6.7" "claude-code-hub-neo VERSION should still resolve" || return 1
  assert_eq "${HARBOR_PROJECT}" "ai.infra" "claude-code-hub-neo HARBOR_PROJECT should still resolve" || return 1
}

test_t1_existing_build_fields_vl_demo() {
  resolve_project_fixture "vl-demo" || return 1
  assert_eq "${IMAGE_NAME}" "zzt-form-extractor" "vl-demo IMAGE_NAME should still resolve" || return 1
  assert_eq "${VERSION}" "v-0.1.5" "vl-demo VERSION should still resolve" || return 1
  assert_eq "${HARBOR_PROJECT}" "tax" "vl-demo HARBOR_PROJECT should still resolve" || return 1
}

test_t2_validate_path_segment_accepts_valid_input() {
  if ! run_deploy_shell validate_path_segment "normal-name" "project name"; then
    fail_test "expected deploy_push_validate_path_segment to accept 'normal-name'; output: ${RUN_OUTPUT}"
  fi
}

test_t2_validate_path_segment_rejects_invalid_input() {
  if run_deploy_shell validate_path_segment "has/slash" "project name"; then
    fail_test "expected deploy_push_validate_path_segment to reject 'has/slash'"
  fi

  assert_contains "${RUN_OUTPUT}" "Invalid project name: has/slash" "invalid path segment error should explain failure" || return 1
}

test_t2_validate_inputs_rejects_empty_directory() {
  local empty_dir="${TEST_TMPDIR}/deploy-empty"

  mkdir -p "${empty_dir}"

  if run_deploy_shell validate_inputs "${empty_dir}"; then
    fail_test "expected deploy_push_validate_inputs to reject an empty deploy directory"
  fi

  assert_contains "${RUN_OUTPUT}" "No YAML files found in deploy directory" "empty deploy directory should fail with YAML error" || return 1
}

test_t2_validate_inputs_accepts_directory_with_yaml() {
  local valid_dir="${TEST_TMPDIR}/deploy-yaml"

  mkdir -p "${valid_dir}"
  printf 'apiVersion: v1\nkind: ConfigMap\n' > "${valid_dir}/manifest.yaml"

  if ! run_deploy_shell validate_inputs "${valid_dir}"; then
    fail_test "expected deploy_push_validate_inputs to accept a directory with YAML; output: ${RUN_OUTPUT}"
  fi
}

test_t3_gating_allows_k8s_intent() {
  if ! run_deploy_shell resolve_project_gate "claude-code-hub-neo"; then
    fail_test "expected deploy_push_resolve_project to allow claude-code-hub-neo; output: ${RUN_OUTPUT}"
  fi

  assert_eq "${RUN_OUTPUT}" "k8s" "gating should keep claude-code-hub-neo deploy intent as k8s" || return 1
}

test_t3_gating_rejects_missing_intent_as_none() {
  if run_deploy_shell resolve_project_gate "claude-code-hub"; then
    fail_test "expected deploy_push_resolve_project to reject claude-code-hub without deploy intent"
  fi

  assert_contains "${RUN_OUTPUT}" "intent=none" "missing deploy intent should normalize to none during gating" || return 1
}

test_t4_path_segment_normal_name_passes() {
  if ! run_deploy_shell validate_path_segment "normal-name" "deploy version"; then
    fail_test "expected 'normal-name' to pass path segment validation; output: ${RUN_OUTPUT}"
  fi
}

test_t4_path_segment_empty_fails() {
  if run_deploy_shell validate_path_segment "" "deploy version"; then
    fail_test "expected empty path segment to fail validation"
  fi

  assert_contains "${RUN_OUTPUT}" "Invalid deploy version:" "empty path segment failure should be reported" || return 1
}

test_t4_path_segment_dot_fails() {
  if run_deploy_shell validate_path_segment "." "deploy version"; then
    fail_test "expected '.' to fail validation"
  fi

  assert_contains "${RUN_OUTPUT}" "Invalid deploy version: ." "dot path segment failure should be reported" || return 1
}

test_t4_path_segment_dot_dot_fails() {
  if run_deploy_shell validate_path_segment ".." "deploy version"; then
    fail_test "expected '..' to fail validation"
  fi

  assert_contains "${RUN_OUTPUT}" "Invalid deploy version: .." "dot-dot path segment failure should be reported" || return 1
}

test_t4_path_segment_space_fails() {
  if run_deploy_shell validate_path_segment "has space" "deploy version"; then
    fail_test "expected 'has space' to fail validation"
  fi

  assert_contains "${RUN_OUTPUT}" "Invalid deploy version: has space" "space-containing path segment failure should be reported" || return 1
}

test_t4_path_segment_slash_fails() {
  if run_deploy_shell validate_path_segment "has/slash" "deploy version"; then
    fail_test "expected 'has/slash' to fail validation"
  fi

  assert_contains "${RUN_OUTPUT}" "Invalid deploy version: has/slash" "slash-containing path segment failure should be reported" || return 1
}

test_t5_backward_compatibility_claude_code_hub() {
  resolve_project_fixture "claude-code-hub" || return 1
  assert_eq "${IMAGE_NAME}" "claude-code-hub" "claude-code-hub IMAGE_NAME should remain unchanged" || return 1
  assert_eq "${VERSION}" "1.0.2" "claude-code-hub VERSION should remain unchanged" || return 1
}

test_t5_backward_compatibility_vl_demo() {
  resolve_project_fixture "vl-demo" || return 1
  assert_eq "${IMAGE_NAME}" "zzt-form-extractor" "vl-demo IMAGE_NAME should remain unchanged" || return 1
  assert_eq "${VERSION}" "v-0.1.5" "vl-demo VERSION should remain unchanged" || return 1
}

test_t6_deploy_conventions_exists_and_nonempty() {
  assert_file_nonempty "${ASSISTANT_ROOT}/image-builder/deploy-conventions.md" "deploy conventions document should exist and be non-empty"
}

test_t6_claude_code_hub_neo_doc_exists_and_nonempty() {
  assert_file_nonempty "${ASSISTANT_ROOT}/image-builder/projects/claude-code-hub-neo.md" "claude-code-hub-neo project document should exist and be non-empty"
}

test_t6_deploys_gitignore_exists() {
  assert_file_exists "${ASSISTANT_ROOT}/image-builder/deploys/.gitignore" "deploys .gitignore should exist"
}

test_t6_deploy_script_is_executable() {
  assert_executable "${ASSISTANT_ROOT}/image-builder/deploy.sh" "deploy.sh should be executable"
}

test_t6_deploy_remote_exec_exists() {
  assert_file_exists "${ASSISTANT_ROOT}/image-builder/scripts/deploy-remote-exec.sh" "deploy-remote-exec.sh should exist"
}

test_t6_remote_deploy_entry_exists() {
  assert_file_exists "${ASSISTANT_ROOT}/image-builder/scripts/remote-deploy-entry.sh" "remote-deploy-entry.sh should exist"
}

main() {
  printf 'TAP version 13\n'

  run_test "T1 resolves claude-code-hub-neo deploy fields" test_t1_resolve_claude_code_hub_neo_deploy_fields
  run_test "T1 resolves empty deploy fields for claude-code-hub" test_t1_resolve_claude_code_hub_empty_deploy_fields
  run_test "T1 resolves empty deploy fields for vl-demo" test_t1_resolve_vl_demo_empty_deploy_fields
  run_test "T1 keeps build fields for claude-code-hub" test_t1_existing_build_fields_claude_code_hub
  run_test "T1 keeps build fields for claude-code-hub-neo" test_t1_existing_build_fields_claude_code_hub_neo
  run_test "T1 keeps build fields for vl-demo" test_t1_existing_build_fields_vl_demo

  run_test "T2 validate_path_segment accepts a valid input" test_t2_validate_path_segment_accepts_valid_input
  run_test "T2 validate_path_segment rejects an invalid input" test_t2_validate_path_segment_rejects_invalid_input
  run_test "T2 validate_inputs rejects an empty deploy directory" test_t2_validate_inputs_rejects_empty_directory
  run_test "T2 validate_inputs accepts a deploy directory with YAML" test_t2_validate_inputs_accepts_directory_with_yaml

  run_test "T3 gating allows projects with k8s deploy intent" test_t3_gating_allows_k8s_intent
  run_test "T3 gating normalizes missing deploy intent to none and rejects it" test_t3_gating_rejects_missing_intent_as_none

  run_test "T4 path validation accepts normal-name" test_t4_path_segment_normal_name_passes
  run_test "T4 path validation rejects an empty string" test_t4_path_segment_empty_fails
  run_test "T4 path validation rejects dot" test_t4_path_segment_dot_fails
  run_test "T4 path validation rejects dot-dot" test_t4_path_segment_dot_dot_fails
  run_test "T4 path validation rejects spaces" test_t4_path_segment_space_fails
  run_test "T4 path validation rejects slashes" test_t4_path_segment_slash_fails

  run_test "T5 keeps claude-code-hub build fields backward-compatible" test_t5_backward_compatibility_claude_code_hub
  run_test "T5 keeps vl-demo build fields backward-compatible" test_t5_backward_compatibility_vl_demo

  run_test "T6 deploy-conventions.md exists and is non-empty" test_t6_deploy_conventions_exists_and_nonempty
  run_test "T6 claude-code-hub-neo project doc exists and is non-empty" test_t6_claude_code_hub_neo_doc_exists_and_nonempty
  run_test "T6 deploys/.gitignore exists" test_t6_deploys_gitignore_exists
  run_test "T6 deploy.sh is executable" test_t6_deploy_script_is_executable
  run_test "T6 scripts/deploy-remote-exec.sh exists" test_t6_deploy_remote_exec_exists
  run_test "T6 scripts/remote-deploy-entry.sh exists" test_t6_remote_deploy_entry_exists

  printf '1..%s\n' "${TEST_COUNT}"
  printf '# Tests: %s, Passed: %s, Failed: %s\n' "${TEST_COUNT}" "${PASS_COUNT}" "${FAIL_COUNT}"

  if (( FAIL_COUNT == 0 )); then
    exit 0
  fi

  exit 1
}

main "$@"
