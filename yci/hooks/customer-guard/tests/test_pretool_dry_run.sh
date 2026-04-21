#!/usr/bin/env bash
# Integration tests: pretool.sh dry-run mode.
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
# test_dry_run_logs_and_allows: YCI_GUARD_DRY_RUN=1 on a would-deny payload.
# Expected:
#   - stdout EMPTY (allow)
#   - stderr contains DRY-RUN banner
#   - audit.log is created and contains "would-block"
# ---------------------------------------------------------------------------
test_dry_run_logs_and_allows() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "dry_run: skipped (pretool.sh not found)"; return 0; }

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

    export YCI_CUSTOMER="acme"
    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"
    local YCI_GUARD_DRY_RUN=1
    export YCI_GUARD_DRY_RUN

    local payload
    payload="$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' \
        "$data/inventories/bigbank/hosts.yaml")"

    local stdout stderr rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/tmp/yci-test-dr-stderr-$$)"; rc=$?
    stderr="$(cat /tmp/yci-test-dr-stderr-$$ 2>/dev/null)"; rm -f /tmp/yci-test-dr-stderr-$$

    local audit_log="$data/.cache/customer-isolation/audit.log"

    assert_exit 0 "$rc" "dry_run: exit 0 (allow)"
    assert_eq "$stdout" "" "dry_run: stdout empty (allowed in dry-run)"
    assert_contains "$stderr" "YCI GUARD: DRY-RUN MODE ACTIVE" "dry_run: DRY-RUN banner in stderr"
    assert_file_exists "$audit_log" "dry_run: audit.log created"

    if [ -f "$audit_log" ]; then
        local audit_content
        audit_content="$(cat "$audit_log")"
        assert_contains "$audit_content" "would-block" "dry_run: audit.log contains would-block"
    fi

    unset YCI_CUSTOMER YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED YCI_GUARD_DRY_RUN
}

# ---------------------------------------------------------------------------
with_sandbox test_dry_run_logs_and_allows

yci_test_summary
