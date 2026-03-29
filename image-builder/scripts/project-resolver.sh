#!/usr/bin/env bash
set -euo pipefail

project_resolver_error() {
  printf '%s\n' "$*" >&2
}

project_resolver_clear() {
  PROJECT_NAME=""
  SOURCE_DIR=""
  DOCKERFILE_PATH=""
  BUILD_CONTEXT=""
  IMAGE_NAME=""
  HARBOR_PROJECT=""
  PLATFORM=""
  ENABLED=""
  VERSION=""
  BUILT_COMMIT=""
  BUILD_ARGS=""
  DEPLOY_INTENT=""
  DEPLOY_NAMESPACE=""
  DEPLOY_CLUSTER=""
  DEPLOY_DOMAIN=""
  DEPLOY_CONTAINER_PORT=""
  DEPLOYED_VERSION=""
  DEPLOYED_COMMIT=""
  ENV_NAME=""
}

# Parse a project-level field (4-space indent, outside envs/deploy sections)
project_resolver_parse_field() {
  local registry_path="$1"
  local project_name="$2"
  local field_name="$3"

  awk -v project_name="${project_name}" -v field_name="${field_name}" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }

    /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
      current = $0
      sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", current)
      in_project = (trim(current) == project_name)
      in_envs = 0
      next
    }

    in_project && /^    envs:[[:space:]]*$/ {
      in_envs = 1
      next
    }

    in_project && in_envs { next }

    in_project && $0 ~ "^    " field_name ":[[:space:]]*" {
      value = $0
      sub("^    " field_name ":[[:space:]]*", "", value)
      print trim(value)
      exit
    }
  ' "${registry_path}"
}

# Parse an env-level field (8-space indent, inside envs section)
project_resolver_parse_env_field() {
  local registry_path="$1"
  local project_name="$2"
  local env_name="$3"
  local field_name="$4"

  awk -v project_name="${project_name}" -v env_name="${env_name}" -v field_name="${field_name}" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }

    /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
      current = $0
      sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", current)
      in_project = (trim(current) == project_name)
      in_envs = 0
      in_env = 0
      in_deploy = 0
      next
    }

    in_project && /^    envs:[[:space:]]*$/ {
      in_envs = 1
      next
    }

    in_project && in_envs && /^      -[[:space:]]*env:[[:space:]]*/ {
      current = $0
      sub(/^      -[[:space:]]*env:[[:space:]]*/, "", current)
      in_env = (trim(current) == env_name)
      in_deploy = 0
      next
    }

    in_project && in_envs && in_env && /^        deploy:[[:space:]]*$/ {
      in_deploy = 1
      next
    }

    in_project && in_envs && in_env && in_deploy { next }

    in_project && in_envs && in_env && $0 ~ "^        " field_name ":[[:space:]]*" {
      value = $0
      sub("^        " field_name ":[[:space:]]*", "", value)
      print trim(value)
      exit
    }
  ' "${registry_path}"
}

# Parse a deploy field inside an env entry (10-space indent)
project_resolver_parse_env_deploy_field() {
  local registry_path="$1"
  local project_name="$2"
  local env_name="$3"
  local field_name="$4"

  awk -v project_name="${project_name}" -v env_name="${env_name}" -v field_name="${field_name}" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }

    /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
      current = $0
      sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", current)
      in_project = (trim(current) == project_name)
      in_envs = 0
      in_env = 0
      in_deploy = 0
      next
    }

    in_project && /^    envs:[[:space:]]*$/ {
      in_envs = 1
      next
    }

    in_project && in_envs && /^      -[[:space:]]*env:[[:space:]]*/ {
      current = $0
      sub(/^      -[[:space:]]*env:[[:space:]]*/, "", current)
      in_env = (trim(current) == env_name)
      in_deploy = 0
      next
    }

    in_project && in_envs && in_env && /^        deploy:[[:space:]]*$/ {
      in_deploy = 1
      next
    }

    in_project && in_envs && in_env && in_deploy && /^          / && $0 ~ "^          " field_name ":[[:space:]]*" {
      value = $0
      sub("^          " field_name ":[[:space:]]*", "", value)
      print trim(value)
      exit
    }

    in_project && in_envs && in_env && in_deploy && $0 !~ /^          / {
      in_deploy = 0
    }
  ' "${registry_path}"
}

project_resolver_normalize_source_dir() {
  local registry_path="$1"
  local raw_source_dir="$2"
  local registry_dir=""

  case "${raw_source_dir}" in
    /*)
      printf '%s\n' "${raw_source_dir}"
      ;;
    *)
      registry_dir="$(cd "$(dirname "${registry_path}")" && pwd)"
      printf '%s\n' "${registry_dir}/${raw_source_dir#./}"
      ;;
  esac
}

# Check if a project+env combination exists
project_resolver_check_exists() {
  local registry_path="$1"
  local project_name="$2"
  local env_name="${3:-}"

  awk -v project_name="${project_name}" -v env_name="${env_name}" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }

    /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
      current = $0
      sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", current)
      in_project = (trim(current) == project_name)
      in_envs = 0
      if (in_project && env_name == "") {
        print "yes"
        exit
      }
      next
    }

    in_project && /^    envs:[[:space:]]*$/ {
      in_envs = 1
      next
    }

    in_project && in_envs && /^      -[[:space:]]*env:[[:space:]]*/ {
      current = $0
      sub(/^      -[[:space:]]*env:[[:space:]]*/, "", current)
      if (trim(current) == env_name) {
        print "yes"
        exit
      }
    }
  ' "${registry_path}"
}

