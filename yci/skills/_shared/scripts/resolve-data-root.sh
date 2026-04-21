#!/usr/bin/env bash
# yci — resolve the runtime data root.
#
# Precedence (highest to lowest):
#   1. --data-root <path>  CLI flag passed to this script or the sourced function
#   2. $YCI_DATA_ROOT      environment variable
#   3. ${HOME}/.config/yci default fallback
#
# On first use the resolved directory is created with mode 0700 (idempotent).
# Prints the resolved absolute path (no trailing slash) to stdout.
#
# Source into another script to expose yci_resolve_data_root(), or run directly.
#
# Exit codes:
#   0  success — resolved path printed to stdout
#   3  runtime error — unwritable or invalid path (message on stderr)

set -euo pipefail

# ---------------------------------------------------------------------------
# yci_resolve_data_root [--data-root <path>] [--data-root=<path>]
# ---------------------------------------------------------------------------

yci_resolve_data_root() {
    local data_root=""

    # Parse optional --data-root flag; stop at first non-flag or --.
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --data-root)
                if [ -z "${2:-}" ]; then
                    printf 'yci: --data-root requires a value\n' >&2
                    return 3
                fi
                data_root="$2"
                shift 2
                ;;
            --data-root=*)
                data_root="${1#*=}"
                shift
                ;;
            --) shift; break ;;
            *)  break ;;
        esac
    done

    # Fall back to env var, then default.
    if [ -z "$data_root" ]; then
        data_root="${YCI_DATA_ROOT:-${HOME}/.config/yci}"
    fi

    # Reject empty string (e.g. YCI_DATA_ROOT="" with no flag).
    if [ -z "$data_root" ]; then
        printf "yci: cannot resolve data root path: ''\n" >&2
        printf '  ensure the path is a valid absolute or expandable path\n' >&2
        return 3
    fi

    # Expand a leading ~ if the caller passed it as a literal character.
    # Use $tilde in comparisons to keep shellcheck (SC2088) quiet about the
    # intentional literal tilde match.
    local tilde='~'
    if [ "$data_root" = "$tilde" ]; then
        data_root="${HOME}"
    elif [ "${data_root:0:2}" = "${tilde}/" ]; then
        data_root="${HOME}/${data_root:2}"
    fi

    # If the directory already exists, canonicalize via cd + pwd.
    if [ -d "$data_root" ]; then
        data_root="$(cd "$data_root" && pwd -P)"
    else
        # Make the path absolute before mkdir.
        case "$data_root" in
            /*) ;;
            *)  data_root="$(pwd -P)/${data_root}" ;;
        esac
        # Strip any trailing slashes.
        data_root="${data_root%/}"

        # Attempt to create the directory (mkdir -p is idempotent).
        if ! mkdir -p "$data_root" 2>/dev/null; then
            printf 'yci: data root is not writable: %s\n' "$data_root" >&2
            printf "  check directory permissions or set a writable path via --data-root or \$YCI_DATA_ROOT\n" >&2
            return 3
        fi
        chmod 0700 "$data_root" 2>/dev/null || true
        # Re-canonicalize now that the directory exists.
        data_root="$(cd "$data_root" && pwd -P)"
    fi

    # Final sanity checks: must be a directory and must be writable.
    if [ ! -d "$data_root" ]; then
        printf "yci: cannot resolve data root path: '%s'\n" "$data_root" >&2
        printf '  ensure the path is a valid absolute or expandable path\n' >&2
        return 3
    fi

    if [ ! -w "$data_root" ]; then
        printf 'yci: data root is not writable: %s\n' "$data_root" >&2
        printf "  check directory permissions or set a writable path via --data-root or \$YCI_DATA_ROOT\n" >&2
        return 3
    fi

    printf '%s\n' "$data_root"
}

# ---------------------------------------------------------------------------
# Standalone entry point — only runs when the script is executed directly,
# not when it is sourced.
# ---------------------------------------------------------------------------

if [ "${BASH_SOURCE[0]:-}" = "$0" ]; then
    yci_resolve_data_root "$@"
fi
