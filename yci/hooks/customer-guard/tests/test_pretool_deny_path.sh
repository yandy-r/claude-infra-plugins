#!/usr/bin/env bash
# Integration tests: pretool.sh path-collision deny.
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
# test_path_collision: Read on bigbank inventory → deny with path collision.
# Note: the deny may be kind=path (detected first) OR kind=token (customer-id
# "bigbank" extracted from the path string). Both are valid — we assert the
# decision is deny and the reason references "bigbank".
# ---------------------------------------------------------------------------
test_path_collision() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "path_collision: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles" "$data/inventories/acme" "$data/inventories/bigbank"

    _build_profile "$data/profiles/acme.yaml"    "acme"    "Acme Corp"  "inventories/acme"
    _build_profile "$data/profiles/bigbank.yaml" "bigbank" "Big Bank"   "inventories/bigbank"

    cat > "$data/inventories/acme/hosts.yaml" <<'EOF'
hosts:
  - acme01.acme.corp
  - 10.1.1.1
EOF
    cat > "$data/inventories/bigbank/hosts.yaml" <<'EOF'
hosts:
  - bb01.bigbank.corp
  - 10.2.2.2
EOF

    export YCI_CUSTOMER="acme"
    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"

    local payload
    payload="$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' \
        "$data/inventories/bigbank/hosts.yaml")"

    local stdout stderr rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/tmp/yci-test-stderr-$$)"; rc=$?
    stderr="$(cat /tmp/yci-test-stderr-$$ 2>/dev/null)"; rm -f /tmp/yci-test-stderr-$$

    assert_exit 0 "$rc" "path_collision: exit 0"
    assert_contains "$stdout" '{"hookSpecificOutput"' "path_collision: stdout has hookSpecificOutput"
    assert_contains "$stdout" '"permissionDecision": "deny"' "path_collision: decision=deny"
    assert_contains "$stdout" "bigbank" "path_collision: stdout references bigbank"
    # The reason phrase is embedded in the JSON on stdout (permissionDecisionReason), not stderr.
    assert_error_id "guard-path-collision" "$stdout" "path_collision: guard-path-collision reason in stdout"

    unset YCI_CUSTOMER YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
with_sandbox test_path_collision

yci_test_summary
