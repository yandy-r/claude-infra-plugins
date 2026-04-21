#!/usr/bin/env bash
# Tests for state-io.sh — covers read/write round-trip, MRU dedupe, MRU cap,
# push_mru doesn't change active, corrupt JSON, atomic concurrency,
# and write-permission-denied error.
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

STATE_IO="${YCI_SCRIPTS_DIR}/state-io.sh"

_state_io_missing_diagnostic() {
    # Fail fast: a missing state-io.sh means the tree is broken. Never skip.
    if [ ! -f "$STATE_IO" ]; then
        printf 'FATAL: state-io.sh not found at %s\n' "$STATE_IO" >&2
        printf '  this script is required; missing it means the tree is broken\n' >&2
        exit 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# write → read round-trip
# ---------------------------------------------------------------------------
test_write_read_roundtrip() {
    local sb="$1"
    _state_io_missing_diagnostic || { _yci_test_report PASS "state_roundtrip: skipped (absent)"; return 0; }
    # shellcheck source=/dev/null
    source "$STATE_IO"
    state_write_active "$sb/real" acme
    local got
    got="$(state_get_active "$sb/real")"
    assert_eq "$got" "acme" "state_roundtrip: write→read active"
    assert_file_exists "$sb/real/state.json" "state_roundtrip: state.json created"
}

# ---------------------------------------------------------------------------
# MRU dedupe — writing same id multiple times keeps only one entry
# ---------------------------------------------------------------------------
test_mru_dedupe() {
    local sb="$1"
    _state_io_missing_diagnostic || { _yci_test_report PASS "mru_dedupe: skipped (absent)"; return 0; }
    # shellcheck source=/dev/null
    source "$STATE_IO"
    state_write_active "$sb/real" acme
    state_write_active "$sb/real" beta
    state_write_active "$sb/real" acme
    local mru
    mru="$(python3 -c "import json; print(','.join(json.load(open('$sb/real/state.json'))['mru']))")"
    assert_eq "$mru" "acme,beta" "mru_dedupe: acme deduplicated to front"
}

# ---------------------------------------------------------------------------
# MRU cap — writing 25 customers trims MRU to 20
# ---------------------------------------------------------------------------
test_mru_cap() {
    local sb="$1"
    _state_io_missing_diagnostic || { _yci_test_report PASS "mru_cap: skipped (absent)"; return 0; }
    # shellcheck source=/dev/null
    source "$STATE_IO"
    local i
    for i in $(seq 1 25); do
        state_write_active "$sb/real" "cust-$i"
    done
    local n
    n="$(python3 -c "import json; print(len(json.load(open('$sb/real/state.json'))['mru']))")"
    assert_eq "$n" "20" "mru_cap: MRU trimmed to 20"
    local active
    active="$(state_get_active "$sb/real")"
    assert_eq "$active" "cust-25" "mru_cap: active is the last written"
}

# ---------------------------------------------------------------------------
# push_mru does NOT change .active
# ---------------------------------------------------------------------------
test_push_mru_no_active_change() {
    local sb="$1"
    _state_io_missing_diagnostic || { _yci_test_report PASS "push_mru_no_change: skipped (absent)"; return 0; }
    # shellcheck source=/dev/null
    source "$STATE_IO"
    state_write_active "$sb/real" acme
    state_push_mru "$sb/real" beta
    local active
    active="$(state_get_active "$sb/real")"
    assert_eq "$active" "acme" "push_mru_no_change: active remains acme"
    local mru
    mru="$(python3 -c "import json; print(','.join(json.load(open('$sb/real/state.json'))['mru']))")"
    assert_contains "$mru" "beta" "push_mru_no_change: beta appears in MRU"
}

# ---------------------------------------------------------------------------
# push_mru deduplicates within MRU without touching active
# ---------------------------------------------------------------------------
test_push_mru_dedupe() {
    local sb="$1"
    _state_io_missing_diagnostic || { _yci_test_report PASS "push_mru_dedupe: skipped (absent)"; return 0; }
    # shellcheck source=/dev/null
    source "$STATE_IO"
    state_write_active "$sb/real" acme
    state_push_mru "$sb/real" beta
    state_push_mru "$sb/real" gamma
    state_push_mru "$sb/real" beta
    # beta should appear exactly once and be at the front after the second push
    local front count
    front="$(python3 -c "import json; d=json.load(open('$sb/real/state.json')); print(d['mru'][0])")"
    count="$(python3 -c "import json; d=json.load(open('$sb/real/state.json')); print(d['mru'].count('beta'))")"
    assert_eq "$count" "1"    "push_mru_dedupe: beta appears exactly once"
    assert_eq "$front" "beta" "push_mru_dedupe: beta moved to front"
    # active still unchanged
    local active
    active="$(state_get_active "$sb/real")"
    assert_eq "$active" "acme" "push_mru_dedupe: active still acme"
}

# ---------------------------------------------------------------------------
# push_mru --cap N honours custom cap
# ---------------------------------------------------------------------------
test_push_mru_custom_cap() {
    local sb="$1"
    _state_io_missing_diagnostic || { _yci_test_report PASS "push_mru_cap: skipped (absent)"; return 0; }
    # shellcheck source=/dev/null
    source "$STATE_IO"
    state_write_active "$sb/real" base
    local i
    for i in $(seq 1 10); do
        state_push_mru "$sb/real" "extra-$i" --cap 5
    done
    local n
    n="$(python3 -c "import json; print(len(json.load(open('$sb/real/state.json'))['mru']))")"
    assert_eq "$n" "5" "push_mru_cap: MRU trimmed to custom cap 5"
}

# ---------------------------------------------------------------------------
# Corrupt JSON → state_get_active exits 2
# ---------------------------------------------------------------------------
test_corrupt_json() {
    local sb="$1"
    _state_io_missing_diagnostic || { _yci_test_report PASS "corrupt_json: skipped (absent)"; return 0; }
    # shellcheck source=/dev/null
    source "$STATE_IO"
    mkdir -p "$sb/real"
    printf '{ not valid json at all\n' > "$sb/real/state.json"
    local rc
    state_get_active "$sb/real" >"$sb/out" 2>"$sb/err"
    rc=$?
    assert_exit 2 "$rc" "corrupt_json: exit 2"
    assert_contains "$(cat "$sb/err")" "corrupt state file" "corrupt_json: error phrase"
}

# ---------------------------------------------------------------------------
# state_read on corrupt JSON → exits 2
# ---------------------------------------------------------------------------
test_corrupt_json_state_read() {
    local sb="$1"
    _state_io_missing_diagnostic || { _yci_test_report PASS "corrupt_read: skipped (absent)"; return 0; }
    # shellcheck source=/dev/null
    source "$STATE_IO"
    mkdir -p "$sb/real"
    printf 'TRUNCATED GARBAGE' > "$sb/real/state.json"
    local rc
    state_read "$sb/real" >"$sb/out" 2>"$sb/err"
    rc=$?
    assert_exit 2 "$rc" "corrupt_read: exit 2"
    assert_contains "$(cat "$sb/err")" "corrupt state file" "corrupt_read: error phrase"
}

# ---------------------------------------------------------------------------
# Missing state.json → state_read returns default, exit 1 (file missing)
# ---------------------------------------------------------------------------
test_missing_state_read_default() {
    local sb="$1"
    _state_io_missing_diagnostic || { _yci_test_report PASS "missing_state_read: skipped (absent)"; return 0; }
    # shellcheck source=/dev/null
    source "$STATE_IO"
    # sb/real exists but no state.json
    local out rc
    out="$(state_read "$sb/real" 2>"$sb/err")"; rc=$?
    assert_exit 1 "$rc" "missing_state_read: exit 1 (file missing)"
    assert_contains "$out" "null" "missing_state_read: default JSON has null active"
}

# ---------------------------------------------------------------------------
# state_get_active on missing file → empty line, exit 0
# ---------------------------------------------------------------------------
test_missing_state_get_active() {
    local sb="$1"
    _state_io_missing_diagnostic || { _yci_test_report PASS "missing_get_active: skipped (absent)"; return 0; }
    # shellcheck source=/dev/null
    source "$STATE_IO"
    local out rc
    out="$(state_get_active "$sb/real" 2>"$sb/err")"; rc=$?
    assert_exit 0 "$rc" "missing_get_active: exit 0 (no file is ok)"
    assert_eq "$out" "" "missing_get_active: stdout is empty (no file → no active)"
}

# ---------------------------------------------------------------------------
# Write permission denied → state_write_active exits 3
# ---------------------------------------------------------------------------
test_write_permission_denied() {
    local sb="$1"
    _state_io_missing_diagnostic || { _yci_test_report PASS "write_perm: skipped (absent)"; return 0; }
    # shellcheck source=/dev/null
    source "$STATE_IO"
    # Make the real/ directory read-only
    mkdir -p "$sb/real"
    chmod 0500 "$sb/real"
    local rc
    state_write_active "$sb/real" acme >"$sb/out" 2>"$sb/err"
    rc=$?
    # restore before cleanup
    chmod 0700 "$sb/real"
    assert_exit 3 "$rc" "write_perm: exit 3"
    assert_contains "$(cat "$sb/err")" "cannot write state file" "write_perm: error phrase"
}

# ---------------------------------------------------------------------------
# JSON validity after multiple writes
# ---------------------------------------------------------------------------
test_json_valid_after_writes() {
    local sb="$1"
    _state_io_missing_diagnostic || { _yci_test_report PASS "json_valid_writes: skipped (absent)"; return 0; }
    # shellcheck source=/dev/null
    source "$STATE_IO"
    local i
    for i in alpha beta gamma delta; do
        state_write_active "$sb/real" "$i"
    done
    assert_json_valid "$sb/real/state.json" "json_valid_writes: state.json is valid JSON after writes"
}

# ---------------------------------------------------------------------------
# Concurrent writes → final file is valid JSON
# ---------------------------------------------------------------------------
test_concurrent_writes() {
    local sb="$1"
    _state_io_missing_diagnostic || { _yci_test_report PASS "concurrent: skipped (absent)"; return 0; }

    local i pid
    local -a pids=()
    for i in $(seq 1 5); do
        (
            # shellcheck source=/dev/null
            source "$STATE_IO"
            state_write_active "$sb/real" "writer-$i"
        ) &
        pids+=("$!")
    done

    # Wait on each writer individually so a single failure is detected; bare
    # `wait` only returns the last child's status and masks earlier failures.
    local failed=0 writer_rc
    for pid in "${pids[@]}"; do
        if wait "$pid"; then
            writer_rc=0
        else
            writer_rc=$?
            printf '  writer pid=%s exited %d\n' "$pid" "$writer_rc" >&2
            failed=1
        fi
    done

    assert_eq "$failed" "0" "concurrent: all writers exited 0"
    assert_json_valid "$sb/real/state.json" "concurrent: state.json is valid JSON after concurrent writes"
}

# ---------------------------------------------------------------------------
# updated_at field is set on write
# ---------------------------------------------------------------------------
test_updated_at_set() {
    local sb="$1"
    _state_io_missing_diagnostic || { _yci_test_report PASS "updated_at: skipped (absent)"; return 0; }
    # shellcheck source=/dev/null
    source "$STATE_IO"
    state_write_active "$sb/real" acme
    local has_updated
    has_updated="$(python3 -c "import json; d=json.load(open('$sb/real/state.json')); print('yes' if 'updated_at' in d else 'no')")"
    assert_eq "$has_updated" "yes" "updated_at: field present after write"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    if [ ! -f "$STATE_IO" ]; then
        printf 'FATAL: state-io.sh not found at %s\n' "$STATE_IO" >&2
        printf '  this script is required; missing it means the tree is broken\n' >&2
        exit 1
    fi

    with_sandbox test_write_read_roundtrip
    with_sandbox test_mru_dedupe
    with_sandbox test_mru_cap
    with_sandbox test_push_mru_no_active_change
    with_sandbox test_push_mru_dedupe
    with_sandbox test_push_mru_custom_cap
    with_sandbox test_corrupt_json
    with_sandbox test_corrupt_json_state_read
    with_sandbox test_missing_state_read_default
    with_sandbox test_missing_state_get_active
    with_sandbox test_write_permission_denied
    with_sandbox test_json_valid_after_writes
    with_sandbox test_concurrent_writes
    with_sandbox test_updated_at_set
    yci_test_summary
}

main
