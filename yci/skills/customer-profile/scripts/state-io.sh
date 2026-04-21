#!/usr/bin/env bash
# yci — state.json I/O library (source this file; do not execute directly).
#
# Provides atomic read/write of <data-root>/state.json. Uses python3 for JSON
# parsing/serialization to avoid jq dependency.
#
# Public functions:
#   state_read            <data-root>
#   state_get_active      <data-root>
#   state_write_active    <data-root> <customer-id>
#   state_push_mru        <data-root> <customer-id> [--cap N]

# Do NOT set -euo pipefail at file scope — that breaks sourcing scripts that
# don't expect strict mode. Callers enable strict mode themselves.

# Guard the readonly decl so repeated sourcing (tests, nested callers) doesn't
# trip "YCI_STATE_MRU_DEFAULT_CAP: readonly variable" on the second source.
if [ -z "${YCI_STATE_MRU_DEFAULT_CAP:-}" ]; then
    readonly YCI_STATE_MRU_DEFAULT_CAP=20
fi

_yci_state_path() {
    printf '%s' "$1/state.json"
}

_yci_state_iso_now() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

_yci_state_ensure_dir() {
    local data_root="$1"
    if [ ! -d "$data_root" ]; then
        printf 'yci: data root directory missing: %s\n' "$data_root" >&2
        return 3
    fi
    if [ ! -w "$data_root" ]; then
        local path; path="$(_yci_state_path "$data_root")"
        printf 'yci: cannot write state file: %s\n  permission denied — check directory ownership and mode (expected 0700)\n' "$path" >&2
        return 3
    fi
    return 0
}

# state_read <data-root>
# Prints the full state.json to stdout as JSON. Exits 0 if present & valid,
# returns 1 if missing (prints empty {"active":null,"mru":[]}), exits 2 on corrupt JSON.
state_read() {
    local data_root="${1:?state_read requires <data-root>}"
    local path; path="$(_yci_state_path "$data_root")"
    if [ ! -f "$path" ]; then
        printf '%s\n' '{"active":null,"mru":[]}'
        return 1
    fi
    python3 - "$path" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except Exception as e:
    sys.stderr.write(f"yci: corrupt state file: {path}\n  state.json failed JSON parse — delete or repair the file to continue\n")
    sys.exit(2)
if not isinstance(data, dict):
    sys.stderr.write(f"yci: corrupt state file: {path}\n  state.json failed JSON parse — delete or repair the file to continue\n")
    sys.exit(2)
data.setdefault("active", None)
data.setdefault("mru", [])
if not isinstance(data["mru"], list):
    data["mru"] = []
print(json.dumps(data))
PY
}

# state_get_active <data-root>
# Prints .active value to stdout (empty line if absent). Exit 0 if file missing (treats as "no active"),
# exit 2 if file is corrupt JSON.
state_get_active() {
    local data_root="${1:?state_get_active requires <data-root>}"
    local path; path="$(_yci_state_path "$data_root")"
    if [ ! -f "$path" ]; then
        printf '\n'
        return 0
    fi
    python3 - "$path" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except Exception as e:
    sys.stderr.write(f"yci: corrupt state file: {path}\n  state.json failed JSON parse — delete or repair the file to continue\n")
    sys.exit(2)
active = data.get("active") if isinstance(data, dict) else None
print(active if isinstance(active, str) else "")
PY
}

_yci_state_write_atomic() {
    # _yci_state_write_atomic <data-root> <json-body>
    local data_root="$1" body="$2"
    _yci_state_ensure_dir "$data_root" || return 3
    local path; path="$(_yci_state_path "$data_root")"
    local tmp
    tmp="$(mktemp "${data_root}/.state.json.XXXXXX")" || {
        printf 'yci: cannot write state file: %s\n  permission denied — check directory ownership and mode (expected 0700)\n' "$path" >&2
        return 3
    }
    # ensure cleanup on interrupt
    # shellcheck disable=SC2064
    trap "rm -f '$tmp'" EXIT INT TERM
    if ! printf '%s\n' "$body" > "$tmp"; then
        rm -f "$tmp"
        trap - EXIT INT TERM
        printf 'yci: cannot write state file: %s\n  permission denied — check directory ownership and mode (expected 0700)\n' "$path" >&2
        return 3
    fi
    chmod 0600 "$tmp" 2>/dev/null || true
    if ! mv -f "$tmp" "$path"; then
        rm -f "$tmp"
        trap - EXIT INT TERM
        printf 'yci: cannot write state file: %s\n  permission denied — check directory ownership and mode (expected 0700)\n' "$path" >&2
        return 3
    fi
    trap - EXIT INT TERM
    return 0
}

# state_write_active <data-root> <customer-id>
# Sets .active=<customer-id> and pushes to MRU (dedupe + cap 20). Writes atomically.
# Updates .updated_at to current ISO-8601 UTC. Exit 3 on permission-denied.
state_write_active() {
    local data_root="${1:?state_write_active requires <data-root>}"
    local customer_id="${2:?state_write_active requires <customer-id>}"
    local cap="${YCI_STATE_MRU_CAP:-$YCI_STATE_MRU_DEFAULT_CAP}"
    local now; now="$(_yci_state_iso_now)"
    local current; current="$(state_read "$data_root" 2>/dev/null)" || current='{"active":null,"mru":[]}'
    local body
    # Pass current JSON as argv[4] to avoid stdin conflict with the heredoc.
    body="$(python3 - "$customer_id" "$now" "$cap" "$current" <<'PY'
import json, sys
customer, now, cap, current_json = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
try:
    data = json.loads(current_json)
except Exception:
    data = {"active": None, "mru": []}
mru = [m for m in data.get("mru", []) if isinstance(m, str) and m != customer]
mru.insert(0, customer)
mru = mru[:cap]
out = {"active": customer, "mru": mru, "updated_at": now}
print(json.dumps(out, indent=2, sort_keys=True))
PY
)"
    _yci_state_write_atomic "$data_root" "$body"
}

# state_push_mru <data-root> <customer-id> [--cap N]
# Pushes <customer-id> to front of .mru (dedupe, cap N; default 20). Does NOT change .active.
# Atomic write. Exit 3 on permission-denied.
state_push_mru() {
    local data_root="${1:?state_push_mru requires <data-root>}"
    local customer_id="${2:?state_push_mru requires <customer-id>}"
    shift 2
    local cap="$YCI_STATE_MRU_DEFAULT_CAP"
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --cap) cap="${2:-$YCI_STATE_MRU_DEFAULT_CAP}"; shift 2 ;;
            --cap=*) cap="${1#*=}"; shift ;;
            *)
                printf "yci: state_push_mru: unknown argument: '%s'\n" "$1" >&2
                return 1
                ;;
        esac
    done
    local now; now="$(_yci_state_iso_now)"
    local current; current="$(state_read "$data_root" 2>/dev/null)" || current='{"active":null,"mru":[]}'
    local body
    # Pass current JSON as argv[4] to avoid stdin conflict with the heredoc.
    body="$(python3 - "$customer_id" "$now" "$cap" "$current" <<'PY'
import json, sys
customer, now, cap, current_json = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
try:
    data = json.loads(current_json)
except Exception:
    data = {"active": None, "mru": []}
mru = [m for m in data.get("mru", []) if isinstance(m, str) and m != customer]
mru.insert(0, customer)
mru = mru[:cap]
out = dict(data)
out["mru"] = mru
out["updated_at"] = now
print(json.dumps(out, indent=2, sort_keys=True))
PY
)"
    _yci_state_write_atomic "$data_root" "$body"
}
