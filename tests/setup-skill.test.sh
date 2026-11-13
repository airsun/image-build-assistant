#!/usr/bin/env bash
# Tests for image-builder/scripts/setup-skill.sh.
# Pure local bash: fake HOME in a mktemp dir, fake IB repo fixture, no network.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSISTANT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
SETUP_SCRIPT="${ASSISTANT_ROOT}/image-builder/scripts/setup-skill.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/setup-skill-test.XXXXXX")"
# Normalize symlinks (macOS TMPDIR is /var -> /private/var) so paths match the
# pwd -P resolution inside setup-skill.sh.
WORK="$(cd "${WORK}" && pwd -P)"
FAKE_IB="${WORK}/fake-ib"
FAIL_LOG="${WORK}/stderr.log"
HOME_N=0
FAKE_HOME=""
trap 'rm -rf "${WORK}"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# Each test case gets its own fake HOME so state never leaks between cases.
new_home() {
  HOME_N=$((HOME_N + 1))
  FAKE_HOME="${WORK}/home-${HOME_N}"
  mkdir -p "${FAKE_HOME}"
}

# Build a fake IB repo: skill copies in .claude/.cursor + the real setup script.
make_fake_ib() {
  mkdir -p "${FAKE_IB}/.claude/skills/image-build"
  mkdir -p "${FAKE_IB}/.cursor/skills/image-build"
  printf '# fake skill\n' > "${FAKE_IB}/.claude/skills/image-build/SKILL.md"
  printf '# fake skill\n' > "${FAKE_IB}/.cursor/skills/image-build/SKILL.md"
  mkdir -p "${FAKE_IB}/image-builder/scripts"
  cp "${SETUP_SCRIPT}" "${FAKE_IB}/image-builder/scripts/setup-skill.sh"
}

run_setup() {
  HOME="${FAKE_HOME}" bash "${FAKE_IB}/image-builder/scripts/setup-skill.sh" "$@" >/dev/null 2>"${FAIL_LOG}"
}

expect_failure() {
  # usage: expect_failure <stderr-grep-pattern> [flags...]
  local pattern="${1}"
  shift
  if HOME="${FAKE_HOME}" bash "${FAKE_IB}/image-builder/scripts/setup-skill.sh" "$@" >/dev/null 2>"${FAIL_LOG}"; then
    fail "expected non-zero exit for: $*"
  fi
  grep -q -- "${pattern}" "${FAIL_LOG}" || fail "stderr missing '${pattern}'"
}

test_fresh_install() {
  new_home
  run_setup || fail "fresh install should exit 0"
  [[ -L "${FAKE_HOME}/.claude/skills/image-build" ]] || fail "claude symlink missing"
  [[ -L "${FAKE_HOME}/.cursor/skills/image-build" ]] || fail "cursor symlink missing"
  [[ "$(readlink "${FAKE_HOME}/.claude/skills/image-build")" == "${FAKE_IB}/.claude/skills/image-build" ]] \
    || fail "claude symlink target wrong"
  [[ -r "${FAKE_HOME}/.claude/skills/image-build/SKILL.md" ]] || fail "skill unreadable via symlink"
  [[ "$(cat "${FAKE_HOME}/.config/image-build-assistant/home")" == "${FAKE_IB}" ]] \
    || fail "config home file content wrong"
}

test_idempotent_rerun() {
  new_home
  run_setup || fail "first run should exit 0"
  local link_before config_before
  link_before="$(readlink "${FAKE_HOME}/.claude/skills/image-build")"
  config_before="$(cat "${FAKE_HOME}/.config/image-build-assistant/home")"
  run_setup || fail "rerun should exit 0"
  [[ "$(readlink "${FAKE_HOME}/.claude/skills/image-build")" == "${link_before}" ]] \
    || fail "rerun changed symlink"
  [[ "$(cat "${FAKE_HOME}/.config/image-build-assistant/home")" == "${config_before}" ]] \
    || fail "rerun changed config"
}

test_stale_symlink_without_force() {
  new_home
  mkdir -p "${FAKE_HOME}/.claude/skills"
  ln -s "${WORK}/elsewhere" "${FAKE_HOME}/.claude/skills/image-build"
  expect_failure "--force"
}

