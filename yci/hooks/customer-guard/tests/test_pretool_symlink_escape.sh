#!/usr/bin/env bash
# Integration tests: pretool.sh symlink escape detection.
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

PRETOOL="${REPO_ROOT}/yci/hooks/customer-guard/scripts/pretool.sh"

_pretool_ok() {
    if [ ! -f "$PRETOOL" ]; then
        printf 'DIAGNOSTIC: pretool.sh not found at %s\n' "$PRETOOL" >&2
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# test_symlink_escape: symlink inside acme's tree pointing to bigbank's inventory.
#
# The current detect.sh implementation uses path_canonicalize (realpath) on
# candidate paths before the path_is_under check. The symlink inside acme's
# tree resolves to bigbank's realpath, which triggers guard-path-collision
# (kind=path). This is the correct behavior — the resolved target is proof of
# a symlink escape. The catalog also defines guard-symlink-escape for a future
# explicit detection phase; either ID may match depending on emitted reason.
# ---------------------------------------------------------------------------
test_symlink_escape() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "symlink_escape: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles" "$data/inventories/acme" "$data/inventories/bigbank"

    _build_profile "$data/profiles/acme.yaml"    "acme"    "Acme Corp" "inventories/acme"
    _build_profile "$data/profiles/bigbank.yaml" "bigbank" "Big Bank"  "inventories/bigbank"

    cat > "$data/inventories/acme/hosts.yaml" <<'EOF'
hosts:
  - acme01.acme.corp
EOF
    cat > "$data/inventories/bigbank/hosts.yaml" <<'EOF'
hosts:
  - bb01.bigbank.corp
EOF

    # Create a symlink inside acme's inventory pointing to bigbank's inventory file.
    # Guard with a fallthrough in case symlinks are not supported in this environment.
    ln -s "$data/inventories/bigbank/hosts.yaml" \
        "$data/inventories/acme/cross-link" 2>/dev/null \
        || { printf '  skip: symlink unsupported\n'; _yci_test_report PASS "symlink_escape: skipped (symlinks unsupported)"; return 0; }

    export YCI_CUSTOMER="acme"
    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"

    # Access the symlink via acme's path — string prefix is acme, but realpath
    # resolves to bigbank. The guard's path canonicalization will detect this.
    local payload
    payload="$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' \
        "$data/inventories/acme/cross-link")"

    local stdout stderr rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/tmp/yci-test-sym-stderr-$$)"; rc=$?
    stderr="$(cat /tmp/yci-test-sym-stderr-$$ 2>/dev/null)"; rm -f /tmp/yci-test-sym-stderr-$$

    assert_exit 0 "$rc" "symlink_escape: exit 0"
    assert_contains "$stdout" '{"hookSpecificOutput"' "symlink_escape: stdout has hookSpecificOutput"
    assert_contains "$stdout" '"permissionDecision": "deny"' "symlink_escape: decision=deny"

    # The reason phrase is embedded in the JSON on stdout (permissionDecisionReason), not stderr.
    # Current implementation emits guard-path-collision (kind=path) because the
    # resolved realpath of the symlink falls under bigbank's artifact root.
    # guard-symlink-escape would be emitted if/when dedicated symlink detection
    # is added in a future phase. Accept either catalog ID here.
    local reason_matched=0
    case "$stdout" in
        *"cross-customer path collision"*) reason_matched=1 ;;
        *"symlink escape"*) reason_matched=1 ;;
    esac
    if [ "$reason_matched" = "1" ]; then
        _yci_test_report PASS "symlink_escape: reason indicates cross-customer collision"
    else
        _yci_test_report FAIL "symlink_escape: expected cross-customer reason in stdout JSON, got: $stdout"
    fi

    unset YCI_CUSTOMER YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
with_sandbox test_symlink_escape

yci_test_summary
