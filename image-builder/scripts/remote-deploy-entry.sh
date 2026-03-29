#!/usr/bin/env bash
set -euo pipefail

REMOTE_DEPLOY_ENTRY_LOG_PREFIX="[image-build-assistant]"

remote_deploy_entry_log() {
  printf '%s %s\n' "${REMOTE_DEPLOY_ENTRY_LOG_PREFIX}" "$*"
}

remote_deploy_entry_error() {
  printf '%s ERROR: %s\n' "${REMOTE_DEPLOY_ENTRY_LOG_PREFIX}" "$*" >&2
}

remote_deploy_entry_main() {
  local target_dir=""

  DEPLOY_BASE_DIR="${DEPLOY_BASE_DIR:-}"
  PROJECT_NAME="${PROJECT_NAME:-}"
  VERSION="${VERSION:-}"

  [[ -n "${DEPLOY_BASE_DIR}" ]] || {
    remote_deploy_entry_error "DEPLOY_BASE_DIR is required"
    return 1
  }
  [[ -n "${PROJECT_NAME}" ]] || {
    remote_deploy_entry_error "PROJECT_NAME is required"
    return 1
  }
  [[ -n "${VERSION}" ]] || {
    remote_deploy_entry_error "VERSION is required"
    return 1
  }

  target_dir="${DEPLOY_BASE_DIR}/${PROJECT_NAME}/${VERSION}"
  mkdir -p "${target_dir}"

  remote_deploy_entry_log "Listing received files in ${target_dir}"
  ls -la "${target_dir}"
  remote_deploy_entry_log "Remote deploy entry completed successfully"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  remote_deploy_entry_main "$@"
fi
