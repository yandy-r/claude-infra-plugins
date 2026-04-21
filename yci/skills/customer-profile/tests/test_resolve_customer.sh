#!/usr/bin/env bash
# Tests for resolve-customer.sh — covers every row of precedence.md test-case matrix.
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

RESOLVER="${YCI_SCRIPTS_DIR}/resolve-customer.sh"

_run_resolver() {
    # _run_resolver <data_root> [extra args...]
    # Captures stdout; stderr goes to $YCI_TEST_SANDBOX/stderr (caller must set sandbox).
    local data_root="$1"; shift
    if [ ! -f "$RESOLVER" ]; then
        printf 'SKIP: resolver not found at %s\n' "$RESOLVER" >&2
        return 127
    fi
    "$RESOLVER" --data-root "$data_root" "$@" 2>"${YCI_TEST_SANDBOX}/stderr"
}

# ---------------------------------------------------------------------------
# Row 1: env wins — $YCI_CUSTOMER=acme, dotfile=beta, state.active=gamma → acme
# ---------------------------------------------------------------------------
test_env_wins() {
    local sb="$1"
    echo beta > "$sb/cwd/.yci-customer"
    echo '{"active":"gamma"}' > "$sb/real/state.json"
    local out rc
    export YCI_CUSTOMER=acme
    out="$(_run_resolver "$sb/real")"; rc=$?
    assert_exit 0 "$rc" "env_wins: exit 0"
    assert_eq "$out" "acme" "env_wins: output is acme"
}

# ---------------------------------------------------------------------------
# Row 2: dotfile at cwd — env empty, dotfile=beta at cwd, state.active=gamma → beta
# ---------------------------------------------------------------------------
test_dotfile_at_cwd() {
    local sb="$1"
    echo beta > "$sb/cwd/.yci-customer"
    echo '{"active":"gamma"}' > "$sb/real/state.json"
    local out rc
    out="$(_run_resolver "$sb/real")"; rc=$?
    assert_exit 0 "$rc" "dotfile_cwd: exit 0"
    assert_eq "$out" "beta" "dotfile_cwd: output is beta"
}

# ---------------------------------------------------------------------------
# Row 3: dotfile at ancestor — env empty, no cwd dotfile, ancestor=beta, state=gamma → beta
# ---------------------------------------------------------------------------
test_dotfile_ancestor() {
    local sb="$1"
    echo beta > "$sb/cwd/.yci-customer"
    mkdir -p "$sb/cwd/nested/deep"
    # Move to deep subdirectory; dotfile is two levels above (within home subtree)
    local out rc
    out="$(cd "$sb/cwd/nested/deep" && "$RESOLVER" --data-root "$sb/real" 2>"${sb}/stderr")"; rc=$?
    assert_exit 0 "$rc" "dotfile_ancestor: exit 0"
    assert_eq "$out" "beta" "dotfile_ancestor: output is beta"
}

# ---------------------------------------------------------------------------
# Row 4: mru only — env empty, no dotfile, state.active=gamma → gamma
# ---------------------------------------------------------------------------
test_mru_only() {
    local sb="$1"
    echo '{"active":"gamma","mru":["gamma"]}' > "$sb/real/state.json"
    local out rc
    out="$(_run_resolver "$sb/real")"; rc=$?
    assert_exit 0 "$rc" "mru_only: exit 0"
    assert_eq "$out" "gamma" "mru_only: output is gamma"
}

# ---------------------------------------------------------------------------
# Row 5: all empty — env unset, no dotfile, no state.json → refuse (exit 1)
# ---------------------------------------------------------------------------
test_refuse_all_empty() {
    local sb="$1"
    local out rc
    out="$(_run_resolver "$sb/real" 2>"$sb/err")"; rc=$?
    # Redirect stderr through the sandbox file
    "$RESOLVER" --data-root "$sb/real" >"$sb/out" 2>"$sb/err"
    rc=$?
    assert_exit 1 "$rc" "refuse_all: exit 1"
    assert_contains "$(cat "$sb/err")" "no active customer" "refuse_all: refusal phrase"
}

