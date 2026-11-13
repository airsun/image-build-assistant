#!/usr/bin/env bash
#
# setup-skill.sh — install the image-build skill into personal skill dirs.
#
# Creates symlinks at ~/.claude/skills/image-build and ~/.cursor/skills/image-build
# pointing at this repo's skill copies (single source of truth), and registers
# the repo home path at ~/.config/image-build-assistant/home for the skill's
# IB_ROOT resolution chain.
#
# Does NOT write shell rc files by default: GUI-launched apps (Cursor, Claude
# Desktop) inherit launchd env rather than shell rc, so a zshrc export would
# not reach them. The config file covers all launch styles; IMAGE_BUILD_HOME
# stays a deliberate override channel (e.g. testing another checkout).
#
# Usage:
#   bash setup-skill.sh [--dry-run] [--force] [--skip-claude] [--skip-cursor]
#                       [--with-shell-export]
#
# Verified on macOS (ln/readlink/sed semantics).
set -euo pipefail

# --- self location (cwd independent) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
IB_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"

CLAUDE_SRC="${IB_ROOT}/.claude/skills/image-build/SKILL.md"
CURSOR_SRC="${IB_ROOT}/.cursor/skills/image-build/SKILL.md"

DRY_RUN=0
FORCE=0
WITH_CLAUDE=1
WITH_CURSOR=1
WITH_SHELL_EXPORT=0

log() { printf '[image-build-assistant] %s\n' "$*"; }
die() { printf '[image-build-assistant] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Dry-run aware command runner: prints the action, executes unless --dry-run.
run_or_print() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '[image-build-assistant] [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

# --- flags ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    --skip-claude) WITH_CLAUDE=0 ;;
    --skip-cursor) WITH_CURSOR=0 ;;
    --with-shell-export) WITH_SHELL_EXPORT=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown flag: $1 (see --help)" ;;
  esac
  shift
done

# --- preflight: the skill copies must live in this repo ---
[[ -f "${CLAUDE_SRC}" ]] || die "missing ${CLAUDE_SRC} — run this script from the image-build-assistant repo"
[[ -f "${CURSOR_SRC}" ]] || die "missing ${CURSOR_SRC} — run this script from the image-build-assistant repo"

# --- symlink install (idempotent) ---
install_symlink() {
  local link="$1" target="$2"
  local parent cur

  if [[ -L "${link}" ]]; then
    cur="$(readlink "${link}")"
    if [[ "${cur}" == "${target}" ]]; then
      log "already installed: ${link}"
      return 0
    fi
    if [[ "${FORCE}" -eq 1 ]]; then
      log "replacing stale symlink: ${link} (was -> ${cur})"
      run_or_print rm "${link}"
    else
      die "${link} points elsewhere (-> ${cur}); pass --force to replace"
    fi
  elif [[ -e "${link}" ]]; then
    die "${link} exists as a regular file/dir — refusing to touch it; remove it manually first"
  fi

  parent="$(dirname "${link}")"
  [[ -d "${parent}" ]] || run_or_print mkdir -p "${parent}"
  log "linking ${link} -> ${target}"
  run_or_print ln -s "${target}" "${link}"
}

# --- config file: single line with the repo absolute path ---
install_config() {
  local config_file="${HOME}/.config/image-build-assistant/home"
  local current

  if [[ -f "${config_file}" ]]; then
    current="$(cat "${config_file}")"
    if [[ "${current}" == "${IB_ROOT}" ]]; then
      log "config up to date: ${config_file}"
      return 0
    fi
    log "updating config ${config_file} (${current} -> ${IB_ROOT})"
  else
    log "writing config ${config_file}"
  fi

  [[ "${DRY_RUN}" -eq 1 ]] && return 0
  mkdir -p "$(dirname "${config_file}")"
  printf '%s\n' "${IB_ROOT}" > "${config_file}"
}

# --- optional shell export (off by default, see header rationale) ---
install_shell_export() {
  local zshrc="${HOME}/.zshrc"
  local line="export IMAGE_BUILD_HOME=\"${IB_ROOT}\""

  if [[ ! -f "${zshrc}" ]]; then
    log "writing ${zshrc}"
    [[ "${DRY_RUN}" -eq 1 ]] && return 0
    printf '%s\n' "${line}" > "${zshrc}"
    return 0
  fi

  if grep -q '^export IMAGE_BUILD_HOME=' "${zshrc}"; then
    log "updating IMAGE_BUILD_HOME export in ${zshrc}"
    [[ "${DRY_RUN}" -eq 1 ]] && return 0
    # BSD sed (macOS) requires the -i '' argument form
    sed -i '' "s|^export IMAGE_BUILD_HOME=.*|${line}|" "${zshrc}"
  else
    log "appending export to ${zshrc}"
    [[ "${DRY_RUN}" -eq 1 ]] && return 0
    printf '%s\n' "${line}" >> "${zshrc}"
  fi
}

# --- post-install verification ---
verify_install() {
  if [[ "${WITH_CLAUDE}" -eq 1 ]]; then
    [[ -L "${HOME}/.claude/skills/image-build" ]] || die "post-install check failed: claude symlink missing"
    [[ -r "${HOME}/.claude/skills/image-build/SKILL.md" ]] || die "post-install check failed: claude skill unreadable"
  fi
  if [[ "${WITH_CURSOR}" -eq 1 ]]; then
    [[ -L "${HOME}/.cursor/skills/image-build" ]] || die "post-install check failed: cursor symlink missing"
    [[ -r "${HOME}/.cursor/skills/image-build/SKILL.md" ]] || die "post-install check failed: cursor skill unreadable"
  fi
  [[ "$(cat "${HOME}/.config/image-build-assistant/home" 2>/dev/null || true)" == "${IB_ROOT}" ]] \
    || die "post-install check failed: config file missing or stale"
}

main() {
  log "IB_ROOT=${IB_ROOT}"

  if [[ "${WITH_CLAUDE}" -eq 1 ]]; then
    install_symlink "${HOME}/.claude/skills/image-build" "${IB_ROOT}/.claude/skills/image-build"
  fi
  if [[ "${WITH_CURSOR}" -eq 1 ]]; then
    install_symlink "${HOME}/.cursor/skills/image-build" "${IB_ROOT}/.cursor/skills/image-build"
  fi
  install_config
  [[ "${WITH_SHELL_EXPORT}" -eq 1 ]] && install_shell_export

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "dry-run complete — no changes made"
    return 0
  fi

  verify_install
  log "install complete. Restart Claude Code / Cursor sessions to pick up the skill."
  log "Note: unset IMAGE_BUILD_HOME before a session to let the config file take over."
}

main "$@"
