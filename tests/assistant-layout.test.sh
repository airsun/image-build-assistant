#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSISTANT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

required_paths=(
  "image-builder/build.sh"
  "image-builder/remote.env.example"
  "image-builder/projects.yaml"
  "image-builder/scripts/packaging.sh"
  "image-builder/scripts/project-resolver.sh"
  "image-builder/scripts/remote-exec.sh"
  "image-builder/scripts/remote-build-entry.sh"
  "docs/usage.md"
)

for path in "${required_paths[@]}"; do
  [[ -f "${ASSISTANT_ROOT}/${path}" ]] || fail "missing required file: ${path}"
done

printf 'PASS: assistant layout test\n'
