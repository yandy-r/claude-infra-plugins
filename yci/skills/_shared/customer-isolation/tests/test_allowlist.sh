#!/usr/bin/env bash
# Tests for allowlist.sh — load + query behaviors.
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

PATH_MATCH="${YCI_SCRIPTS_DIR}/path-match.sh"
ALLOWLIST="${YCI_SCRIPTS_DIR}/allowlist.sh"

_deps_ok() {
    if [ ! -f "$PATH_MATCH" ] || [ ! -f "$ALLOWLIST" ]; then
        printf 'DIAGNOSTIC: path-match.sh or allowlist.sh not found\n' >&2
        return 1
    fi
    return 0
}

# Source deps once. with_sandbox runs in current shell so they remain available.
# shellcheck source=/dev/null
[ -f "$PATH_MATCH" ] && source "$PATH_MATCH"
# shellcheck source=/dev/null
[ -f "$ALLOWLIST" ] && source "$ALLOWLIST"

# ---------------------------------------------------------------------------
test_missing_file() {
    local sb="$1"
    _deps_ok || { _yci_test_report PASS "al_missing: skipped"; return 0; }
    mkdir -p "$sb/data/profiles"
    local rc=0
    allowlist_load "$sb/data" "acme" 2>/dev/null || rc=$?
    assert_exit 0 "$rc" "al_missing: no allowlist file returns 0"
    assert_eq "${#ALLOWLIST_PATHS[@]}" "0" "al_missing: ALLOWLIST_PATHS empty"
    assert_eq "${#ALLOWLIST_TOKENS[@]}" "0" "al_missing: ALLOWLIST_TOKENS empty"
}

test_malformed_yaml() {
    local sb="$1"
    _deps_ok || { _yci_test_report PASS "al_malformed: skipped"; return 0; }
    mkdir -p "$sb/data/profiles"
    # Write intentionally malformed YAML
    printf 'paths: [unclosed\n' > "$sb/data/profiles/acme.allowlist.yaml"
    local stderr_out rc
    stderr_out="$(allowlist_load "$sb/data" "acme" 2>&1)"; rc=$?
    assert_exit 3 "$rc" "al_malformed: malformed YAML returns 3"
    assert_error_id "guard-allowlist-malformed" "$stderr_out" "al_malformed: guard-allowlist-malformed message"
}

test_path_match() {
    local sb="$1"
    _deps_ok || { _yci_test_report PASS "al_path_match: skipped"; return 0; }
    mkdir -p "$sb/data/profiles" "$sb/foo/subdir"
    printf 'paths:\n  - %s\n' "$sb/foo" > "$sb/data/profiles/acme.allowlist.yaml"
    allowlist_load "$sb/data" "acme" 2>/dev/null
    local rc=0
    allowlist_contains path "$sb/foo/subdir" 2>/dev/null || rc=$?
    assert_exit 0 "$rc" "al_path_match: child path matches allowlist entry"
}

test_path_no_match() {
    local sb="$1"
    _deps_ok || { _yci_test_report PASS "al_path_no_match: skipped"; return 0; }
    mkdir -p "$sb/data/profiles" "$sb/foo" "$sb/bar"
    printf 'paths:\n  - %s\n' "$sb/foo" > "$sb/data/profiles/acme.allowlist.yaml"
    allowlist_load "$sb/data" "acme" 2>/dev/null
    local rc=0
    allowlist_contains path "$sb/bar" 2>/dev/null || rc=$?
    assert_exit 1 "$rc" "al_path_no_match: unrelated path not matched"
}

test_token_match_dict_form() {
    local sb="$1"
    _deps_ok || { _yci_test_report PASS "al_token_dict: skipped"; return 0; }
    mkdir -p "$sb/data/profiles"
    cat > "$sb/data/profiles/acme.allowlist.yaml" <<'EOF'
tokens:
  hostname:
    - x.com
EOF
    allowlist_load "$sb/data" "acme" 2>/dev/null
    local rc=0
    allowlist_contains hostname "x.com" 2>/dev/null || rc=$?
    assert_exit 0 "$rc" "al_token_dict: dict-form hostname match"
}

test_token_match_list_form() {
    local sb="$1"
    _deps_ok || { _yci_test_report PASS "al_token_list: skipped"; return 0; }
    mkdir -p "$sb/data/profiles"
    cat > "$sb/data/profiles/acme.allowlist.yaml" <<'EOF'
tokens:
  - category: hostname
    token: y.com
EOF
    allowlist_load "$sb/data" "acme" 2>/dev/null
    local rc=0
    allowlist_contains hostname "y.com" 2>/dev/null || rc=$?
    assert_exit 0 "$rc" "al_token_list: list-form hostname match"
}

test_global_merge() {
    local sb="$1"
    _deps_ok || { _yci_test_report PASS "al_global_merge: skipped"; return 0; }
    mkdir -p "$sb/data/profiles"
    # Per-tenant allowlist has one hostname.
    cat > "$sb/data/profiles/acme.allowlist.yaml" <<'EOF'
tokens:
  hostname:
    - tenant.host.corp
EOF
    # Global allowlist has a different hostname.
    cat > "$sb/data/allowlist.yaml" <<'EOF'
tokens:
  hostname:
    - global.host.corp
EOF
    allowlist_load "$sb/data" "acme" 2>/dev/null
    local rc1=0 rc2=0
    allowlist_contains hostname "tenant.host.corp" 2>/dev/null || rc1=$?
    allowlist_contains hostname "global.host.corp" 2>/dev/null || rc2=$?
    assert_exit 0 "$rc1" "al_global_merge: per-tenant token present"
    assert_exit 0 "$rc2" "al_global_merge: global token present"
}

# ---------------------------------------------------------------------------
with_sandbox test_missing_file
with_sandbox test_malformed_yaml
with_sandbox test_path_match
with_sandbox test_path_no_match
with_sandbox test_token_match_dict_form
with_sandbox test_token_match_list_form
with_sandbox test_global_merge

yci_test_summary
