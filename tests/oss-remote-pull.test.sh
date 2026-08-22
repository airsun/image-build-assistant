#!/usr/bin/env bash
set -euo pipefail

# Tests for remote source mode (docs/specs/oss-remote-pull.md).
# Pure local bash: ssh is shadowed by a fake function, git/docker are never
# invoked. See docs/test-plans/oss-remote-pull.md.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSISTANT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
SCRIPTS_DIR="${ASSISTANT_ROOT}/image-builder/scripts"

# shellcheck source=../image-builder/scripts/project-resolver.sh
source "${SCRIPTS_DIR}/project-resolver.sh"
# shellcheck source=../image-builder/scripts/remote-build-entry.sh
source "${SCRIPTS_DIR}/remote-build-entry.sh"
# shellcheck source=../image-builder/scripts/remote-code-pull.sh
source "${SCRIPTS_DIR}/remote-code-pull.sh"
# shellcheck source=../image-builder/build.sh
source "${ASSISTANT_ROOT}/image-builder/build.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  [[ "${actual}" == "${expected}" ]] || fail "${message}: expected '${expected}', got '${actual}'"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  [[ "${haystack}" == *"${needle}"* ]] || fail "${message}: '${haystack}' does not contain '${needle}'"
}

# --- 1. project-resolver: source_mode / upstream_url parsing -----------------

TMP_REGISTRY="$(mktemp -d)/projects.yaml"
REGISTRY_DIR="$(dirname "${TMP_REGISTRY}")"
cat > "${TMP_REGISTRY}" <<'YAML'
projects:
  - name: remote-demo
    source_mode: remote
    source_dir: ~/code_workspaces/remote-demo
    upstream_url: https://github.com/acme/remote-demo.git
    dockerfile_path: Dockerfile
    build_context: .
    image_name: remote-demo
    platform: linux/amd64
    enabled: true
    envs:
      - env: skytech
        version: v-1.2.3
        built_commit: abc1234
        harbor_project: ai.infra

  - name: local-demo
    source_dir: ./local-src
    dockerfile_path: Dockerfile
    build_context: .
    image_name: local-demo
    envs:
      - env: skytech
        version: v-0.1.0
YAML

resolve_project_by_name "${TMP_REGISTRY}" remote-demo skytech
assert_eq "${SOURCE_MODE}" remote "remote source mode parsed"
assert_eq "${SOURCE_DIR}" "~/code_workspaces/remote-demo" "remote source dir stays verbatim (no local normalization)"
assert_eq "${UPSTREAM_URL}" "https://github.com/acme/remote-demo.git" "upstream url parsed"
assert_eq "${VERSION}" "v-1.2.3" "env-level version parsed"

resolve_project_by_name "${TMP_REGISTRY}" local-demo skytech
assert_eq "${SOURCE_MODE}" local "default source mode is local"
assert_eq "${SOURCE_DIR}" "${REGISTRY_DIR}/local-src" "local source dir normalized against registry dir"
assert_eq "${UPSTREAM_URL}" "" "upstream url empty when absent"

# --- 2. build.sh remote-mode validation --------------------------------------

project_resolver_clear
PROJECT_NAME="remote-demo"
SOURCE_DIR='~/code_workspaces/remote-demo'
SOURCE_MODE="remote"
UPSTREAM_URL=""
DOCKERFILE_PATH="Dockerfile"
BUILD_CONTEXT="."
PUSH_LATEST="true"

if build_image_validate_inputs; then
  fail "remote mode without upstream_url must fail"
fi

UPSTREAM_URL="https://github.com/acme/remote-demo.git"
# SOURCE_DIR is a remote path that does not exist locally; remote mode must
# not touch the local filesystem.
SOURCE_DIR='~/code_workspaces/does-not-exist-locally'
build_image_validate_inputs || fail "remote mode with upstream_url must pass without local source dir"

PUSH_LATEST="sometimes"
if build_image_validate_inputs; then
  fail "invalid PUSH_LATEST must fail in remote mode"
fi
PUSH_LATEST="true"

# --- 3. remote-build-entry: remote source mode -------------------------------

REMOTE_BASE_DIR="$(mktemp -d)"
RUN_ID="test-run-1"
REMOTE_SOURCE_DIR='~/code_workspaces/demo'
UPLOADED_ARCHIVE_PATH=""
UPLOADED_DOCKERFILE_PATH=""
DOCKERFILE_PATH="Dockerfile"
BUILD_CONTEXT="."
HARBOR_HOST=""
HARBOR_PROJECT="library"
IMAGE_NAME="demo"
VERSION="v-0.0.1"
PLATFORM="linux/amd64"
PUSH="false"
PUSH_LATEST="true"
BUILD_ARGS=""

remote_entry_init || fail "remote entry init must pass in remote source mode"
assert_eq "${REMOTE_SOURCE_DIR}" "${HOME}/code_workspaces/demo" "leading tilde expanded against HOME"

BUILD_CONTEXT="."
assert_eq "$(remote_entry_resolve_context_dir)" "${HOME}/code_workspaces/demo" "context '.' resolves to remote source dir"
BUILD_CONTEXT="app"
assert_eq "$(remote_entry_resolve_context_dir)" "${HOME}/code_workspaces/demo/app" "nested context resolves under remote source dir"
BUILD_CONTEXT="."

