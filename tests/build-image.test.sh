#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSISTANT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"

# shellcheck source=../bin/build-image.sh
source "${ASSISTANT_ROOT}/bin/build-image.sh"

TEST_TMPDIR="$(mktemp -d "/tmp/build-image-test.XXXXXX")"
trap 'rm -rf "${TEST_TMPDIR}"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"

  if [[ "${actual}" != "${expected}" ]]; then
    fail "${message}: expected '${expected}', got '${actual}'"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "${message}: missing '${needle}' in '${haystack}'"
  fi
}

reload_build_image_script() {
  # shellcheck source=../bin/build-image.sh
  source "${ASSISTANT_ROOT}/bin/build-image.sh"
}

remote_env="${TEST_TMPDIR}/remote.env"
projects_file="${TEST_TMPDIR}/projects.yaml"
source_dir="${TEST_TMPDIR}/claude-code-hub"

mkdir -p "${source_dir}/deploy"
: > "${source_dir}/deploy/Dockerfile"

cat >"${remote_env}" <<'EOF'
REMOTE_HOST=builder.example.internal
REMOTE_PORT=22
REMOTE_USER=deploy
SSH_KEY_PATH=/tmp/id_test
REMOTE_BASE_DIR=/srv/image-build-assistant
HARBOR_HOST=harbor.test.example.com
HARBOR_PROJECT=library
PLATFORM=linux/amd64
PUSH=true
EOF

cat >"${projects_file}" <<EOF
projects:
  - name: claude-code-hub
    source_dir: ${source_dir}
    dockerfile_path: deploy/Dockerfile
    build_context: .
    image_name: claude-code-hub
    harbor_project: library
    platform: linux/amd64
    enabled: true
EOF

test_build_image_requires_project_or_path() {
  if build_image_main --config "${remote_env}" --projects "${projects_file}" >"${TEST_TMPDIR}/missing-project.out" 2>&1; then
    fail "build_image_main should fail without project or source dir"
  fi

  grep -q "Either --project or --source-dir is required" "${TEST_TMPDIR}/missing-project.out" || fail "missing selector failure should explain required input"
}

test_build_image_uses_project_registry() {
  local call_log="${TEST_TMPDIR}/project-registry.log"

  build_image_reset_state
  BUILD_IMAGE_RUN_ID="run-from-test"

  resolve_project_by_name() {
    PROJECT_NAME="claude-code-hub"
    SOURCE_DIR="${source_dir}"
    DOCKERFILE_PATH="deploy/Dockerfile"
    BUILD_CONTEXT="."
    IMAGE_NAME="claude-code-hub"
    HARBOR_PROJECT="library"
    PLATFORM="linux/amd64"
    ENABLED="true"
  }

  merge_project_settings() {
    IMAGE_NAME="${OVERRIDE_IMAGE_NAME:-${IMAGE_NAME}}"
    HARBOR_PROJECT="${OVERRIDE_HARBOR_PROJECT:-${HARBOR_PROJECT}}"
    PLATFORM="${OVERRIDE_PLATFORM:-${PLATFORM}}"
  }

  validate_project_settings() {
    :
  }

  create_build_context_archive() {
    printf '%s\n' "archive ${1} ${2} ${3}" >> "${call_log}"
    : > "${3}"
    printf '%s\n' "${3}"
  }

  remote_exec_upload_and_execute() {
    printf '%s\n' "remote ${1} ${2} ${3} ${IMAGE_NAME} ${VERSION} ${PLATFORM}" >> "${call_log}"
  }

  build_image_main --config "${remote_env}" --projects "${projects_file}" --project "claude-code-hub" --version "v1.2.3"

  unset -f resolve_project_by_name merge_project_settings validate_project_settings create_build_context_archive remote_exec_upload_and_execute
  reload_build_image_script

  assert_contains "$(cat "${call_log}")" "archive ${source_dir} . " "should package resolved project source and context"
  assert_contains "$(cat "${call_log}")" "remote " "should invoke remote execution"
  assert_contains "$(cat "${call_log}")" " run-from-test claude-code-hub v1.2.3 linux/amd64" "should pass run id and merged image parameters"
}

