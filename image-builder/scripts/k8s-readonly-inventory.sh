#!/usr/bin/env bash
# Thin entry: run read-only cluster inventory (JSON). Requires kubectl + current context.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${SCRIPT_DIR}/k8s_readonly_inventory.py" "$@"
