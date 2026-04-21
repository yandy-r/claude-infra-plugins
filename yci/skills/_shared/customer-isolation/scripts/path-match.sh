#!/usr/bin/env bash
# yci — canonical-form path-prefix containment helpers.
#
# Sourceable library. Exports:
#   path_canonicalize <path>   → echoes the realpath (follows symlinks)
#   path_is_under <cand> <root>→ exit 0 iff $cand is $root or a descendant
#
# Usage: source this file; both functions consult a one-time probe of
# `realpath -m` support (GNU) and fall back to Python when needed (macOS BSD).
#
# No `set -euo pipefail` here — this is a sourceable library.

_PM_HAS_M=0

_pm_probe_realpath_m() {
    if command -v realpath >/dev/null 2>&1 && realpath -m / >/dev/null 2>&1; then
        _PM_HAS_M=1
    else
        _PM_HAS_M=0
    fi
}
_pm_probe_realpath_m

path_canonicalize() {
    local p="$1"
    if [ "$_PM_HAS_M" = "1" ]; then
        realpath -m "$p"
    else
        python3 -c 'import os.path,sys; print(os.path.realpath(sys.argv[1]))' "$p"
    fi
}

path_is_under() {
    local cand root cand_c root_c
    cand="$1"; root="$2"
    cand_c="$(path_canonicalize "$cand")"
    root_c="$(path_canonicalize "$root")"
    # Empty canonicalization → fail safe (not under).
    [ -z "$cand_c" ] && return 1
    [ -z "$root_c" ] && return 1
    # Strip trailing slash from root for consistent comparison.
    root_c="${root_c%/}"
    [ "$cand_c" = "$root_c" ] && return 0
    # Prefix-with-separator: $cand must start with $root + "/"
    # Using case with quoted variable: * in the unquoted suffix is a glob star
    # but * inside "$root_c" is treated literally, making this safe with paths
    # containing glob characters.
    case "$cand_c" in
        "$root_c"/*) return 0 ;;
        *) return 1 ;;
    esac
}