test_build_image_manual_path_overrides_registry() {
  local call_log="${TEST_TMPDIR}/manual-path.log"
  local manual_source="${TEST_TMPDIR}/manual-project"

  mkdir -p "${manual_source}/docker"
  : > "${manual_source}/docker/Dockerfile"

  build_image_reset_state
  BUILD_IMAGE_RUN_ID="manual-run"

  resolve_project_by_name() {
    fail "resolve_project_by_name should not run when manual path is supplied"
  }

  create_build_context_archive() {
    printf '%s\n' "archive ${1} ${2} ${3}" >> "${call_log}"
    : > "${3}"
    printf '%s\n' "${3}"
  }

  remote_exec_upload_and_execute() {
    printf '%s\n' "remote ${1} ${2} ${3} ${IMAGE_NAME} ${VERSION} ${PLATFORM}" >> "${call_log}"
  }

  build_image_main \
    --config "${remote_env}" \
    --projects "${projects_file}" \
    --source-dir "${manual_source}" \
    --dockerfile-path "docker/Dockerfile" \
    --build-context "." \
    --image-name "manual-image" \
    --version "v9.9.9" \
    --platform "linux/arm64"

  unset -f resolve_project_by_name create_build_context_archive remote_exec_upload_and_execute
  reload_build_image_script

  assert_contains "$(cat "${call_log}")" "archive ${manual_source} . " "manual source dir should be packaged directly"
  assert_contains "$(cat "${call_log}")" " manual-run manual-image v9.9.9 linux/arm64" "manual overrides should win for image name, version, and platform"
}

test_build_image_rejects_dockerfile_path_escape() {
  local manual_source="${TEST_TMPDIR}/escape-project"

  mkdir -p "${manual_source}/deploy" "${TEST_TMPDIR}/outside"
  : > "${manual_source}/deploy/Dockerfile"
  : > "${TEST_TMPDIR}/outside/Dockerfile"

  if build_image_main \
    --config "${remote_env}" \
    --projects "${projects_file}" \
    --source-dir "${manual_source}" \
    --dockerfile-path "../outside/Dockerfile" \
    --build-context "." >"${TEST_TMPDIR}/dockerfile-escape.out" 2>&1; then
    fail "dockerfile path escape should fail"
  fi

  grep -q "Dockerfile path must stay within source directory" "${TEST_TMPDIR}/dockerfile-escape.out" || fail "dockerfile path escape failure should explain source-dir boundary"
}

test_build_image_rejects_disabled_project() {
  local disabled_projects="${TEST_TMPDIR}/disabled-projects.yaml"

  cat >"${disabled_projects}" <<EOF
projects:
  - name: disabled-project
    source_dir: ${source_dir}
    dockerfile_path: deploy/Dockerfile
    build_context: .
    image_name: disabled-project
    harbor_project: library
    platform: linux/amd64
    enabled: false
EOF

  if build_image_main --config "${remote_env}" --projects "${disabled_projects}" --project "disabled-project" >"${TEST_TMPDIR}/disabled-project.out" 2>&1; then
    fail "disabled project should not be buildable"
  fi

  grep -q "Project is disabled" "${TEST_TMPDIR}/disabled-project.out" || fail "disabled project failure should explain disabled status"
}

test_build_image_make_run_id_is_not_second_only() {
  unset BUILD_IMAGE_RUN_ID
  BUILD_IMAGE_NOW="20260307173000"
  BUILD_IMAGE_PID="4242"
  BUILD_IMAGE_NONCE="abc123"

  assert_eq "$(build_image_make_run_id)" "run-20260307173000-4242-abc123" "run id should include extra uniqueness components"

  unset BUILD_IMAGE_NOW BUILD_IMAGE_PID BUILD_IMAGE_NONCE
}

run_all_tests() {
  test_build_image_requires_project_or_path
  test_build_image_uses_project_registry
  test_build_image_manual_path_overrides_registry
  test_build_image_rejects_dockerfile_path_escape
  test_build_image_rejects_disabled_project
  test_build_image_make_run_id_is_not_second_only
  printf 'PASS: build-image tests\n'
}

run_all_tests
