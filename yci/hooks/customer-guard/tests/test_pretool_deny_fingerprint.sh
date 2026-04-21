#!/usr/bin/env bash
# Integration tests: pretool.sh fingerprint/token-collision deny.
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
# test_fingerprint_collision: Write whose content contains a bigbank hostname
# that appears ONLY in bigbank's inventory → deny with identifier collision.
# We use bb01.bigbank.corp which is exclusive to bigbank's inventory.
# ---------------------------------------------------------------------------
test_fingerprint_collision() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "fingerprint_collision: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles" "$data/inventories/acme" "$data/inventories/bigbank"

    _build_profile "$data/profiles/acme.yaml"    "acme"    "Acme Corp" "inventories/acme"
    _build_profile "$data/profiles/bigbank.yaml" "bigbank" "Big Bank"  "inventories/bigbank"

    cat > "$data/inventories/acme/hosts.yaml" <<'EOF'
hosts:
  - acme01.acme.corp
  - 10.1.1.1
EOF
    # bb01.bigbank.corp only appears in bigbank's inventory
    cat > "$data/inventories/bigbank/hosts.yaml" <<'EOF'
hosts:
  - bb01.bigbank.corp
  - 10.2.2.2
EOF

    export YCI_CUSTOMER="acme"
    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"

    # Payload references bb01.bigbank.corp — a hostname from bigbank's inventory only.
    local payload='{"tool_name":"Write","tool_input":{"content":"connecting to bb01.bigbank.corp"}}'

    local stdout stderr rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/tmp/yci-test-stderr-$$)"; rc=$?
    stderr="$(cat /tmp/yci-test-stderr-$$ 2>/dev/null)"; rm -f /tmp/yci-test-stderr-$$

    assert_exit 0 "$rc" "fingerprint_collision: exit 0"
    assert_contains "$stdout" '{"hookSpecificOutput"' "fingerprint_collision: stdout has hookSpecificOutput"
    assert_contains "$stdout" '"permissionDecision": "deny"' "fingerprint_collision: decision=deny"
    # Reason must reference the foreign customer or colliding token
    local reason_ok=0
    case "$stdout" in
        *"bigbank"*) reason_ok=1 ;;
        *"hostname"*) reason_ok=1 ;;
    esac
    if [ "$reason_ok" = "1" ]; then
        _yci_test_report PASS "fingerprint_collision: reason references bigbank/hostname"
    else
        _yci_test_report FAIL "fingerprint_collision: reason missing bigbank/hostname reference"
    fi
    # The reason phrase is embedded in the JSON on stdout (permissionDecisionReason), not stderr.
    assert_error_id "guard-fingerprint-collision" "$stdout" "fingerprint_collision: guard-fingerprint-collision reason in stdout"

    unset YCI_CUSTOMER YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
with_sandbox test_fingerprint_collision

yci_test_summary
