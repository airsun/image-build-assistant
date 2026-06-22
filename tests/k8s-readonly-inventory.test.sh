#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSISTANT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
PY="${ASSISTANT_ROOT}/image-builder/scripts/k8s_readonly_inventory.py"
SH="${ASSISTANT_ROOT}/image-builder/scripts/k8s-readonly-inventory.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -f "${PY}" ]] || fail "missing ${PY}"
[[ -f "${SH}" ]] || fail "missing ${SH}"

python3 -c "import ast; ast.parse(open('${PY}').read())" || fail "Python syntax invalid"
bash -n "${SH}" || fail "bash wrapper syntax invalid"

printf 'PASS: k8s-readonly-inventory layout/syntax tests\n'
