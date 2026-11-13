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
  "image-builder/scripts/remote-code-pull.sh"
  "image-builder/scripts/setup-skill.sh"
  "docs/usage.md"
  "docs/specs/oss-remote-pull.md"
  "docs/specs/image-build-skill.md"
  ".claude/skills/oss-image-build/SKILL.md"
  ".cursor/skills/oss-image-build/SKILL.md"
  ".claude/skills/image-build/SKILL.md"
  ".cursor/skills/image-build/SKILL.md"
)

for path in "${required_paths[@]}"; do
  [[ -f "${ASSISTANT_ROOT}/${path}" ]] || fail "missing required file: ${path}"
done

# image-build skill: both copies must be byte-identical (no drift)
cmp -s \
  "${ASSISTANT_ROOT}/.claude/skills/image-build/SKILL.md" \
  "${ASSISTANT_ROOT}/.cursor/skills/image-build/SKILL.md" \
  || fail "image-build SKILL.md copies differ between .claude and .cursor"

# structural markers in the skill text (only the .claude copy is tested;
# cmp above guarantees the .cursor copy matches)
skill="${ASSISTANT_ROOT}/.claude/skills/image-build/SKILL.md"
for marker in \
  "IMAGE_BUILD_HOME" \
  "setup-skill.sh" \
  "remote.env.example" \
  "k8s-deploy-intent.md"; do
  grep -q "${marker}" "${skill}" || fail "image-build SKILL.md missing marker: ${marker}"
done

# no repo-relative spec path inside the skill (breaks outside this repo)
grep -q "\.\./\.\./\.\./docs/specs" "${skill}" \
  && fail "image-build SKILL.md contains repo-relative spec path (../../..)"

printf 'PASS: assistant layout test\n'
