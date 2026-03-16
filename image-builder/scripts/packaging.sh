#!/usr/bin/env bash
set -euo pipefail

packaging_error() {
  printf '%s\n' "$*" >&2
}

default_excludes() {
  printf '%s\n' ".git" "node_modules" ".next" "coverage" "dist" ".DS_Store"
}

resolve_build_context_path() {
  local source_dir="$1"
  local build_context="$2"
  local resolved_path=""
  local source_realpath=""
  local resolved_realpath=""

  source_realpath="$(cd "${source_dir}" && pwd)"

  if [[ "${build_context}" == "." ]]; then
    resolved_path="${source_realpath}"
  else
    resolved_path="${source_realpath}/${build_context}"
  fi

  [[ -d "${resolved_path}" ]] || {
    packaging_error "Build context directory not found: ${resolved_path}"
    return 1
  }

  resolved_realpath="$(cd "${resolved_path}" && pwd)"

  case "${resolved_realpath}" in
    "${source_realpath}"|"${source_realpath}"/*)
      ;;
    *)
      packaging_error "Build context must stay within source directory: ${build_context}"
      return 1
      ;;
  esac

  printf '%s\n' "${resolved_realpath}"
}

create_build_context_archive() {
  local source_dir="$1"
  local build_context="$2"
  local archive_path="$3"
  local context_path=""
  local tar_args=()
  local exclude_name=""

  context_path="$(resolve_build_context_path "${source_dir}" "${build_context}")"

  # Prevent macOS BSD tar from embedding AppleDouble resource fork
  # files (._*) that cause parse errors on Linux build hosts.
  export COPYFILE_DISABLE=1
  tar_args+=("--exclude=._*")

  if [[ "${build_context}" == "." ]]; then
    while IFS= read -r exclude_name; do
      tar_args+=("--exclude=./${exclude_name}")
    done < <(default_excludes)

    tar -czf "${archive_path}" \
      "${tar_args[@]}" \
      -C "${context_path}" \
      .
  else
    while IFS= read -r exclude_name; do
      tar_args+=("--exclude=${build_context}/${exclude_name}")
    done < <(default_excludes)

    tar -czf "${archive_path}" \
      "${tar_args[@]}" \
      -C "${source_dir}" \
      "${build_context}"
  fi

  printf '%s\n' "${archive_path}"
}
