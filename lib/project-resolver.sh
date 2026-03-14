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
}

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
      current = trim(current)
      in_project = (current == project_name)
      next
    }

    in_project && $0 ~ "^[[:space:]]*" field_name ":[[:space:]]*" {
      value = $0
      sub("^[[:space:]]*" field_name ":[[:space:]]*", "", value)
      print trim(value)
      exit
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

resolve_project_by_name() {
  local registry_path="$1"
  local project_name="$2"
  local project_exists=""

  [[ -f "${registry_path}" ]] || {
    project_resolver_error "Registry file not found: ${registry_path}"
    return 1
  }

  project_resolver_clear

  project_exists="$(awk -v project_name="${project_name}" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }

    /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
      current = $0
      sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", current)
      if (trim(current) == project_name) {
        print "yes"
        exit
      }
    }
  ' "${registry_path}")"

  [[ -n "${project_exists}" ]] || {
    project_resolver_error "Project not found: ${project_name}"
    return 1
  }

  PROJECT_NAME="${project_name}"
  SOURCE_DIR="$(project_resolver_parse_field "${registry_path}" "${project_name}" "source_dir")"
  DOCKERFILE_PATH="$(project_resolver_parse_field "${registry_path}" "${project_name}" "dockerfile_path")"
  BUILD_CONTEXT="$(project_resolver_parse_field "${registry_path}" "${project_name}" "build_context")"
  IMAGE_NAME="$(project_resolver_parse_field "${registry_path}" "${project_name}" "image_name")"
  HARBOR_PROJECT="$(project_resolver_parse_field "${registry_path}" "${project_name}" "harbor_project")"
  PLATFORM="$(project_resolver_parse_field "${registry_path}" "${project_name}" "platform")"
  ENABLED="$(project_resolver_parse_field "${registry_path}" "${project_name}" "enabled")"
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
