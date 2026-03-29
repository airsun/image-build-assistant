#!/usr/bin/env bash
set -euo pipefail

DEPLOY_REMOTE_EXEC_SCRIPT_DIR="${DEPLOY_REMOTE_EXEC_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

deploy_remote_exec_error() {
  printf '%s\n' "$*" >&2
}

deploy_remote_exec_log() {
  printf '%s\n' "$*" >&2
}

deploy_remote_exec_ssh_target() {
  printf '%s@%s' "${DEPLOY_USER}" "${DEPLOY_HOST}"
}

deploy_remote_exec_ssh_options() {
  printf '%s\n' \
    "-i" "${DEPLOY_SSH_KEY_PATH}" \
    "-p" "${DEPLOY_PORT}" \
    "-o" "BatchMode=yes"
}

deploy_remote_exec_scp_options() {
  printf '%s\n' \
    "-i" "${DEPLOY_SSH_KEY_PATH}" \
    "-P" "${DEPLOY_PORT}" \
    "-o" "BatchMode=yes"
}

deploy_remote_exec_shell_quote() {
  printf '%q' "$1"
}

deploy_remote_exec_check_remote_dir() {
  local remote_path="$1"

  ssh $(deploy_remote_exec_ssh_options) "$(deploy_remote_exec_ssh_target)" \
    "ls $(deploy_remote_exec_shell_quote "${remote_path}")" >/dev/null 2>&1
}

deploy_remote_exec_push() {
  local local_dir="$1"
  local remote_dir="$2"
  local force="${3:-}"
  local remote_parent_dir=""

  [[ -d "${local_dir}" ]] || {
    deploy_remote_exec_error "Local directory not found: ${local_dir}"
    return 1
  }

  if ssh $(deploy_remote_exec_ssh_options) "$(deploy_remote_exec_ssh_target)" \
    "test -d $(deploy_remote_exec_shell_quote "${remote_dir}")"; then
    if [[ "${force}" == "true" ]]; then
      deploy_remote_exec_log "Force-overwriting remote directory: ${remote_dir}"
      ssh $(deploy_remote_exec_ssh_options) "$(deploy_remote_exec_ssh_target)" \
        "rm -rf $(deploy_remote_exec_shell_quote "${remote_dir}")"
    else
      deploy_remote_exec_error "Remote directory already exists: ${remote_dir}"
      return 1
    fi
  fi

  remote_parent_dir="$(dirname "${remote_dir}")"
  ssh $(deploy_remote_exec_ssh_options) "$(deploy_remote_exec_ssh_target)" \
    "mkdir -p $(deploy_remote_exec_shell_quote "${remote_parent_dir}") $(deploy_remote_exec_shell_quote "${remote_dir}")"

  scp $(deploy_remote_exec_scp_options) -r \
    "${local_dir}/." \
    "$(deploy_remote_exec_ssh_target):${remote_dir}"

  printf '%s\n' "${remote_dir}"
}
