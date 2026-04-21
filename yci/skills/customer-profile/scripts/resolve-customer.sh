#!/usr/bin/env bash
# yci — resolve active customer id via 4-tier precedence chain.
#
# Tiers (first non-empty, valid id wins):
#   1. $YCI_CUSTOMER           (env var; trimmed; must match [a-z0-9][a-z0-9-]*)
#   2. .yci-customer dotfile   (walk up from $PWD, stop at $HOME or /)
#   3. state.json .active      (<data-root>/state.json)
#   4. refuse with error       (exit 1)
#
# Usage: resolve-customer.sh [--data-root <path>]
# Stdout: customer id string (no trailing whitespace) on success.
# Stderr: diagnostic messages on error.
# Exit 0: success — customer id printed to stdout.
# Exit 1: no customer resolved, or invalid id format.
#
# See yci/skills/customer-profile/references/precedence.md for the authoritative spec.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SHARED_DIR="${SCRIPT_DIR}/../../_shared/scripts"

# shellcheck source=/dev/null
source "${SHARED_DIR}/resolve-data-root.sh"

readonly YCI_ID_RE='^[a-z0-9][a-z0-9-]*$'

# NOTE on reserved ids (_internal, _template):
# These ids start with '_', which already fails YCI_ID_RE (requires [a-z0-9] first char).
# If the regex is ever relaxed, reserved ids MUST remain blocked — see init-reserved-id
# in error-messages.md for the init-side policy. Resolver behavior: skip (fall through),
# not an error — a stale env var or dotfile should not abort the session.

yci_trim() {
    # Strip leading and trailing whitespace.
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

yci_validate_id() {
    # Return 0 if id matches [a-z0-9][a-z0-9-]*; 1 otherwise.
    [[ "$1" =~ $YCI_ID_RE ]]
}

yci_read_dotfile_line() {
    # Read the first non-empty, non-comment, trimmed line from a dotfile.
    # Returns 0 and prints the line on success; returns 1 if no usable line found.
    local file="$1" line trimmed
    [ -r "$file" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in \#*) continue ;; esac
        trimmed="$(yci_trim "$line")"
        [ -z "$trimmed" ] && continue
        printf '%s' "$trimmed"
        return 0
    done < "$file"
    return 1
}

yci_walkup_dotfile() {
    # Walk from $PWD upward looking for .yci-customer dotfiles.
    # $HOME is checked (inclusive); the walk never ascends past $HOME.
    # Prints the customer id and returns 0 on success; returns 1 if not found.
    local dir home_abs candidate
    dir="$(pwd -P)"
    home_abs="${HOME:-/}"
    home_abs="$(cd "$home_abs" 2>/dev/null && pwd -P || printf '%s' "$home_abs")"

    while :; do
        if [ -f "$dir/.yci-customer" ]; then
            if candidate="$(yci_read_dotfile_line "$dir/.yci-customer")"; then
                printf '%s' "$candidate"
                return 0
            fi
            # File has no usable lines — continue walking up
        fi
        # Stop AFTER checking $HOME; never ascend past it
        [ "$dir" = "$home_abs" ] && break
        [ "$dir" = "/" ] && break
        dir="$(dirname "$dir")"
    done
    return 1
}

yci_read_state_active() {
    # Read .active from <data-root>/state.json via embedded Python.
    # Prints the trimmed value and returns 0 on success; returns 1 otherwise.
    local state_path="${1}/state.json"
    [ -f "$state_path" ] || return 1
    python3 - "$state_path" 2>/dev/null <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception:
    sys.exit(1)
active = data.get("active")
if isinstance(active, str) and active.strip():
    print(active.strip(), end="")
else:
    sys.exit(1)
PY
}

yci_emit_invalid_id() {
    # Emit resolver-invalid-id-format (exit 1) — error-messages.md verbatim.
    local id="$1"
    printf "yci: invalid customer id: '%s'\n" "$id" >&2
    printf '  allowed pattern: [a-z0-9][a-z0-9-]*  (lowercase, hyphens only)\n' >&2
    printf 'Check $YCI_CUSTOMER, your .yci-customer dotfile, or state.json .active field.\n' >&2
}

yci_emit_refusal() {
    # Emit resolver-no-active-customer (exit 1) — error-messages.md verbatim.
    # Args: <data_root> <env_status>
    # env_status is "unset" or "empty (whitespace-only)"
    local data_root="$1" env_status="$2"
    local cwd stop_at
    cwd="$(pwd -P)"
    stop_at="$(cd "${HOME:-/}" 2>/dev/null && pwd -P || printf '/')"
    printf 'yci: no active customer.\n' >&2
    printf '  $YCI_CUSTOMER: %s\n' "$env_status" >&2
    printf '  .yci-customer: not found (searched from %s up to %s)\n' "$cwd" "$stop_at" >&2
    printf '  state.json: no active customer at %s/state.json\n' "$data_root" >&2
    printf 'Run `/yci:init <customer>` to create a profile, or `/yci:switch <customer>` to activate one.\n' >&2
}

main() {
    local data_root env_status="unset"
    data_root="$(yci_resolve_data_root "$@")"

    # Tier 1 — $YCI_CUSTOMER env var
    if [ -n "${YCI_CUSTOMER+x}" ]; then
        # Variable is set (possibly empty or whitespace-only)
        local env_id
        env_id="$(yci_trim "${YCI_CUSTOMER}")"
        if [ -n "$env_id" ]; then
            if yci_validate_id "$env_id"; then
                printf '%s\n' "$env_id"
                return 0
            else
                # Set, non-empty after trim, but invalid format — hard error (exit 1).
                yci_emit_invalid_id "$env_id"
                return 1
            fi
        fi
        # Variable is set but empty or whitespace-only — fall through
        env_status="empty (whitespace-only)"
    fi

    # Tier 2 — .yci-customer dotfile walk-up
    local dotfile_id
    if dotfile_id="$(yci_walkup_dotfile)"; then
        if yci_validate_id "$dotfile_id"; then
            printf '%s\n' "$dotfile_id"
            return 0
        else
            # Dotfile contains an invalid id — surface the format error (exit 1).
            yci_emit_invalid_id "$dotfile_id"
            return 1
        fi
    fi

    # Tier 3 — state.json .active (MRU)
    local mru_id
    if mru_id="$(yci_read_state_active "$data_root")"; then
        if yci_validate_id "$mru_id"; then
            printf '%s\n' "$mru_id"
            return 0
        else
            yci_emit_invalid_id "$mru_id"
            return 1
        fi
    fi

    # Tier 4 — refuse
    yci_emit_refusal "$data_root" "$env_status"
    return 1
}

main "$@"