test_stale_symlink_force() {
  new_home
  mkdir -p "${FAKE_HOME}/.claude/skills"
  ln -s "${WORK}/elsewhere" "${FAKE_HOME}/.claude/skills/image-build"
  run_setup --force || fail "--force should exit 0"
  [[ "$(readlink "${FAKE_HOME}/.claude/skills/image-build")" == "${FAKE_IB}/.claude/skills/image-build" ]] \
    || fail "--force did not replace symlink"
}

test_regular_dir_protected() {
  new_home
  mkdir -p "${FAKE_HOME}/.claude/skills/image-build"
  printf 'sentinel\n' > "${FAKE_HOME}/.claude/skills/image-build/keep.txt"
  if run_setup; then
    fail "regular dir at link path should abort"
  fi
  [[ -f "${FAKE_HOME}/.claude/skills/image-build/keep.txt" ]] \
    || fail "regular dir was deleted"
}

test_parent_dirs_created() {
  new_home
  run_setup || fail "install should create parent dirs"
  [[ -d "${FAKE_HOME}/.claude/skills" ]] || fail "claude skills parent not created"
  [[ -d "${FAKE_HOME}/.cursor/skills" ]] || fail "cursor skills parent not created"
}

test_dry_run_writes_nothing() {
  new_home
  run_setup --dry-run || fail "dry-run should exit 0"
  [[ ! -e "${FAKE_HOME}/.claude/skills/image-build" ]] || fail "dry-run created claude symlink"
  [[ ! -e "${FAKE_HOME}/.cursor/skills/image-build" ]] || fail "dry-run created cursor symlink"
  [[ ! -e "${FAKE_HOME}/.config/image-build-assistant/home" ]] || fail "dry-run wrote config"
}

test_detached_script() {
  # script without the skill copies beside it must fail with a clear message
  new_home
  local detached="${WORK}/detached"
  mkdir -p "${detached}"
  cp "${SETUP_SCRIPT}" "${detached}/setup-skill.sh"
  if HOME="${FAKE_HOME}" bash "${detached}/setup-skill.sh" >/dev/null 2>"${FAIL_LOG}"; then
    fail "detached script should fail"
  fi
  grep -q "missing" "${FAIL_LOG}" || fail "detached script error lacks 'missing' hint"
}

test_shell_export_single_line() {
  new_home
  run_setup --with-shell-export || fail "install with export should exit 0"
  [[ -f "${FAKE_HOME}/.zshrc" ]] || fail ".zshrc not created"
  local n
  n="$(grep -c '^export IMAGE_BUILD_HOME=' "${FAKE_HOME}/.zshrc")"
  [[ "${n}" -eq 1 ]] || fail "expected 1 export line, got ${n}"
  run_setup --with-shell-export || fail "rerun with export should exit 0"
  n="$(grep -c '^export IMAGE_BUILD_HOME=' "${FAKE_HOME}/.zshrc")"
  [[ "${n}" -eq 1 ]] || fail "export duplicated on rerun: ${n} lines"
}

test_skip_claude() {
  new_home
  run_setup --skip-claude || fail "install with --skip-claude should exit 0"
  [[ ! -e "${FAKE_HOME}/.claude/skills/image-build" ]] || fail "--skip-claude still created claude symlink"
  [[ -L "${FAKE_HOME}/.cursor/skills/image-build" ]] || fail "--skip-claude missing cursor symlink"
}

test_config_overwrite() {
  new_home
  mkdir -p "${FAKE_HOME}/.config/image-build-assistant"
  printf 'old/value\n' > "${FAKE_HOME}/.config/image-build-assistant/home"
  run_setup || fail "install should exit 0"
  [[ "$(cat "${FAKE_HOME}/.config/image-build-assistant/home")" == "${FAKE_IB}" ]] \
    || fail "config not overwritten with new home"
}

main() {
  make_fake_ib
  test_fresh_install
  test_idempotent_rerun
  test_stale_symlink_without_force
  test_stale_symlink_force
  test_regular_dir_protected
  test_parent_dirs_created
  test_dry_run_writes_nothing
  test_detached_script
  test_shell_export_single_line
  test_skip_claude
  test_config_overwrite
  printf 'PASS: setup-skill test\n'
}

main
