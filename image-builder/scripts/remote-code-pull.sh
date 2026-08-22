#!/usr/bin/env bash
set -euo pipefail

# Remote code pull: fetch an upstream repository directly on the build host
# and keep it under ~/code_workspaces/ on the builder. The local machine only
# receives a small JSON index (remote path, commit, tag) for registration in
# projects.yaml. See docs/specs/oss-remote-pull.md.
#
# Usage:
#   remote-code-pull.sh tags --config <env> --repo-url <url>
#     List upstream tag names (JSON array) for AI-layer semver filtering.
#   remote-code-pull.sh pull --config <env> --repo-url <url> [--ref <ref>] [--name <name>]
#     Clone (or fetch when the destination already exists) and optionally
#     checkout <ref>. Prints JSON index: remote_path / commit / ref.

REMOTE_CODE_PULL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/remote-exec.sh
source "${REMOTE_CODE_PULL_SCRIPT_DIR}/remote-exec.sh"

REMOTE_CODE_PULL_LOG_PREFIX="[image-build-assistant]"
# Keep the tilde literal: it must expand on the build host, keeping the
# workspace path portable across builders with different home directories.
# shellcheck disable=SC2088
REMOTE_CODE_PULL_WORKSPACE="~/code_workspaces"

# stdout is the machine contract (JSON index); human logs go to stderr.
remote_code_pull_log() {
  printf '%s %s\n' "${REMOTE_CODE_PULL_LOG_PREFIX}" "$*" >&2
}

remote_code_pull_error() {
  printf '%s ERROR: %s\n' "${REMOTE_CODE_PULL_LOG_PREFIX}" "$*" >&2
}

remote_code_pull_die() {
  remote_code_pull_error "$*"
  return 1 2>/dev/null || exit 1
}

remote_code_pull_load_config() {
  local config_path="$1"

  [[ -f "${config_path}" ]] || {
    remote_code_pull_die "Config file not found: ${config_path}"
    return 1
  }

  # shellcheck disable=SC1090
  source "${config_path}"

  # Per-project settings must not leak from the env file into the pull.
  unset IMAGE_NAME VERSION

  REMOTE_PORT="${REMOTE_PORT:-22}"

  [[ -n "${REMOTE_HOST:-}" ]] || {
    remote_code_pull_die "Missing required remote config: REMOTE_HOST"
    return 1
  }
  [[ -n "${REMOTE_USER:-}" ]] || {
    remote_code_pull_die "Missing required remote config: REMOTE_USER"
    return 1
  }
  [[ -n "${SSH_KEY_PATH:-}" ]] || {
    remote_code_pull_die "Missing required remote config: SSH_KEY_PATH"
    return 1
  }
}

# Run a command on the build host. The command is passed as a single argument,
# mirroring how remote-exec.sh invokes remote builds. The ssh options helper
# intentionally emits multiple words, and the command is expanded locally by
# design (it IS the payload sent to the remote shell).
# shellcheck disable=SC2046,SC2029
remote_code_pull_run_remote() {
  local remote_command="$1"

  ssh $(remote_exec_ssh_options) "$(remote_exec_ssh_target)" "${remote_command}"
}

