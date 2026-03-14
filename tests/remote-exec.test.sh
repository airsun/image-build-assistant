#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSISTANT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"

# shellcheck source=../image-builder/scripts/remote-exec.sh
source "${ASSISTANT_ROOT}/image-builder/scripts/remote-exec.sh"
# shellcheck source=../image-builder/scripts/remote-build-entry.sh
source "${ASSISTANT_ROOT}/image-builder/scripts/remote-build-entry.sh"

TEST_TMPDIR="$(mktemp -d "/tmp/remote-exec-test.XXXXXX")"
trap 'rm -rf "${TEST_TMPDIR}"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "${message}: missing '${needle}' in '${haystack}'"
  fi
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"

  if [[ "${actual}" != "${expected}" ]]; then
    fail "${message}: expected '${expected}', got '${actual}'"
  fi
}

assert_file_exists() {
  local path="$1"
  local message="$2"

  [[ -f "${path}" ]] || fail "${message}: file not found at ${path}"
}

assert_dir_exists() {
  local path="$1"
  local message="$2"

  [[ -d "${path}" ]] || fail "${message}: directory not found at ${path}"
}

assert_dir_empty() {
  local path="$1"
  local message="$2"
  local entries=()

  shopt -s nullglob dotglob
  entries=("${path}"/*)
  shopt -u nullglob dotglob

  if (( ${#entries[@]} != 0 )); then
    fail "${message}: expected empty directory"
  fi
}

test_remote_exec_upload_and_execute_contract() {
  local case_dir="${TEST_TMPDIR}/upload"
  local archive_path="${case_dir}/context.tar.gz"
  local dockerfile_path="${case_dir}/Dockerfile"
  local ssh_log="${case_dir}/ssh.log"
  local scp_log="${case_dir}/scp.log"

  mkdir -p "${case_dir}"
  : > "${archive_path}"
  : > "${dockerfile_path}"
  : > "${case_dir}/id_test"

  REMOTE_HOST="builder.example.internal"
  REMOTE_PORT="2222"
  REMOTE_USER="deploy"
  SSH_KEY_PATH="${case_dir}/id_test"
  REMOTE_BASE_DIR="/srv/image-build-assistant"
  HARBOR_HOST="harbor.test.example.com"
  HARBOR_PROJECT="library"
  IMAGE_NAME="claude-code-hub"
  VERSION="v1.0.0"
  PLATFORM="linux/amd64"
  PUSH="true"
  BUILD_CONTEXT="."
  DOCKERFILE_PATH="deploy/Dockerfile"
  REMOTE_EXEC_SCRIPT_DIR="${ASSISTANT_ROOT}/image-builder/scripts"

  ssh() {
    printf '%s\n' "$*" >> "${ssh_log}"
  }

  scp() {
    printf '%s\n' "$*" >> "${scp_log}"
  }

  remote_exec_upload_and_execute "${archive_path}" "${dockerfile_path}" "run-001"
  unset -f ssh
  unset -f scp

  assert_contains "$(cat "${ssh_log}")" "mkdir -p /srv/image-build-assistant" "should prepare remote base dir"
  assert_contains "$(cat "${scp_log}")" "-P 2222" "scp uploads should use uppercase port option"
  assert_contains "$(cat "${scp_log}")" "${archive_path}" "should upload context archive"
  assert_contains "$(cat "${scp_log}")" "${dockerfile_path}" "should upload dockerfile"
  assert_contains "$(cat "${scp_log}")" "${ASSISTANT_ROOT}/image-builder/scripts/remote-build-entry.sh" "should upload remote entry script"
  assert_contains "$(cat "${scp_log}")" "deploy@builder.example.internal:/srv/image-build-assistant/context-run-001.tar.gz" "should upload context archive to contract path"
  assert_contains "$(cat "${scp_log}")" "deploy@builder.example.internal:/srv/image-build-assistant/dockerfile-run-001" "should upload dockerfile to contract path"
  assert_contains "$(cat "${ssh_log}")" "RUN_ID=run-001" "should pass run id to remote entry"
  assert_contains "$(cat "${ssh_log}")" "UPLOADED_ARCHIVE_PATH=/srv/image-build-assistant/context-run-001.tar.gz" "should pass archive path to remote entry"
  assert_contains "$(cat "${ssh_log}")" "UPLOADED_DOCKERFILE_PATH=/srv/image-build-assistant/dockerfile-run-001" "should pass dockerfile path to remote entry"
  assert_contains "$(cat "${ssh_log}")" "DOCKERFILE_PATH=deploy/Dockerfile" "should pass logical dockerfile path"
  assert_contains "$(cat "${ssh_log}")" "BUILD_CONTEXT=." "should pass build context"
}

test_remote_entry_builds_and_pushes_root_context() {
  local case_dir="${TEST_TMPDIR}/remote-root"
  local base_dir="${case_dir}/remote"
  local uploaded_archive="${base_dir}/context-uploaded.tar.gz"
  local uploaded_dockerfile="${base_dir}/dockerfile-uploaded"
  local status=0

  mkdir -p "${base_dir}/workspace"
  printf 'stale' > "${base_dir}/workspace/stale.txt"
  : > "${uploaded_archive}"
  : > "${uploaded_dockerfile}"

  (
    set -euo pipefail
    source "${ASSISTANT_ROOT}/image-builder/scripts/remote-build-entry.sh"

    REMOTE_BASE_DIR="${base_dir}"
    RUN_ID="run-root"
    UPLOADED_ARCHIVE_PATH="${uploaded_archive}"
    UPLOADED_DOCKERFILE_PATH="${uploaded_dockerfile}"
    DOCKERFILE_PATH="deploy/Dockerfile"
    BUILD_CONTEXT="."
    HARBOR_HOST="harbor.test.example.com"
    HARBOR_PROJECT="library"
    IMAGE_NAME="claude-code-hub"
    VERSION="v2.0.0"
    PLATFORM="linux/amd64"
    PUSH="true"

    tar() {
      local destination=""

      while (($# > 0)); do
        if [[ "$1" == "-C" ]]; then
          destination="$2"
          shift 2
          continue
        fi
        shift
      done

      [[ ! -e "${destination}/stale.txt" ]] || {
        printf 'workspace not cleaned before extraction\n' >&2
        return 1
      }

      mkdir -p "${destination}"
      : > "${destination}/package.json"
    }

    docker() {
      printf '%s\n' "$*" >> "${REMOTE_BASE_DIR}/docker.log"
    }

    remote_entry_main
  ) || status=$?

  assert_eq "${status}" "0" "remote entry should succeed for root context"
  assert_file_exists "${base_dir}/docker.log" "docker log should be captured"
  assert_contains "$(cat "${base_dir}/docker.log")" "build --platform linux/amd64 -f ${base_dir}/runs/run-root/incoming/dockerfiles/deploy/Dockerfile -t harbor.test.example.com/library/claude-code-hub:v2.0.0 -t harbor.test.example.com/library/claude-code-hub:latest ${base_dir}/runs/run-root/workspace/context" "docker build should target run-scoped root context and staged dockerfile path"
  assert_contains "$(cat "${base_dir}/docker.log")" "push harbor.test.example.com/library/claude-code-hub:v2.0.0" "docker push should include version tag"
  assert_contains "$(cat "${base_dir}/docker.log")" "push harbor.test.example.com/library/claude-code-hub:latest" "docker push should include latest tag"
  assert_dir_exists "${base_dir}/runs/run-root/incoming" "run-scoped incoming dir should exist"
  assert_dir_exists "${base_dir}/runs/run-root/workspace" "run-scoped workspace dir should exist"
  assert_dir_exists "${base_dir}/runs/run-root/logs" "run-scoped logs dir should exist"
  assert_dir_empty "${base_dir}/runs/run-root/incoming" "run-scoped incoming dir should be cleaned"
  assert_dir_empty "${base_dir}/runs/run-root/workspace" "run-scoped workspace dir should be cleaned"
}

test_remote_entry_builds_subdir_context_without_push() {
  local case_dir="${TEST_TMPDIR}/remote-subdir"
  local base_dir="${case_dir}/remote"
  local uploaded_archive="${base_dir}/context-uploaded.tar.gz"
  local uploaded_dockerfile="${base_dir}/dockerfile-uploaded"
  local status=0

  mkdir -p "${base_dir}"
  : > "${uploaded_archive}"
  : > "${uploaded_dockerfile}"

  (
    set -euo pipefail
    source "${ASSISTANT_ROOT}/image-builder/scripts/remote-build-entry.sh"

    REMOTE_BASE_DIR="${base_dir}"
    RUN_ID="run-subdir"
    UPLOADED_ARCHIVE_PATH="${uploaded_archive}"
    UPLOADED_DOCKERFILE_PATH="${uploaded_dockerfile}"
    DOCKERFILE_PATH="docker/Dockerfile"
    BUILD_CONTEXT="app"
    HARBOR_HOST="harbor.test.example.com"
    HARBOR_PROJECT="services"
    IMAGE_NAME="worker"
    VERSION="v3.0.0"
    PLATFORM="linux/arm64"
    PUSH="false"

    tar() {
      local destination=""

      while (($# > 0)); do
        if [[ "$1" == "-C" ]]; then
          destination="$2"
          shift 2
          continue
        fi
        shift
      done

      mkdir -p "${destination}/app"
      : > "${destination}/app/main.ts"
    }

    docker() {
      printf '%s\n' "$*" >> "${REMOTE_BASE_DIR}/docker.log"
    }

    remote_entry_main
  ) || status=$?

  assert_eq "${status}" "0" "remote entry should succeed for subdir context"
  assert_contains "$(cat "${base_dir}/docker.log")" "build --platform linux/arm64 -f ${base_dir}/runs/run-subdir/incoming/dockerfiles/docker/Dockerfile -t harbor.test.example.com/services/worker:v3.0.0 -t harbor.test.example.com/services/worker:latest ${base_dir}/runs/run-subdir/workspace/context/app" "docker build should target run-scoped subdir context and staged dockerfile path"
  if grep -q "push " "${base_dir}/docker.log"; then
    fail "docker push should not run when PUSH=false"
  fi
}

run_all_tests() {
  test_remote_exec_upload_and_execute_contract
  test_remote_entry_builds_and_pushes_root_context
  test_remote_entry_builds_subdir_context_without_push
  printf 'PASS: remote exec tests\n'
}

run_all_tests