resolve_project_by_name() {
  local registry_path="$1"
  local project_name="$2"
  local env_name="${3:-}"
  local project_exists=""
  local error_label=""

  [[ -f "${registry_path}" ]] || {
    project_resolver_error "Registry file not found: ${registry_path}"
    return 1
  }

  project_resolver_clear

  project_exists="$(project_resolver_check_exists "${registry_path}" "${project_name}" "${env_name}")"

  if [[ -n "${env_name}" ]]; then
    error_label="${project_name} (env: ${env_name})"
  else
    error_label="${project_name}"
  fi

  [[ -n "${project_exists}" ]] || {
    project_resolver_error "Project not found: ${error_label}"
    return 1
  }

  # Resolve first env if not specified
  if [[ -z "${env_name}" ]]; then
    env_name="$(awk -v project_name="${project_name}" '
      function trim(value) {
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        return value
      }
      /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
        current = $0
        sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", current)
        in_project = (trim(current) == project_name)
        next
      }
      in_project && /^      -[[:space:]]*env:[[:space:]]*/ {
        current = $0
        sub(/^      -[[:space:]]*env:[[:space:]]*/, "", current)
        print trim(current)
        exit
      }
    ' "${registry_path}")"
  fi

  PROJECT_NAME="${project_name}"
  ENV_NAME="${env_name}"

  # Project-level fields
  SOURCE_DIR="$(project_resolver_parse_field "${registry_path}" "${project_name}" "source_dir")"
  DOCKERFILE_PATH="$(project_resolver_parse_field "${registry_path}" "${project_name}" "dockerfile_path")"
  BUILD_CONTEXT="$(project_resolver_parse_field "${registry_path}" "${project_name}" "build_context")"
  IMAGE_NAME="$(project_resolver_parse_field "${registry_path}" "${project_name}" "image_name")"
  PLATFORM="$(project_resolver_parse_field "${registry_path}" "${project_name}" "platform")"
  ENABLED="$(project_resolver_parse_field "${registry_path}" "${project_name}" "enabled")"
  BUILD_ARGS="$(project_resolver_parse_field "${registry_path}" "${project_name}" "build_args")"

  # Env-level fields
  VERSION="$(project_resolver_parse_env_field "${registry_path}" "${project_name}" "${env_name}" "version")"
  BUILT_COMMIT="$(project_resolver_parse_env_field "${registry_path}" "${project_name}" "${env_name}" "built_commit")"
  HARBOR_PROJECT="$(project_resolver_parse_env_field "${registry_path}" "${project_name}" "${env_name}" "harbor_project")"

  # Deploy fields (inside env)
  DEPLOY_INTENT="$(project_resolver_parse_env_deploy_field "${registry_path}" "${project_name}" "${env_name}" "intent")"
  DEPLOY_NAMESPACE="$(project_resolver_parse_env_deploy_field "${registry_path}" "${project_name}" "${env_name}" "namespace")"
  DEPLOY_CLUSTER="$(project_resolver_parse_env_deploy_field "${registry_path}" "${project_name}" "${env_name}" "cluster")"
  DEPLOY_DOMAIN="$(project_resolver_parse_env_deploy_field "${registry_path}" "${project_name}" "${env_name}" "domain")"
  DEPLOY_CONTAINER_PORT="$(project_resolver_parse_env_deploy_field "${registry_path}" "${project_name}" "${env_name}" "container_port")"
  DEPLOYED_VERSION="$(project_resolver_parse_env_deploy_field "${registry_path}" "${project_name}" "${env_name}" "deployed_version")"
  DEPLOYED_COMMIT="$(project_resolver_parse_env_deploy_field "${registry_path}" "${project_name}" "${env_name}" "deployed_commit")"

  SOURCE_DIR="$(project_resolver_normalize_source_dir "${registry_path}" "${SOURCE_DIR}")"
}

merge_project_settings() {
  IMAGE_NAME="${OVERRIDE_IMAGE_NAME:-${IMAGE_NAME:-${DEFAULT_IMAGE_NAME:-}}}"
  HARBOR_PROJECT="${OVERRIDE_HARBOR_PROJECT:-${HARBOR_PROJECT:-${DEFAULT_HARBOR_PROJECT:-}}}"
  PLATFORM="${OVERRIDE_PLATFORM:-${PLATFORM:-${DEFAULT_PLATFORM:-}}}"
}

validate_project_settings() {
  local required_vars=(
    PROJECT_NAME
    SOURCE_DIR
    DOCKERFILE_PATH
    BUILD_CONTEXT
  )
  local var_name=""

  for var_name in "${required_vars[@]}"; do
    if [[ -z "${!var_name:-}" ]]; then
      project_resolver_error "Missing required project setting: ${var_name}"
      return 1
    fi
  done
}