remote_code_pull_json_string() {
  # Minimal JSON string escaping (backslash, double quote).
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

remote_code_pull_default_name() {
  basename "$1" .git
}

remote_code_pull_cmd_tags() {
  local repo_url="$1"
  local remote_command=""
  local raw_output=""
  local tag_list=""
  local tag=""
  local first=1

  [[ -n "${repo_url}" ]] || {
    remote_code_pull_die "Repo URL is required"
    return 1
  }

  printf -v remote_command 'git ls-remote --tags -- %q' "${repo_url}"
  raw_output="$(remote_code_pull_run_remote "${remote_command}")"

  # Keep tag names only; annotated tags produce a peeled (^{}) duplicate line.
  tag_list="$(printf '%s\n' "${raw_output}" \
    | awk '{print $2}' \
    | sed -e 's|^refs/tags/||' -e 's|\^{}$||' \
    | grep -v '^$' \
    | sort -u)"

  printf '['
  while IFS= read -r tag; do
    [[ -n "${tag}" ]] || continue
    if [[ "${first}" -eq 1 ]]; then
      first=0
    else
      printf ','
    fi
    printf '"%s"' "$(remote_code_pull_json_string "${tag}")"
  done <<< "${tag_list}"
  printf ']\n'
}

remote_code_pull_cmd_pull() {
  local repo_url="$1"
  local ref="$2"
  local name="$3"
  local remote_command=""
  local output=""
  local remote_path=""
  local commit=""
  local resolved_ref=""

  [[ -n "${repo_url}" ]] || {
    remote_code_pull_die "Repo URL is required"
    return 1
  }
  name="${name:-$(remote_code_pull_default_name "${repo_url}")}"

  # The remote side expands ~ in WS=~ and keeps the literal ~/code_workspaces
  # form in the printed path so projects.yaml stays portable across builders
  # with different home directories.
  # Single-quoted template on purpose: ${...} inside must be evaluated on the
  # build host, not locally.
  # Checkout order: refs/tags first (a local branch of the same name would
  # otherwise shadow the tag via DWIM), then origin/<ref> (detached snapshot
  # at the latest remote tip), then the bare ref (commit hashes). A ref-less
  # update moves HEAD to the remote default branch instead of leaving a stale
  # checkout behind.
  # shellcheck disable=SC2016
  printf -v remote_command \
    'set -e; WS=%q; NAME=%q; URL=%q; REF=%q; DEST="${WS}/${NAME}"; mkdir -p "${WS}"; if [ -d "${DEST}/.git" ]; then ORIGIN="$(git -C "${DEST}" remote get-url origin 2>/dev/null || true)"; if [ -n "${ORIGIN}" ] && [ "${ORIGIN}" != "${URL}" ]; then printf "%%s\n" "REMOTE_CODE_PULL_ERROR: destination exists with different origin: ${ORIGIN}" >&2; exit 1; fi; git -C "${DEST}" fetch --tags origin; else git clone -- "${URL}" "${DEST}"; fi; if [ -n "${REF}" ]; then git -C "${DEST}" checkout -q "refs/tags/${REF}" 2>/dev/null || git -C "${DEST}" checkout -q "origin/${REF}" 2>/dev/null || git -C "${DEST}" checkout -q "${REF}" 2>/dev/null || { if git -C "${DEST}" rev-parse --verify -q "${REF}^{commit}" >/dev/null 2>&1 || git -C "${DEST}" rev-parse --verify -q "refs/tags/${REF}^{commit}" >/dev/null 2>&1 || git -C "${DEST}" rev-parse --verify -q "refs/remotes/origin/${REF}^{commit}" >/dev/null 2>&1; then printf "%%s\n" "REMOTE_CODE_PULL_ERROR: checkout failed for ref: ${REF} (dirty tree or fetch failure)" >&2; else printf "%%s\n" "REMOTE_CODE_PULL_ERROR: ref not found: ${REF}" >&2; fi; exit 1; }; else DEFAULT_REF="$(git -C "${DEST}" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"; if [ -n "${DEFAULT_REF}" ]; then git -C "${DEST}" checkout -q "${DEFAULT_REF}" 2>/dev/null || true; fi; fi; printf "%%s\t%%s\t%%s\n" "~/code_workspaces/${NAME}" "$(git -C "${DEST}" rev-parse --short HEAD)" "$(git -C "${DEST}" describe --tags --exact-match 2>/dev/null || true)"' \
    "${REMOTE_CODE_PULL_WORKSPACE}" \
    "${name}" \
    "${repo_url}" \
    "${ref:-}"

  remote_code_pull_log "Pull ${repo_url} into ${REMOTE_CODE_PULL_WORKSPACE}/${name} on ${REMOTE_HOST}"

  output="$(remote_code_pull_run_remote "${remote_command}")" || {
    remote_code_pull_die "Remote pull failed (see ssh stderr above)"
    return 1
  }

  # Tab delimiter: tab is forbidden in git ref names, pipe is not.
  IFS=$'\t' read -r remote_path commit resolved_ref <<< "${output}"

  [[ -n "${remote_path}" ]] || {
    remote_code_pull_die "Remote pull returned an empty index"
    return 1
  }

  printf '{"remote_path":"%s","commit":"%s","ref":"%s"}\n' \
    "$(remote_code_pull_json_string "${remote_path}")" \
    "$(remote_code_pull_json_string "${commit}")" \
    "$(remote_code_pull_json_string "${resolved_ref}")"
}

remote_code_pull_usage() {
  cat <<'EOF'
Usage:
  remote-code-pull.sh tags --config <env-file> --repo-url <url>
  remote-code-pull.sh pull --config <env-file> --repo-url <url> [--ref <ref>] [--name <name>]
EOF
}

remote_code_pull_main() {
  local subcommand=""
  local config_path=""
  local repo_url=""
  local ref=""
  local name=""

  subcommand="${1:-}"
  shift 2>/dev/null || true

  while (($# > 0)); do
    case "$1" in
      --config)
        [[ $# -ge 2 && -n "$2" ]] || {
          remote_code_pull_die "Missing value for --config"
          return 1
        }
        config_path="$2"
        shift 2
        ;;
      --repo-url)
        [[ $# -ge 2 && -n "$2" ]] || {
          remote_code_pull_die "Missing value for --repo-url"
          return 1
        }
        repo_url="$2"
        shift 2
        ;;
      --ref)
        [[ $# -ge 2 && -n "$2" ]] || {
          remote_code_pull_die "Missing value for --ref"
          return 1
        }
        ref="$2"
        shift 2
        ;;
      --name)
        [[ $# -ge 2 && -n "$2" ]] || {
          remote_code_pull_die "Missing value for --name"
          return 1
        }
        name="$2"
        shift 2
        ;;
      *)
        remote_code_pull_die "Unknown argument: $1"
        return 1
        ;;
    esac
  done

  [[ -n "${config_path}" ]] || {
    remote_code_pull_die "--config is required"
    return 1
  }

  remote_code_pull_load_config "${config_path}" || return 1

  case "${subcommand}" in
    tags)
      remote_code_pull_cmd_tags "${repo_url}" || return 1
      ;;
    pull)
      remote_code_pull_cmd_pull "${repo_url}" "${ref}" "${name}" || return 1
      ;;
    *)
      remote_code_pull_usage >&2
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  remote_code_pull_main "$@"
fi
