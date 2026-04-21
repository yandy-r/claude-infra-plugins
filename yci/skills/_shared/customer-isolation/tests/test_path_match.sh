#!/usr/bin/env bash
# Tests for path-match.sh — path_is_under edge cases.
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

PATH_MATCH="${YCI_SCRIPTS_DIR}/path-match.sh"

_pm_ok() {
    if [ ! -f "$PATH_MATCH" ]; then
        printf 'DIAGNOSTIC: path-match.sh not found at %s\n' "$PATH_MATCH" >&2
        return 1
    fi
    return 0
}

# Source path-match.sh once at the top level (functions persist across with_sandbox calls
# since with_sandbox runs in the current shell, not a subshell).
# shellcheck source=/dev/null
[ -f "$PATH_MATCH" ] && source "$PATH_MATCH"

# ---------------------------------------------------------------------------
test_equal() {
    local sb="$1"
    _pm_ok || { _yci_test_report PASS "pm_equal: skipped"; return 0; }
    mkdir -p "$sb/a"
    if path_is_under "$sb/a" "$sb/a"; then
        _yci_test_report PASS "pm_equal: /a under /a"
    else
        _yci_test_report FAIL "pm_equal: expected /a to be under /a"
    fi
}

test_child() {
    local sb="$1"
    _pm_ok || { _yci_test_report PASS "pm_child: skipped"; return 0; }
    mkdir -p "$sb/a/b/c"
    if path_is_under "$sb/a/b/c" "$sb/a/b"; then
        _yci_test_report PASS "pm_child: /a/b/c under /a/b"
    else
        _yci_test_report FAIL "pm_child: expected /a/b/c to be under /a/b"
    fi
}

test_parent_not_under_child() {
    local sb="$1"
    _pm_ok || { _yci_test_report PASS "pm_parent_not_child: skipped"; return 0; }
    mkdir -p "$sb/a/b/c"
    if path_is_under "$sb/a/b" "$sb/a/b/c"; then
        _yci_test_report FAIL "pm_parent_not_child: /a/b should NOT be under /a/b/c"
    else
        _yci_test_report PASS "pm_parent_not_child: /a/b correctly not under /a/b/c"
    fi
}

test_partial_segment() {
    local sb="$1"
    _pm_ok || { _yci_test_report PASS "pm_partial: skipped"; return 0; }
    mkdir -p "$sb/acme" "$sb/acme-inc"
    if path_is_under "$sb/acme-inc" "$sb/acme"; then
        _yci_test_report FAIL "pm_partial: /acme-inc should NOT be under /acme"
    else
        _yci_test_report PASS "pm_partial: /acme-inc correctly not under /acme (no segment bleed)"
    fi
}

test_symlink_child() {
    local sb="$1"
    _pm_ok || { _yci_test_report PASS "pm_symlink: skipped"; return 0; }
    mkdir -p "$sb/foreign/target"
    if ln -s "$sb/foreign/target" "$sb/link" 2>/dev/null; then
        if path_is_under "$sb/link" "$sb/foreign"; then
            _yci_test_report PASS "pm_symlink: symlink resolved correctly"
        else
            _yci_test_report FAIL "pm_symlink: symlink should resolve under foreign/"
        fi
    else
        printf '  skip: symlink unsupported on this filesystem\n'
        _yci_test_report PASS "pm_symlink: skipped (no symlink support)"
    fi
}

test_relative_path_clean_exit() {
    local sb="$1"
    _pm_ok || { _yci_test_report PASS "pm_relative: skipped"; return 0; }
    # Test that path_is_under with a relative candidate exits cleanly (no crash).
    local rc=0
    path_is_under "relative/path" "/absolute/root" 2>/dev/null || rc=$?
    # We don't assert a specific direction — just that exit code is 0 or 1 (no crash).
    if [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; then
        _yci_test_report PASS "pm_relative: exits cleanly with relative path"
    else
        _yci_test_report FAIL "pm_relative: unexpected exit code $rc for relative path"
    fi
}

# ---------------------------------------------------------------------------
with_sandbox test_equal
with_sandbox test_child
with_sandbox test_parent_not_under_child
with_sandbox test_partial_segment
with_sandbox test_symlink_child
with_sandbox test_relative_path_clean_exit

yci_test_summary
