#!/usr/bin/env bash
set -euo pipefail

BUILD_IMAGE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_IMAGE_ASSISTANT_ROOT="$(cd "${BUILD_IMAGE_SCRIPT_DIR}/.." && pwd)"
BUILD_IMAGE_DEFAULT_CONFIG="${BUILD_IMAGE_SCRIPT_DIR}/remote.env"
BUILD_IMAGE_DEFAULT_PROJECTS="${BUILD_IMAGE_SCRIPT_DIR}/projects.yaml"
BUILD_IMAGE_LOG_PREFIX="[image-build-assistant]"

# shellcheck source=scripts/project-resolver.sh
source "${BUILD_IMAGE_SCRIPT_DIR}/scripts/project-resolver.sh"
# shellcheck source=scripts/packaging.sh
source "${BUILD_IMAGE_SCRIPT_DIR}/scripts/packaging.sh"
# shellcheck source=scripts/remote-exec.sh
source "${BUILD_IMAGE_SCRIPT_DIR}/scripts/remote-exec.sh"

build_image_log() {
  printf '%s %s\n' "${BUILD_IMAGE_LOG_PREFIX}" "$*"
}

build_image_error() {
  printf '%s ERROR: %s\n' "${BUILD_IMAGE_LOG_PREFIX}" "$*" >&2
}

build_image_die() {
  build_image_error "$*"
  return 1 2>/dev/null || exit 1
}

build_image_reset_state() {
  CONFIG_PATH="${BUILD_IMAGE_DEFAULT_CONFIG}"
  PROJECTS_PATH="${BUILD_IMAGE_DEFAULT_PROJECTS}"
  REQUESTED_PROJECT=""
  REQUESTED_SOURCE_DIR=""
  REQUESTED_DOCKERFILE_PATH=""
  REQUESTED_BUILD_CONTEXT=""
  REQUESTED_IMAGE_NAME=""
  REQUESTED_HARBOR_PROJECT=""
  REQUESTED_VERSION=""
  REQUESTED_PLATFORM=""
  REQUESTED_PUSH=""
  REQUESTED_ENV=""
  BUILD_ARGS=""
}

build_image_load_remote_config() {
  local config_path="$1"

  [[ -f "${config_path}" ]] || {
    build_image_die "Config file not found: ${config_path}"
    return 1
  }

  # shellcheck disable=SC1090
  source "${config_path}"

  # These are per-project/per-build settings, not remote config.
  # Unset to prevent source residue from polluting merge_project_settings().
  unset IMAGE_NAME VERSION

  DEPLOY_HOST="${DEPLOY_HOST:-}"
  DEPLOY_PORT="${DEPLOY_PORT:-22}"
  DEPLOY_USER="${DEPLOY_USER:-}"
  DEPLOY_SSH_KEY_PATH="${DEPLOY_SSH_KEY_PATH:-}"
  DEPLOY_BASE_DIR="${DEPLOY_BASE_DIR:-}"
  REMOTE_HOST="${REMOTE_HOST:-}"
  REMOTE_PORT="${REMOTE_PORT:-22}"
  REMOTE_USER="${REMOTE_USER:-}"
  SSH_KEY_PATH="${SSH_KEY_PATH:-}"
  REMOTE_BASE_DIR="${REMOTE_BASE_DIR:-}"
  HARBOR_HOST="${HARBOR_HOST:-}"
  DEFAULT_HARBOR_PROJECT="${HARBOR_PROJECT:-library}"
  DEFAULT_PLATFORM="${PLATFORM:-linux/amd64}"
  PUSH="${PUSH:-true}"

  [[ -n "${REMOTE_HOST}" ]] || {
    build_image_die "Missing required remote config: REMOTE_HOST"
    return 1
  }
  [[ -n "${REMOTE_USER}" ]] || {
    build_image_die "Missing required remote config: REMOTE_USER"
    return 1
  }
  [[ -n "${SSH_KEY_PATH}" ]] || {
    build_image_die "Missing required remote config: SSH_KEY_PATH"
    return 1
  }
  [[ -n "${REMOTE_BASE_DIR}" ]] || {
    build_image_die "Missing required remote config: REMOTE_BASE_DIR"
    return 1
  }
}

