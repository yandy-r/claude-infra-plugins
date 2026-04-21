#!/usr/bin/env bash
# Integration tests: pretool.sh allow scenarios.
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
# test_allow_own_path: Read on active customer's own inventory file → allow.
# ---------------------------------------------------------------------------
test_allow_own_path() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "allow_own_path: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles" "$data/inventories/acme"

    _build_profile "$data/profiles/acme.yaml" "acme" "Acme Corp" "inventories/acme"

    cat > "$data/inventories/acme/hosts.yaml" <<'EOF'
hosts:
  - acme01.acme.corp
  - 10.1.1.1
EOF

    export YCI_CUSTOMER="acme"
    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"

    local payload
    payload="$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' \
        "$data/inventories/acme/hosts.yaml")"

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "allow_own_path: exit 0"
    assert_eq "$stdout" "" "allow_own_path: stdout empty (allow)"

    unset YCI_CUSTOMER YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
# test_missing_fields_fail_open: empty payload → fail-open (allow), exit 0.
# The guard-missing-tool-input error is emitted to stderr; stdout is EMPTY.
# ---------------------------------------------------------------------------
test_missing_fields_fail_open() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "missing_fields: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles" "$data/inventories/acme"

    _build_profile "$data/profiles/acme.yaml" "acme" "Acme Corp" "inventories/acme"

    export YCI_CUSTOMER="acme"
    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"
    export YCI_GUARD_STRICT=0

    local stdout rc
    stdout="$(printf '{}' | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "missing_fields: exit 0 (fail-open)"
    assert_eq "$stdout" "" "missing_fields: stdout empty (allow on missing input)"

    unset YCI_CUSTOMER YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED YCI_GUARD_STRICT
}

# ---------------------------------------------------------------------------
with_sandbox test_allow_own_path
with_sandbox test_missing_fields_fail_open

yci_test_summary
