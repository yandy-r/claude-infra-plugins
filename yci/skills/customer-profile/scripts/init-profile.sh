#!/usr/bin/env bash
# yci — scaffold a new customer profile from _template.yaml.
#
# Usage: init-profile.sh <data-root> <customer> [--force] [--allow-reserved]
# Stdout: confirmation message on success.
# Stderr: error messages only.
# Exit 0: success.
# Exit 1: invalid id, reserved id, or profile already exists without --force.
# Exit 3: runtime error (mkdir failure, cp failure).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TEMPLATE="${SCRIPT_DIR}/../references/_template.yaml"

data_root="${1:?usage: init-profile.sh <data-root> <customer> [--force] [--allow-reserved]}"
customer="${2:?usage: init-profile.sh <data-root> <customer> [--force] [--allow-reserved]}"
shift 2

force=0
allow_reserved=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --force)           force=1 ;;
        --allow-reserved)  allow_reserved=1 ;;
        *)
            printf "yci: unknown flag: '%s'\n" "$1" >&2
            printf '  valid flags: --force, --allow-reserved\n' >&2
            exit 1
            ;;
    esac
    shift
done

# --- validate customer id format (init-invalid-customer-id, exit 1) ---------
# Reserved ids start with '_'; they fail this regex (requires [a-z0-9] first).
# We check reserved separately below, so regex only tests format here.
if ! [[ "$customer" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    # Could be a reserved id (starts with _) — check that first for a better message.
    if [[ "$customer" == _* ]]; then
        if [ "$allow_reserved" -eq 0 ]; then
            printf "yci: reserved customer id: '%s'\n" "$customer" >&2
            printf "  ids starting with '_' are reserved for internal use\n" >&2
            printf '  pass --allow-reserved to create a reserved-namespace profile\n' >&2
            exit 1
        fi
        # --allow-reserved passed; still validate the rest of the id.
        # Reserved ids don't need to match [a-z0-9][a-z0-9-]* but must at
        # minimum be non-empty after the underscore and contain no spaces.
        if [[ "$customer" =~ [[:space:]] ]]; then
            printf "yci: invalid customer id: '%s'\n" "$customer" >&2
            printf '  allowed pattern: [a-z0-9][a-z0-9-]*  (lowercase, hyphens only)\n' >&2
            exit 1
        fi
    else
        printf "yci: invalid customer id: '%s'\n" "$customer" >&2
        printf '  allowed pattern: [a-z0-9][a-z0-9-]*  (lowercase, hyphens only)\n' >&2
        exit 1
    fi
else
    # Passes main regex — check reserved regardless (reserved start with _ which fails regex,
    # so this branch means the id does NOT start with _ and is fully valid).
    :
fi

# Separate reserved check for ids that pass the format regex (none currently,
# since _ prefix fails [a-z0-9] first char; kept for defensive correctness).
if [[ "$customer" == _* ]] && [ "$allow_reserved" -eq 0 ]; then
    printf "yci: reserved customer id: '%s'\n" "$customer" >&2
    printf "  ids starting with '_' are reserved for internal use\n" >&2
    printf '  pass --allow-reserved to create a reserved-namespace profile\n' >&2
    exit 1
fi

profiles_dir="${data_root}/profiles"
target="${profiles_dir}/${customer}.yaml"

# --- create profiles directory (mode 0700) if absent -----------------------
if [ ! -d "$profiles_dir" ]; then
    if ! mkdir -p "$profiles_dir"; then
        printf 'yci: cannot create profiles directory: %s\n' "$profiles_dir" >&2
        exit 3
    fi
    chmod 0700 "$profiles_dir"
fi

# --- refuse overwrite without --force (init-profile-exists, exit 1) --------
if [ -f "$target" ] && [ "$force" -eq 0 ]; then
    printf 'yci: profile already exists: %s\n' "$target" >&2
    printf '  pass --force to overwrite, or choose a different customer id\n' >&2
    exit 1
fi

# --- copy template ----------------------------------------------------------
if ! cp "$TEMPLATE" "$target"; then
    printf 'yci: failed to copy template to: %s\n' "$target" >&2
    exit 3
fi
chmod 0600 "$target"

# --- confirmation -----------------------------------------------------------
printf 'yci: scaffolded profile at %s\n' "$target"
printf '  edit the <TODO: ...> placeholders, then run: /yci:switch %s\n' "$customer"