build_image_parse_args() {
  while (($# > 0)); do
    case "$1" in
      --config)
        CONFIG_PATH="$2"
        shift 2
        ;;
      --projects)
        PROJECTS_PATH="$2"
        shift 2
        ;;
      --project)
        REQUESTED_PROJECT="$2"
        shift 2
        ;;
      --source-dir)
        REQUESTED_SOURCE_DIR="$2"
        shift 2
        ;;
      --dockerfile-path)
        REQUESTED_DOCKERFILE_PATH="$2"
        shift 2
        ;;
      --build-context)
        REQUESTED_BUILD_CONTEXT="$2"
        shift 2
        ;;
      --image-name)
        REQUESTED_IMAGE_NAME="$2"
        shift 2
        ;;
      --harbor-project)
        REQUESTED_HARBOR_PROJECT="$2"
        shift 2
        ;;
      --version)
        REQUESTED_VERSION="$2"
        shift 2
        ;;
      --platform)
        REQUESTED_PLATFORM="$2"
        shift 2
        ;;
      --push)
        REQUESTED_PUSH="$2"
        shift 2
        ;;
      --env)
        REQUESTED_ENV="$2"
        shift 2
        ;;
      *)
        build_image_die "Unknown argument: $1"
        return 1
        ;;
    esac
  done
}

build_image_make_run_id() {
  local now="${BUILD_IMAGE_NOW:-$(date '+%Y%m%d%H%M%S')}"
  local pid="${BUILD_IMAGE_PID:-$$}"
  local nonce="${BUILD_IMAGE_NONCE:-$(date '+%N')}"

  if [[ -n "${BUILD_IMAGE_RUN_ID:-}" ]]; then
    printf '%s\n' "${BUILD_IMAGE_RUN_ID}"
  else
    printf 'run-%s-%s-%s\n' "${now}" "${pid}" "${nonce}"
  fi
}

build_image_apply_manual_project() {
  project_resolver_clear
  PROJECT_NAME="${REQUESTED_PROJECT:-manual}"
  SOURCE_DIR="${REQUESTED_SOURCE_DIR}"
  DOCKERFILE_PATH="${REQUESTED_DOCKERFILE_PATH}"
  BUILD_CONTEXT="${REQUESTED_BUILD_CONTEXT}"
  IMAGE_NAME="${REQUESTED_IMAGE_NAME}"
  HARBOR_PROJECT="${REQUESTED_HARBOR_PROJECT}"
  PLATFORM="${REQUESTED_PLATFORM}"
  ENABLED="true"
  BUILD_ARGS=""
}