# ---------------------------------------------------------------------------
# Row 6: walk stops at $HOME — dotfile exists only ABOVE $HOME → refuse (exit 1)
# ---------------------------------------------------------------------------
test_walkup_stops_at_home() {
    local sb="$1"
    # Put dotfile above HOME (in sb root, not in sb/home subtree)
    echo outsider > "$sb/.yci-customer"
    export HOME="$sb/home"
    mkdir -p "$sb/home/project"
    local rc
    "$RESOLVER" --data-root "$sb/real" >"$sb/out" 2>"$sb/err"
    rc=$?
    (cd "$sb/home/project" && "$RESOLVER" --data-root "$sb/real" >"$sb/out2" 2>"$sb/err2")
    rc=$?
    assert_exit 1 "$rc" "walkup_home: refused (did not ascend past HOME)"
    assert_contains "$(cat "$sb/err2")" "no active customer" "walkup_home: refusal message"
}

# ---------------------------------------------------------------------------
# Row 7: empty env is ignored — YCI_CUSTOMER="" dotfile=beta → beta
# ---------------------------------------------------------------------------
test_empty_env_ignored() {
    local sb="$1"
    echo beta > "$sb/cwd/.yci-customer"
    local out rc
    out="$(_run_resolver "$sb/real")"; rc=$?
    assert_exit 0 "$rc" "empty_env: exit 0"
    assert_eq "$out" "beta" "empty_env: falls through to dotfile"
}

# ---------------------------------------------------------------------------
# Row 8: whitespace-only dotfile at cwd, valid ancestor dotfile=beta → beta
# ---------------------------------------------------------------------------
test_whitespace_dotfile_fallthrough() {
    local sb="$1"
    # Walk from $sb/cwd/sub: first visit $sb/cwd/sub/.yci-customer (whitespace
    # → skip), then $sb/cwd/.yci-customer (valid → beta wins).
    mkdir -p "$sb/cwd/sub"
    printf '   \n   \n' > "$sb/cwd/sub/.yci-customer"
    echo beta > "$sb/cwd/.yci-customer"
    export HOME="$sb/home"
    local out rc
    out="$(cd "$sb/cwd/sub" && "$RESOLVER" --data-root "$sb/real" 2>"${sb}/stderr")"; rc=$?
    assert_exit 0 "$rc" "whitespace_dotfile: falls through to ancestor"
    assert_eq "$out" "beta" "whitespace_dotfile: ancestor value beta"
}

# ---------------------------------------------------------------------------
# Row 9: comment-only dotfile at cwd, ancestor dotfile=beta → beta
# ---------------------------------------------------------------------------
test_comment_dotfile_fallthrough() {
    local sb="$1"
    mkdir -p "$sb/cwd/sub"
    printf '# comment only\n# another comment\n' > "$sb/cwd/sub/.yci-customer"
    echo beta > "$sb/cwd/.yci-customer"
    export HOME="$sb/home"
    local out rc
    out="$(cd "$sb/cwd/sub" && "$RESOLVER" --data-root "$sb/real" 2>"${sb}/stderr")"; rc=$?
    assert_exit 0 "$rc" "comment_dotfile: falls through to ancestor"
    assert_eq "$out" "beta" "comment_dotfile: ancestor value beta"
}

# ---------------------------------------------------------------------------
# Row 10: invalid id format — YCI_CUSTOMER=ACME (uppercase) → exit 1
# ---------------------------------------------------------------------------
test_env_invalid_id_format() {
    local sb="$1"
    local rc
    YCI_CUSTOMER="ACME" "$RESOLVER" --data-root "$sb/real" >"$sb/out" 2>"$sb/err"
    rc=$?
    assert_exit 1 "$rc" "env_invalid: exit 1"
    assert_contains "$(cat "$sb/err")" "invalid customer id" "env_invalid: error phrase"
}

# ---------------------------------------------------------------------------
# Row 11: missing state.json — no env, no dotfile, no state.json → refuse (exit 1)
# ---------------------------------------------------------------------------
test_missing_state_json() {
    local sb="$1"
    # sb/real exists but no state.json inside
    local rc
    YCI_CUSTOMER="" "$RESOLVER" --data-root "$sb/real" >"$sb/out" 2>"$sb/err"
    rc=$?
    assert_exit 1 "$rc" "missing_state: exit 1"
    assert_contains "$(cat "$sb/err")" "no active customer" "missing_state: refusal phrase"
}

# ---------------------------------------------------------------------------
# Row 12: state.json with no .active field ({}) → refuse (exit 1)
# ---------------------------------------------------------------------------
test_state_json_no_active_field() {
    local sb="$1"
    echo '{}' > "$sb/real/state.json"
    local rc
    YCI_CUSTOMER="" "$RESOLVER" --data-root "$sb/real" >"$sb/out" 2>"$sb/err"
    rc=$?
    assert_exit 1 "$rc" "state_no_active: exit 1"
    assert_contains "$(cat "$sb/err")" "no active customer" "state_no_active: refusal phrase"
}

