#!/usr/bin/env bash
set -euo pipefail

DEPLOY_PUSH_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_PUSH_ASSISTANT_ROOT="$(cd "${DEPLOY_PUSH_SCRIPT_DIR}/.." && pwd)"
DEPLOY_PUSH_DEFAULT_CONFIG="${DEPLOY_PUSH_SCRIPT_DIR}/remote.env"
DEPLOY_PUSH_DEFAULT_PROJECTS="${DEPLOY_PUSH_SCRIPT_DIR}/projects.yaml"
DEPLOY_PUSH_LOG_PREFIX="[image-build-assistant]"

# shellcheck source=scripts/project-resolver.sh
source "${DEPLOY_PUSH_SCRIPT_DIR}/scripts/project-resolver.sh"
# shellcheck source=scripts/deploy-remote-exec.sh
source "${DEPLOY_PUSH_SCRIPT_DIR}/scripts/deploy-remote-exec.sh"

deploy_push_log() {
  printf '%s %s\n' "${DEPLOY_PUSH_LOG_PREFIX}" "$*"
}

deploy_push_error() {
  printf '%s ERROR: %s\n' "${DEPLOY_PUSH_LOG_PREFIX}" "$*" >&2
}

deploy_push_die() {
  deploy_push_error "$*"
  return 1 2>/dev/null || exit 1
}

deploy_push_reset_state() {
  CONFIG_PATH="${DEPLOY_PUSH_DEFAULT_CONFIG}"
  PROJECTS_PATH="${DEPLOY_PUSH_DEFAULT_PROJECTS}"
  REQUESTED_PROJECT=""
  REQUESTED_DEPLOY_DIR=""
  REQUESTED_FORCE=""
  REQUESTED_ENV=""
}

deploy_push_load_remote_config() {
  local config_path="$1"

  [[ -f "${config_path}" ]] || {
    deploy_push_die "Config file not found: ${config_path}"
    return 1
  }

  # shellcheck disable=SC1090
  source "${config_path}"

  unset IMAGE_NAME VERSION

  DEPLOY_HOST="${DEPLOY_HOST:-}"
  DEPLOY_PORT="${DEPLOY_PORT:-22}"
  DEPLOY_USER="${DEPLOY_USER:-}"
  DEPLOY_SSH_KEY_PATH="${DEPLOY_SSH_KEY_PATH:-}"
  DEPLOY_BASE_DIR="${DEPLOY_BASE_DIR:-}"

  [[ -n "${DEPLOY_HOST}" ]] || {
    deploy_push_die "Missing required remote config: DEPLOY_HOST"
    return 1
  }
  [[ -n "${DEPLOY_USER}" ]] || {
    deploy_push_die "Missing required remote config: DEPLOY_USER"
    return 1
  }
  [[ -n "${DEPLOY_SSH_KEY_PATH}" ]] || {
    deploy_push_die "Missing required remote config: DEPLOY_SSH_KEY_PATH"
    return 1
  }
  [[ -n "${DEPLOY_BASE_DIR}" ]] || {
    deploy_push_die "Missing required remote config: DEPLOY_BASE_DIR"
    return 1
  }
}

deploy_push_parse_args() {
  while (($# > 0)); do
    case "$1" in
      --project)
        REQUESTED_PROJECT="$2"
        shift 2
        ;;
      --deploy-dir)
        REQUESTED_DEPLOY_DIR="$2"
        shift 2
        ;;
      --config)
        CONFIG_PATH="$2"
        shift 2
        ;;
      --projects)
        PROJECTS_PATH="$2"
        shift 2
        ;;
      --force)
        REQUESTED_FORCE="true"
        shift
        ;;
      --env)
        REQUESTED_ENV="$2"
        shift 2
        ;;
      *)
        deploy_push_die "Unknown argument: $1"
        return 1
        ;;
    esac
  done
}

deploy_push_validate_path_segment() {
  local value="$1"
  local label="$2"

  case "${value}" in
    ""|"."|".."|*[[:space:]]*|*/*)
      deploy_push_die "Invalid ${label}: ${value}"
      return 1
      ;;
  esac
}

deploy_push_resolve_project() {
  [[ -n "${REQUESTED_PROJECT}" ]] || {
    deploy_push_die "--project is required"
    return 1
  }

  resolve_project_by_name "${PROJECTS_PATH}" "${REQUESTED_PROJECT}" "${REQUESTED_ENV}" || return 1

  if [[ -z "${DEPLOY_INTENT}" ]]; then
    DEPLOY_INTENT="none"
  fi

  [[ "${DEPLOY_INTENT}" == "k8s" ]] || {
    deploy_push_die "Project ${PROJECT_NAME} has no k8s deploy intent (intent=${DEPLOY_INTENT:-none})"
    return 1
  }
}

deploy_push_validate_inputs() {
  local yaml_file=""

  [[ -n "${REQUESTED_DEPLOY_DIR}" ]] || {
    deploy_push_die "--deploy-dir is required"
    return 1
  }

  [[ -d "${REQUESTED_DEPLOY_DIR}" ]] || {
    deploy_push_die "Deploy directory not found: ${REQUESTED_DEPLOY_DIR}"
    return 1
  }

  yaml_file="$(find "${REQUESTED_DEPLOY_DIR}" -mindepth 1 -maxdepth 1 -type f -name '*.yaml' -print -quit)"
  [[ -n "${yaml_file}" ]] || {
    deploy_push_die "No YAML files found in deploy directory: ${REQUESTED_DEPLOY_DIR}"
    return 1
  }
}

deploy_push_main() {
  local version=""
  local remote_dir=""
  local remote_path=""

  deploy_push_reset_state
  deploy_push_parse_args "$@" || return 1
  deploy_push_load_remote_config "${CONFIG_PATH}" || return 1
  deploy_push_resolve_project || return 1
  deploy_push_validate_inputs || return 1

  version="$(basename "${REQUESTED_DEPLOY_DIR}")"
  deploy_push_validate_path_segment "${PROJECT_NAME}" "project name" || return 1
  deploy_push_validate_path_segment "${version}" "deploy version" || return 1
  VERSION="${version}"
  remote_dir="${DEPLOY_BASE_DIR}/${PROJECT_NAME}"
  remote_path="${remote_dir}/${VERSION}"

  deploy_push_log "Pushing deploy assets for ${PROJECT_NAME}:${VERSION}"
  deploy_remote_exec_push "${REQUESTED_DEPLOY_DIR}" "${remote_path}" "${REQUESTED_FORCE}" >/dev/null
  deploy_push_log "Deploy assets pushed to ${remote_path}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  deploy_push_main "$@"
fi