build_image_normalize_dockerfile_path() {
  local raw_dockerfile_path="$1"
  local source_realpath=""
  local dockerfile_realpath=""

  source_realpath="$(cd "${SOURCE_DIR}" && pwd)"
  dockerfile_realpath="$(cd "$(dirname "${source_realpath}/${raw_dockerfile_path}")" 2>/dev/null && pwd)/$(basename "${raw_dockerfile_path}")"

  case "${dockerfile_realpath}" in
    "${source_realpath}"|"${source_realpath}"/*)
      printf '%s\n' "${dockerfile_realpath#${source_realpath}/}"
      ;;
    *)
      build_image_die "Dockerfile path must stay within source directory: ${raw_dockerfile_path}"
      return 1
      ;;
  esac
}

build_image_resolve_project() {
  if [[ -n "${REQUESTED_SOURCE_DIR}" ]]; then
    [[ -n "${REQUESTED_DOCKERFILE_PATH}" ]] || {
      build_image_die "--dockerfile-path is required with --source-dir"
      return 1
    }
    [[ -n "${REQUESTED_BUILD_CONTEXT}" ]] || {
      build_image_die "--build-context is required with --source-dir"
      return 1
    }
    build_image_apply_manual_project
    return
  fi

  [[ -n "${REQUESTED_PROJECT}" ]] || {
    build_image_die "Either --project or --source-dir is required"
    return 1
  }
  resolve_project_by_name "${PROJECTS_PATH}" "${REQUESTED_PROJECT}" "${REQUESTED_ENV}" || return 1
}

build_image_merge_settings() {
  DEFAULT_IMAGE_NAME="${DEFAULT_IMAGE_NAME:-$(basename "${SOURCE_DIR}")}"
  OVERRIDE_IMAGE_NAME="${REQUESTED_IMAGE_NAME}"
  OVERRIDE_HARBOR_PROJECT="${REQUESTED_HARBOR_PROJECT}"
  OVERRIDE_PLATFORM="${REQUESTED_PLATFORM}"

  merge_project_settings

  VERSION="${REQUESTED_VERSION:-${VERSION}}"
  PUSH="${REQUESTED_PUSH:-${PUSH}}"
}

build_image_validate_enabled_state() {
  case "${ENABLED:-true}" in
    true|yes|1|"")
      ;;
    *)
      build_image_die "Project is disabled: ${PROJECT_NAME}"
      return 1
      ;;
  esac
}

build_image_validate_inputs() {
  local dockerfile_abspath=""

  validate_project_settings || return $?
  DOCKERFILE_PATH="$(build_image_normalize_dockerfile_path "${DOCKERFILE_PATH}")" || return 1
  dockerfile_abspath="${SOURCE_DIR}/${DOCKERFILE_PATH}"
  [[ -f "${dockerfile_abspath}" ]] || {
    build_image_die "Dockerfile not found: ${dockerfile_abspath}"
    return 1
  }
}

build_image_setup_logging() {
  local log_dir="${BUILD_IMAGE_SCRIPT_DIR}/logs/${PROJECT_NAME}"
  local log_timestamp="${BUILD_IMAGE_NOW:-$(date '+%Y%m%d-%H%M%S')}"
  BUILD_IMAGE_LOG_FILE="${log_dir}/${log_timestamp}.log"

  mkdir -p "${log_dir}"
  exec > >(tee -a "${BUILD_IMAGE_LOG_FILE}") 2>&1

  build_image_log "Log file: ${BUILD_IMAGE_LOG_FILE}"
}

build_image_main() {
  local archive_path=""
  local dockerfile_abspath=""
  local run_id=""

  build_image_reset_state
  build_image_parse_args "$@" || return 1
  build_image_load_remote_config "${CONFIG_PATH}" || return 1
  build_image_resolve_project || return 1
  build_image_validate_enabled_state || return 1
  build_image_merge_settings
  build_image_validate_inputs || return 1

  build_image_setup_logging

  dockerfile_abspath="${SOURCE_DIR}/${DOCKERFILE_PATH}"
  run_id="$(build_image_make_run_id)"
  archive_path="$(mktemp "/tmp/image-build-context-${run_id}.XXXXXX.tar.gz")"
  trap "rm -f $(printf '%q' "${archive_path}")" RETURN

  build_image_log "Packaging ${PROJECT_NAME} from ${SOURCE_DIR}"
  create_build_context_archive "${SOURCE_DIR}" "${BUILD_CONTEXT}" "${archive_path}" >/dev/null

  build_image_log "Executing remote build for ${IMAGE_NAME}:${VERSION}"
  remote_exec_upload_and_execute "${archive_path}" "${dockerfile_abspath}" "${run_id}"

  build_image_log "Remote build complete for ${IMAGE_NAME}:${VERSION}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  build_image_main "$@"
fi
