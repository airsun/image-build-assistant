#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSISTANT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
REGISTRY="${ASSISTANT_ROOT}/image-builder/projects.yaml"
OFFICE31_ENV="${ASSISTANT_ROOT}/image-builder/remote-envs/office-31.env"

# shellcheck source=../image-builder/scripts/project-resolver.sh
source "${ASSISTANT_ROOT}/image-builder/scripts/project-resolver.sh"

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

resolve_project_by_name "${REGISTRY}" agentic-techlab-wiki-infra office-31

assert_eq "${PROJECT_NAME}" agentic-techlab-wiki-infra "project name"
assert_eq "${SOURCE_DIR}" /Users/gunegg/Works/vibe-infra/agentic-techlab-wiki-infra/.worktrees/b-0.1.0-rc "source directory"
assert_eq "${DOCKERFILE_PATH}" Dockerfile "Dockerfile path"
assert_eq "${BUILD_CONTEXT}" . "build context"
assert_eq "${IMAGE_NAME}" agentic-techlab-wiki-infra "image name"
assert_eq "${PLATFORM}" linux/amd64 "platform"
assert_eq "${ENABLED}" true "enabled state"
assert_eq "${ENV_NAME}" office-31 "environment"
assert_eq "${VERSION}" v-0.1.0 "image version"
assert_eq "${HARBOR_PROJECT}" ai.infra "Harbor project"
assert_eq "${DEPLOY_INTENT}" docker "deploy intent"

[[ "${BUILT_COMMIT}" =~ ^[0-9a-f]{40}$ ]] || fail "built_commit must be a full lowercase Git commit"
actual_commit="$(git -C "${SOURCE_DIR}" rev-parse HEAD)"
assert_eq "${BUILT_COMMIT}" "${actual_commit}" "built commit"
[[ -z "$(git -C "${SOURCE_DIR}" status --short)" ]] || fail "B source worktree must be clean"

# shellcheck disable=SC1090
source "${OFFICE31_ENV}"
assert_eq "${REMOTE_HOST}" 192.168.14.31 "remote host"
assert_eq "${REMOTE_USER}" builder "remote build user"
assert_eq "${REMOTE_BASE_DIR}" /home/builder/images/ "remote build directory"
assert_eq "${HARBOR_HOST}" harbor.tech.skytech.io "Harbor host"
assert_eq "${PUSH}" true "push policy"

printf 'PASS: agentic-techlab-wiki-infra Office-31 registration\n'
