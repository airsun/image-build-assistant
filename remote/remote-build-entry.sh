#!/usr/bin/env bash
set -euo pipefail

REMOTE_ENTRY_LOG_PREFIX="[image-build-assistant]"
REMOTE_ENTRY_LOG_FILE=""
REMOTE_ENTRY_RUN_DIR=""
REMOTE_ENTRY_INCOMING_DIR=""
REMOTE_ENTRY_WORKSPACE_DIR=""
REMOTE_ENTRY_LOGS_DIR=""
REMOTE_ENTRY_CONTEXT_DIR=""
REMOTE_ENTRY_STAGED_ARCHIVE=""
REMOTE_ENTRY_STAGED_DOCKERFILE=""

remote_entry_timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

remote_entry_log() {
  local line

  line="$(remote_entry_timestamp) ${REMOTE_ENTRY_LOG_PREFIX} $*"
  printf '%s\n' "${line}"

  if [[ -n "${REMOTE_ENTRY_LOG_FILE}" ]]; then
    printf '%s\n' "${line}" >> "${REMOTE_ENTRY_LOG_FILE}"
  fi
}

remote_entry_error() {
  remote_entry_log "ERROR: $*"
}

remote_entry_clear_directory() {
  local target_dir="$1"
  local entries=()

  mkdir -p "${target_dir}"
  shopt -s nullglob dotglob
  entries=("${target_dir}"/*)
  shopt -u nullglob dotglob

  if (( ${#entries[@]} > 0 )); then
    rm -rf "${entries[@]}"
  fi
}

remote_entry_init() {
  REMOTE_BASE_DIR="${REMOTE_BASE_DIR:-}"
  RUN_ID="${RUN_ID:-}"
  UPLOADED_ARCHIVE_PATH="${UPLOADED_ARCHIVE_PATH:-}"
  UPLOADED_DOCKERFILE_PATH="${UPLOADED_DOCKERFILE_PATH:-}"
  DOCKERFILE_PATH="${DOCKERFILE_PATH:-}"
  BUILD_CONTEXT="${BUILD_CONTEXT:-.}"
  HARBOR_HOST="${HARBOR_HOST:-harbor.tech.skytech.io}"
  HARBOR_PROJECT="${HARBOR_PROJECT:-library}"
  IMAGE_NAME="${IMAGE_NAME:-image-build-assistant}"
  VERSION="${VERSION:-latest}"
  PLATFORM="${PLATFORM:-linux/amd64}"
  PUSH="${PUSH:-true}"

  [[ -n "${REMOTE_BASE_DIR}" ]] || {
    remote_entry_error "REMOTE_BASE_DIR is required"
    return 1
  }
  [[ -n "${RUN_ID}" ]] || {
    remote_entry_error "RUN_ID is required"
    return 1
  }
  [[ -n "${UPLOADED_ARCHIVE_PATH}" ]] || {
    remote_entry_error "UPLOADED_ARCHIVE_PATH is required"
    return 1
  }
  [[ -n "${UPLOADED_DOCKERFILE_PATH}" ]] || {
    remote_entry_error "UPLOADED_DOCKERFILE_PATH is required"
    return 1
  }
  [[ -n "${DOCKERFILE_PATH}" ]] || {
    remote_entry_error "DOCKERFILE_PATH is required"
    return 1
  }

  REMOTE_ENTRY_RUN_DIR="${REMOTE_BASE_DIR}/runs/${RUN_ID}"
  REMOTE_ENTRY_INCOMING_DIR="${REMOTE_ENTRY_RUN_DIR}/incoming"
  REMOTE_ENTRY_WORKSPACE_DIR="${REMOTE_ENTRY_RUN_DIR}/workspace"
  REMOTE_ENTRY_LOGS_DIR="${REMOTE_ENTRY_RUN_DIR}/logs"
  REMOTE_ENTRY_CONTEXT_DIR="${REMOTE_ENTRY_WORKSPACE_DIR}/context"

  mkdir -p "${REMOTE_ENTRY_INCOMING_DIR}" "${REMOTE_ENTRY_WORKSPACE_DIR}" "${REMOTE_ENTRY_LOGS_DIR}"

  REMOTE_ENTRY_LOG_FILE="${REMOTE_ENTRY_LOGS_DIR}/build-$(date '+%Y%m%d%H%M%S').log"
  : > "${REMOTE_ENTRY_LOG_FILE}"
}

remote_entry_stage_inputs() {
  local dockerfile_parent=""

  [[ -f "${UPLOADED_ARCHIVE_PATH}" ]] || {
    remote_entry_error "Uploaded archive not found: ${UPLOADED_ARCHIVE_PATH}"
    return 1
  }
  [[ -f "${UPLOADED_DOCKERFILE_PATH}" ]] || {
    remote_entry_error "Uploaded dockerfile not found: ${UPLOADED_DOCKERFILE_PATH}"
    return 1
  }

  remote_entry_clear_directory "${REMOTE_ENTRY_INCOMING_DIR}"

  REMOTE_ENTRY_STAGED_ARCHIVE="${REMOTE_ENTRY_INCOMING_DIR}/context.tar.gz"
  REMOTE_ENTRY_STAGED_DOCKERFILE="${REMOTE_ENTRY_INCOMING_DIR}/dockerfiles/${DOCKERFILE_PATH}"
  dockerfile_parent="$(dirname "${REMOTE_ENTRY_STAGED_DOCKERFILE}")"

  mkdir -p "${dockerfile_parent}"
  mv "${UPLOADED_ARCHIVE_PATH}" "${REMOTE_ENTRY_STAGED_ARCHIVE}"
  mv "${UPLOADED_DOCKERFILE_PATH}" "${REMOTE_ENTRY_STAGED_DOCKERFILE}"
}

remote_entry_unpack_context() {
  remote_entry_clear_directory "${REMOTE_ENTRY_WORKSPACE_DIR}"
  mkdir -p "${REMOTE_ENTRY_CONTEXT_DIR}"
  tar -xzf "${REMOTE_ENTRY_STAGED_ARCHIVE}" -C "${REMOTE_ENTRY_CONTEXT_DIR}"
}

remote_entry_resolve_context_dir() {
  if [[ "${BUILD_CONTEXT}" == "." ]]; then
    printf '%s\n' "${REMOTE_ENTRY_CONTEXT_DIR}"
  else
    printf '%s\n' "${REMOTE_ENTRY_CONTEXT_DIR}/${BUILD_CONTEXT}"
  fi
}

remote_entry_run_build() {
  local full_image="${HARBOR_HOST}/${HARBOR_PROJECT}/${IMAGE_NAME}"
  local context_dir=""

  context_dir="$(remote_entry_resolve_context_dir)"

  [[ -d "${context_dir}" ]] || {
    remote_entry_error "Resolved build context not found: ${context_dir}"
    return 1
  }

  remote_entry_log "Building image ${full_image}:${VERSION}"
  docker build \
    --platform "${PLATFORM}" \
    -f "${REMOTE_ENTRY_STAGED_DOCKERFILE}" \
    -t "${full_image}:${VERSION}" \
    -t "${full_image}:latest" \
    "${context_dir}"

  if [[ "${PUSH}" == "true" ]]; then
    remote_entry_log "Pushing image ${full_image}:${VERSION}"
    docker push "${full_image}:${VERSION}"
    docker push "${full_image}:latest"
  fi
}

remote_entry_cleanup() {
  local status="${1:-0}"

  set +e
  if [[ -n "${REMOTE_ENTRY_WORKSPACE_DIR}" && -d "${REMOTE_ENTRY_WORKSPACE_DIR}" ]]; then
    remote_entry_clear_directory "${REMOTE_ENTRY_WORKSPACE_DIR}"
  fi
  if [[ -n "${REMOTE_ENTRY_INCOMING_DIR}" && -d "${REMOTE_ENTRY_INCOMING_DIR}" ]]; then
    remote_entry_clear_directory "${REMOTE_ENTRY_INCOMING_DIR}"
  fi
  if [[ -n "${UPLOADED_ARCHIVE_PATH:-}" && -f "${UPLOADED_ARCHIVE_PATH}" ]]; then
    rm -f "${UPLOADED_ARCHIVE_PATH}"
  fi
  if [[ -n "${UPLOADED_DOCKERFILE_PATH:-}" && -f "${UPLOADED_DOCKERFILE_PATH}" ]]; then
    rm -f "${UPLOADED_DOCKERFILE_PATH}"
  fi
  if [[ -n "${REMOTE_ENTRY_STAGED_ARCHIVE}" && -f "${REMOTE_ENTRY_STAGED_ARCHIVE}" ]]; then
    rm -f "${REMOTE_ENTRY_STAGED_ARCHIVE}"
  fi
  if [[ -n "${REMOTE_ENTRY_STAGED_DOCKERFILE}" && -f "${REMOTE_ENTRY_STAGED_DOCKERFILE}" ]]; then
    rm -f "${REMOTE_ENTRY_STAGED_DOCKERFILE}"
  fi
  set -e

  if [[ "${status}" -eq 0 ]]; then
    remote_entry_log "Cleanup complete"
  else
    remote_entry_log "Cleanup complete after failure"
  fi
}

remote_entry_main() {
  local status=0

  remote_entry_init || return $?
  trap 'status=$?; remote_entry_cleanup "${status}"; exit "${status}"' EXIT

  remote_entry_log "Preparing remote build workspace under ${REMOTE_BASE_DIR}"
  remote_entry_stage_inputs
  remote_entry_unpack_context
  remote_entry_run_build
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  remote_entry_main "$@"
fi
