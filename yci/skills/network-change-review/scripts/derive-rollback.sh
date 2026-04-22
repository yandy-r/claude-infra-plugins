#!/usr/bin/env bash
# derive-rollback.sh — thin wrapper over the shared yci rollback helper.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd -P)}"
SHARED_HELPER="${PLUGIN_ROOT}/skills/_shared/scripts/derive-change-rollback.sh"

if [[ ! -f "$SHARED_HELPER" || ! -x "$SHARED_HELPER" ]]; then
  printf 'derive-rollback.sh: missing or non-executable helper: %s\n' "$SHARED_HELPER" >&2
  exit 2
fi

exec bash "$SHARED_HELPER" "$@"
