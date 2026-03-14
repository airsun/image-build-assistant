#!/usr/bin/env bash
set -euo pipefail

REMOTE_EXEC_SCRIPT_DIR="${REMOTE_EXEC_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

remote_exec_error() {
  printf '%s\n' "$*" >&2
}

remote_exec_ssh_target() {
  printf '%s@%s' "${REMOTE_USER}" "${REMOTE_HOST}"
}

remote_exec_ssh_options() {
  printf '%s\n' \
    "-i" "${SSH_KEY_PATH}" \
    "-p" "${REMOTE_PORT}" \
    "-o" "BatchMode=yes"
}

remote_exec_scp_options() {
  printf '%s\n' \
    "-i" "${SSH_KEY_PATH}" \
    "-P" "${REMOTE_PORT}" \
    "-o" "BatchMode=yes"
}

remote_exec_shell_quote() {
  printf '%q' "$1"
}

remote_exec_prepare_remote_base() {
  ssh $(remote_exec_ssh_options) "$(remote_exec_ssh_target)" \
    "mkdir -p $(remote_exec_shell_quote "${REMOTE_BASE_DIR}")"
}

remote_exec_upload_and_execute() {
  local archive_path="$1"
  local dockerfile_path="$2"
  local run_id="$3"
  local remote_archive_path="${REMOTE_BASE_DIR}/context-${run_id}.tar.gz"
  local remote_dockerfile_path="${REMOTE_BASE_DIR}/dockerfile-${run_id}"
  local remote_entry_path="${REMOTE_BASE_DIR}/remote-build-entry.sh"
  local remote_command=""

  [[ -f "${archive_path}" ]] || {
    remote_exec_error "Archive not found: ${archive_path}"
    return 1
  }

  [[ -f "${dockerfile_path}" ]] || {
    remote_exec_error "Dockerfile not found: ${dockerfile_path}"
    return 1
  }

  remote_exec_prepare_remote_base

  scp $(remote_exec_scp_options) \
    "${archive_path}" \
    "$(remote_exec_ssh_target):${remote_archive_path}"

  scp $(remote_exec_scp_options) \
    "${dockerfile_path}" \
    "$(remote_exec_ssh_target):${remote_dockerfile_path}"

  scp $(remote_exec_scp_options) \
    "${REMOTE_EXEC_SCRIPT_DIR}/remote-build-entry.sh" \
    "$(remote_exec_ssh_target):${remote_entry_path}"

  printf -v remote_command \
    'env REMOTE_BASE_DIR=%q RUN_ID=%q UPLOADED_ARCHIVE_PATH=%q UPLOADED_DOCKERFILE_PATH=%q DOCKERFILE_PATH=%q BUILD_CONTEXT=%q HARBOR_HOST=%q HARBOR_PROJECT=%q IMAGE_NAME=%q VERSION=%q PLATFORM=%q PUSH=%q bash %q' \
    "${REMOTE_BASE_DIR}" \
    "${run_id}" \
    "${remote_archive_path}" \
    "${remote_dockerfile_path}" \
    "${DOCKERFILE_PATH}" \
    "${BUILD_CONTEXT}" \
    "${HARBOR_HOST}" \
    "${HARBOR_PROJECT}" \
    "${IMAGE_NAME}" \
    "${VERSION}" \
    "${PLATFORM}" \
    "${PUSH}" \
    "${remote_entry_path}"

  ssh $(remote_exec_ssh_options) "$(remote_exec_ssh_target)" "${remote_command}"
}
