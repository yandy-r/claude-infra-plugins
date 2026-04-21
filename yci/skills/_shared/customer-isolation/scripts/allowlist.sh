#!/usr/bin/env bash
# yci — per-tenant allowlist loader + query.
#
# Sourceable library. Exports:
#   allowlist_load <data-root> <active-customer>
#     Populates arrays ALLOWLIST_PATHS=() and ALLOWLIST_TOKENS=("category:token" ...)
#     from <data-root>/profiles/<active>.allowlist.yaml (if present) merged with
#     <data-root>/allowlist.yaml (global, if present). Emits `guard-allowlist-malformed`
#     to stderr and returns 3 on YAML parse failure.
#   allowlist_contains <category> <token>
#     Returns 0 iff the (category, token) is present. For category='path', matches
#     if any entry in ALLOWLIST_PATHS is a prefix of the token (via path_is_under).
#     For other categories, exact string match against "category:token" entries.
#
# Usage: source path-match.sh FIRST, then this file, then call allowlist_load.
#
# No `set -euo pipefail` here — this is a sourceable library.

ALLOWLIST_PATHS=()
ALLOWLIST_TOKENS=()

_allowlist_merge_file() {
    local f="$1"
    local py_out py_exit_code category token path_val

    py_out="$(python3 - "$f" 2>&1 <<'PY'
import sys, yaml
try:
    with open(sys.argv[1]) as fh:
        data = yaml.safe_load(fh) or {}
except Exception as e:
    print(str(e).splitlines()[0], file=sys.stderr)
    sys.exit(2)
if not isinstance(data, dict):
    print("top-level YAML value is not a mapping", file=sys.stderr)
    sys.exit(2)
paths = data.get("paths") or []
if not isinstance(paths, list):
    print("'paths' key is not a list", file=sys.stderr)
    sys.exit(2)
for p in paths:
    if isinstance(p, str):
        print(f"P\t{p}")
tokens = data.get("tokens") or {}
if isinstance(tokens, dict):
    for cat, vals in tokens.items():
        if not isinstance(vals, list):
            continue
        for v in vals:
            if isinstance(v, str):
                print(f"T\t{cat}\t{v}")
elif isinstance(tokens, list):
    for entry in tokens:
        if isinstance(entry, dict) and "category" in entry and "token" in entry:
            print(f"T\t{entry['category']}\t{entry['token']}")
PY
    )"
    py_exit_code=$?

    if [ "$py_exit_code" -ne 0 ]; then
        local parse_err
        parse_err="$(printf '%s' "$py_out" | head -n1)"
        printf "yci guard: allowlist YAML at '%s' is malformed.\n" "$f" >&2
        printf '  %s\n' "$parse_err" >&2
        printf "Reproduce the error with: python3 -c \"import yaml; yaml.safe_load(open('%s'))\"\n" "$f" >&2
        return 3
    fi

    while IFS=$'\t' read -r kind rest; do
        case "$kind" in
            P)
                path_val="$rest"
                ALLOWLIST_PATHS+=("$path_val")
                ;;
            T)
                category="${rest%%$'\t'*}"
                token="${rest#*$'\t'}"
                ALLOWLIST_TOKENS+=("${category}:${token}")
                ;;
        esac
    done <<< "$py_out"

    return 0
}

allowlist_load() {
    local data_root active_customer
    data_root="$1"; active_customer="$2"
    ALLOWLIST_PATHS=()
    ALLOWLIST_TOKENS=()

    local per_tenant="${data_root}/profiles/${active_customer}.allowlist.yaml"
    local global="${data_root}/allowlist.yaml"

    for f in "$per_tenant" "$global"; do
        [ -f "$f" ] || continue
        if ! _allowlist_merge_file "$f"; then
            return 3
        fi
    done
    return 0
}

allowlist_contains() {
    local category token entry
    category="$1"; token="$2"
    if [ "$category" = "path" ]; then
        for entry in "${ALLOWLIST_PATHS[@]+"${ALLOWLIST_PATHS[@]}"}"; do
            if path_is_under "$token" "$entry"; then
                return 0
            fi
        done
        return 1
    fi
    # Exact "category:token" match for non-path categories
    for entry in "${ALLOWLIST_TOKENS[@]+"${ALLOWLIST_TOKENS[@]}"}"; do
        [ "$entry" = "${category}:${token}" ] && return 0
    done
    return 1
}