FIXTURE_SRC="$(mktemp -d)"
touch "${FIXTURE_SRC}/Dockerfile"
REMOTE_SOURCE_DIR="${FIXTURE_SRC}"
DOCKERFILE_PATH="Dockerfile"
remote_entry_stage_remote_source || fail "existing remote source with Dockerfile must stage"

DOCKERFILE_PATH="deploy/Dockerfile"
if remote_entry_stage_remote_source; then
  fail "missing Dockerfile in remote source must fail"
fi
DOCKERFILE_PATH="Dockerfile"

REMOTE_SOURCE_DIR="${FIXTURE_SRC}/nope"
if remote_entry_stage_remote_source; then
  fail "missing remote source dir must fail"
fi
REMOTE_SOURCE_DIR=""

# Regression: upload mode still requires uploaded inputs.
UPLOADED_ARCHIVE_PATH=""
UPLOADED_DOCKERFILE_PATH=""
if remote_entry_init; then
  fail "upload mode without uploaded archive/dockerfile must fail"
fi

# --- 4. remote-code-pull with a shadowed ssh --------------------------------

REMOTE_USER="testuser"
REMOTE_HOST="testhost"
SSH_KEY_PATH="/dev/null"
REMOTE_PORT="22"
# The shadowed ssh runs inside a command-substitution subshell, so the
# captured remote command is written to a file instead of a variable.
SSH_CAPTURE="$(mktemp)"

# 4a. JSON string escaping and default name derivation
assert_eq "$(remote_code_pull_json_string 'a"b\c')" 'a\"b\\c' "json string escaping"
assert_eq "$(remote_code_pull_default_name 'https://github.com/acme/remote-demo.git')" "remote-demo" "default name strips .git and path"

# 4b. tags subcommand: annotated-tag dedup and JSON array output
ssh() {
  printf '%s' "${@: -1}" > "${SSH_CAPTURE}"
  printf '9fceb02d98d2e2a7b9a2e6c5f9d1b3a4c5d6e7f8\trefs/tags/v1.2.3\n9fceb02d98d2e2a7b9a2e6c5f9d1b3a4c5d6e7f8\trefs/tags/v1.2.3^{}\n1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a\trefs/tags/2.0.0\n'
}
tags_json="$(remote_code_pull_cmd_tags 'https://github.com/acme/remote-demo.git')"
assert_eq "${tags_json}" '["2.0.0","v1.2.3"]' "tag list dedups annotated tags into a JSON array"
assert_contains "$(cat "${SSH_CAPTURE}")" "git ls-remote --tags --" "tags uses ls-remote with -- separator"
assert_contains "$(cat "${SSH_CAPTURE}")" "https://github.com/acme/remote-demo.git" "tags passes the repo URL"

# 4c. pull subcommand: index JSON and remote command content
ssh() {
  printf '%s' "${@: -1}" > "${SSH_CAPTURE}"
  printf '~/code_workspaces/remote-demo\tabc1234\tv1.2.3\n'
}
pull_json="$(remote_code_pull_cmd_pull 'https://github.com/acme/remote-demo.git' '' '')"
assert_eq "${pull_json}" '{"remote_path":"~/code_workspaces/remote-demo","commit":"abc1234","ref":"v1.2.3"}' "pull prints the remote index as JSON"
assert_contains "$(cat "${SSH_CAPTURE}")" 'WS=~/code_workspaces' "remote command uses the tilde workspace"
assert_contains "$(cat "${SSH_CAPTURE}")" 'DEST="${WS}/${NAME}"' "remote command derives dest from name (template stays literal for remote expansion)"
assert_contains "$(cat "${SSH_CAPTURE}")" 'checkout -q "refs/tags/${REF}"' "remote command prefers an exact tag over same-named branches"
assert_contains "$(cat "${SSH_CAPTURE}")" 'checkout -q "origin/${REF}"' "remote command falls back to origin/<ref>"
assert_contains "$(cat "${SSH_CAPTURE}")" 'git clone -- "${URL}"' "remote clone uses -- separator"
assert_contains "$(cat "${SSH_CAPTURE}")" 'symbolic-ref --short refs/remotes/origin/HEAD' "ref-less pull moves HEAD to the remote default branch"

# 4d. pull failure: ssh exit propagates, no JSON on stdout
ssh() {
  printf '%s' "${@: -1}" > "${SSH_CAPTURE}"
  return 1
}
if remote_code_pull_cmd_pull 'https://example.com/x.git' '' ''; then
  fail "pull must fail when ssh fails"
fi

# 4e. argument validation
if remote_code_pull_main pull --repo-url 'https://example.com/x.git'; then
  fail "missing --config must fail"
fi
if remote_code_pull_main pull --config /nonexistent/env --repo-url 'https://example.com/x.git'; then
  fail "missing config file must fail"
fi
if remote_code_pull_main pull --config; then
  fail "missing option value must fail cleanly (no unbound variable)"
fi

printf 'PASS: oss-remote-pull tests\n'
