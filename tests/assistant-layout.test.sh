#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSISTANT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

required_paths=(
  "bin/build-image.sh"
  "config/remote.env.example"
  "config/projects.yaml"
  "lib/packaging.sh"
  "lib/project-resolver.sh"
  "lib/remote-exec.sh"
  "remote/remote-build-entry.sh"
  "docs/usage.md"
)

for path in "${required_paths[@]}"; do
  [[ -f "${ASSISTANT_ROOT}/${path}" ]] || fail "missing required file: ${path}"
done

printf 'PASS: assistant layout test\n'
