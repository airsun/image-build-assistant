#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSISTANT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"

# shellcheck source=../lib/project-resolver.sh
source "${ASSISTANT_ROOT}/lib/project-resolver.sh"

TEST_TMPDIR="$(mktemp -d "/tmp/project-resolver-test.XXXXXX")"
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

registry_file="${TEST_TMPDIR}/projects.yaml"

cat >"${registry_file}" <<'EOF'
projects:
  - name: claude-code-hub
    source_dir: /tmp/claude-code-hub
    dockerfile_path: deploy/Dockerfile
    build_context: .
    image_name: claude-code-hub
    harbor_project: library
    platform: linux/amd64
    enabled: true
  - name: worker-service
    source_dir: /tmp/worker-service
    dockerfile_path: build/Dockerfile
    build_context: app
    image_name: worker-service
    harbor_project: services
    platform: linux/arm64
    enabled: false
EOF

test_resolve_project_by_name() {
  project_resolver_clear
  resolve_project_by_name "${registry_file}" "claude-code-hub"

  assert_eq "${PROJECT_NAME}" "claude-code-hub" "should resolve project name"
  assert_eq "${SOURCE_DIR}" "/tmp/claude-code-hub" "should resolve source dir"
  assert_eq "${DOCKERFILE_PATH}" "deploy/Dockerfile" "should resolve dockerfile path"
  assert_eq "${BUILD_CONTEXT}" "." "should resolve build context"
  assert_eq "${IMAGE_NAME}" "claude-code-hub" "should resolve image name"
  assert_eq "${HARBOR_PROJECT}" "library" "should resolve harbor project"
  assert_eq "${PLATFORM}" "linux/amd64" "should resolve platform"
  assert_eq "${ENABLED}" "true" "should resolve enabled flag"
}

test_missing_project_fails() {
  project_resolver_clear

  if resolve_project_by_name "${registry_file}" "missing-project" >"${TEST_TMPDIR}/missing.out" 2>&1; then
    fail "resolve_project_by_name should fail for unknown project"
  fi

  grep -q "Project not found" "${TEST_TMPDIR}/missing.out" || fail "unknown project failure should explain missing project"
}

test_merge_project_settings_prefers_overrides() {
  project_resolver_clear
  resolve_project_by_name "${registry_file}" "claude-code-hub"

  DEFAULT_IMAGE_NAME="default-image"
  DEFAULT_HARBOR_PROJECT="default-project"
  DEFAULT_PLATFORM="linux/amd64"
  OVERRIDE_IMAGE_NAME="override-image"
  OVERRIDE_PLATFORM="linux/arm64"

  merge_project_settings

  assert_eq "${IMAGE_NAME}" "override-image" "override image should win"
  assert_eq "${HARBOR_PROJECT}" "library" "project harbor project should beat defaults"
  assert_eq "${PLATFORM}" "linux/arm64" "override platform should win"
}

test_resolve_relative_source_dir_against_registry_file() {
  local relative_registry="${TEST_TMPDIR}/relative/projects.yaml"

  mkdir -p "${TEST_TMPDIR}/relative/projects/claude-code-hub"

  cat > "${relative_registry}" <<'EOF'
projects:
  - name: claude-code-hub
    source_dir: ./projects/claude-code-hub
    dockerfile_path: deploy/Dockerfile
    build_context: .
EOF

  project_resolver_clear
  resolve_project_by_name "${relative_registry}" "claude-code-hub"

  assert_eq "${SOURCE_DIR}" "${TEST_TMPDIR}/relative/projects/claude-code-hub" "relative source_dir should resolve against registry file directory"
}

test_validate_project_settings_rejects_missing_required_fields() {
  project_resolver_clear
  PROJECT_NAME="broken-project"
  SOURCE_DIR=""
  DOCKERFILE_PATH="deploy/Dockerfile"
  BUILD_CONTEXT="."

  if validate_project_settings >"${TEST_TMPDIR}/validate.out" 2>&1; then
    fail "validate_project_settings should fail when source_dir is missing"
  fi

  grep -q "Missing required project setting: SOURCE_DIR" "${TEST_TMPDIR}/validate.out" || fail "validation should name missing required field"
}

run_all_tests() {
  test_resolve_project_by_name
  test_missing_project_fails
  test_merge_project_settings_prefers_overrides
  test_resolve_relative_source_dir_against_registry_file
  test_validate_project_settings_rejects_missing_required_fields
  printf 'PASS: project resolver tests\n'
}

run_all_tests