# ---------------------------------------------------------------------------
# Row 13: state.json .active=null → refuse (exit 1)
# ---------------------------------------------------------------------------
test_state_json_active_null() {
    local sb="$1"
    echo '{"active":null}' > "$sb/real/state.json"
    local rc
    YCI_CUSTOMER="" "$RESOLVER" --data-root "$sb/real" >"$sb/out" 2>"$sb/err"
    rc=$?
    assert_exit 1 "$rc" "state_null: exit 1"
    assert_contains "$(cat "$sb/err")" "no active customer" "state_null: refusal phrase"
}

# ---------------------------------------------------------------------------
# Row 14: whitespace-only env — YCI_CUSTOMER="   " dotfile=beta → beta
# ---------------------------------------------------------------------------
test_whitespace_only_env() {
    local sb="$1"
    echo beta > "$sb/cwd/.yci-customer"
    local out rc
    export YCI_CUSTOMER="   "
    out="$(_run_resolver "$sb/real")"; rc=$?
    assert_exit 0 "$rc" "whitespace_env: exit 0"
    assert_eq "$out" "beta" "whitespace_env: falls through to dotfile beta"
}

# ---------------------------------------------------------------------------
# Row 15: multi-line dotfile — first non-comment line wins
# ---------------------------------------------------------------------------
test_multiline_dotfile_first_wins() {
    local sb="$1"
    printf '# comment\nreal-id\nother-id\n' > "$sb/cwd/.yci-customer"
    local out rc
    # YCI_CUSTOMER is already exported empty by with_sandbox; no prefix needed.
    out="$(_run_resolver "$sb/real")"; rc=$?
    assert_exit 0 "$rc" "multiline_dotfile: exit 0"
    assert_eq "$out" "real-id" "multiline_dotfile: first non-comment line wins"
}

# ---------------------------------------------------------------------------
# Extra: whitespace-only env shows hint in stderr
# ---------------------------------------------------------------------------
test_whitespace_env_shows_empty_hint() {
    local sb="$1"
    # No dotfile, no state — so we see the full refusal with hint
    local rc
    YCI_CUSTOMER="   " "$RESOLVER" --data-root "$sb/real" >"$sb/out" 2>"$sb/err"
    rc=$?
    assert_exit 1 "$rc" "ws_env_hint: exit 1"
    assert_contains "$(cat "$sb/err")" "whitespace-only" "ws_env_hint: hint in stderr"
}

# ---------------------------------------------------------------------------
# Extra: invalid id in dotfile → exit 1 with format error
# ---------------------------------------------------------------------------
test_dotfile_invalid_id_format() {
    local sb="$1"
    echo "UPPERCASE_BAD" > "$sb/cwd/.yci-customer"
    local rc
    YCI_CUSTOMER="" "$RESOLVER" --data-root "$sb/real" >"$sb/out" 2>"$sb/err"
    rc=$?
    assert_exit 1 "$rc" "dotfile_invalid: exit 1"
    assert_contains "$(cat "$sb/err")" "invalid customer id" "dotfile_invalid: format error phrase"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    if [ ! -f "$RESOLVER" ]; then
        printf 'DIAGNOSTIC: resolver not found at %s — tests will be skipped at runtime\n' "$RESOLVER" >&2
        printf '  (expected after B5.1 merges)\n' >&2
    fi

    with_sandbox test_env_wins
    with_sandbox test_dotfile_at_cwd
    with_sandbox test_dotfile_ancestor
    with_sandbox test_mru_only
    with_sandbox test_refuse_all_empty
    with_sandbox test_walkup_stops_at_home
    with_sandbox test_empty_env_ignored
    with_sandbox test_whitespace_dotfile_fallthrough
    with_sandbox test_comment_dotfile_fallthrough
    with_sandbox test_env_invalid_id_format
    with_sandbox test_missing_state_json
    with_sandbox test_state_json_no_active_field
    with_sandbox test_state_json_active_null
    with_sandbox test_whitespace_only_env
    with_sandbox test_multiline_dotfile_first_wins
    with_sandbox test_whitespace_env_shows_empty_hint
    with_sandbox test_dotfile_invalid_id_format
    yci_test_summary
}

main
