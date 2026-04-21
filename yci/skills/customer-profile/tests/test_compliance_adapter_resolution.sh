#!/usr/bin/env bash
# Tests for load-compliance-adapter.sh — end-to-end resolution cases.
# Covers:
#   1. _internal profile → none adapter
#   2. commercial-example fixture → commercial adapter
#   3. synthetic JSON with unknown regime → exit 2 + stderr phrase
#
# shellcheck disable=SC1091
set -uo pipefail  # no -e: tests handle their own failures to report all cases

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

LOADER="${YCI_SCRIPTS_DIR}/load-profile.sh"
ADAPTER_LOADER="${YCI_SHARED_DIR}/load-compliance-adapter.sh"

# Resolve the yci plugin root (parent of skills/) from helpers' known path.
# YCI_SHARED_DIR = <yci>/skills/_shared/scripts — walk up three levels.
_YCI_ROOT="$(cd "${YCI_SHARED_DIR}/../../.." && pwd -P)"
_FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures" && pwd -P)"
_INTERNAL_YAML="${_YCI_ROOT}/docs/profiles/_internal.yaml.example"
_COMMERCIAL_FIXTURE="${_FIXTURES_DIR}/commercial-example.yaml"

# ---------------------------------------------------------------------------
# Guard: diagnostic if either script is absent (non-fatal, skips gracefully)
# ---------------------------------------------------------------------------
_adapter_loader_present() {
    if [ ! -f "$ADAPTER_LOADER" ]; then
        printf 'DIAGNOSTIC: load-compliance-adapter.sh not found at %s\n' \
            "$ADAPTER_LOADER" >&2
        return 1
    fi
    return 0
}

_loader_present() {
    if [ ! -f "$LOADER" ]; then
        printf 'DIAGNOSTIC: load-profile.sh not found at %s\n' "$LOADER" >&2
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Case 1 — _internal profile → none adapter
# ---------------------------------------------------------------------------
test_internal_resolves_none() {
    local sb="$1"

    if ! _loader_present; then
        _yci_test_report SKIP "internal_none (load-profile absent)"; return 0
    fi
    if ! _adapter_loader_present; then
        _yci_test_report SKIP "internal_none (adapter loader absent)"; return 0
    fi
    if [ ! -f "$_INTERNAL_YAML" ]; then
        _yci_test_report FAIL "internal_none: _internal.yaml.example not found at $_INTERNAL_YAML"
        return 0
    fi

    mkdir -p "$sb/real/profiles"
    cp "$_INTERNAL_YAML" "$sb/real/profiles/_internal.yaml"

    local profile_json profile_rc
    profile_json="$("$LOADER" "$sb/real" _internal 2>"$sb/load_err")"
    profile_rc=$?
    assert_exit 0 "$profile_rc" "internal_none: load-profile exit 0"

    local adapter_path adapter_rc
    adapter_path="$(printf '%s\n' "$profile_json" | "$ADAPTER_LOADER" 2>"$sb/adapter_err")"
    adapter_rc=$?
    assert_exit 0 "$adapter_rc" "internal_none: load-compliance-adapter exit 0"

    case "$adapter_path" in
        */compliance-adapters/none)
            _yci_test_report PASS "internal_none: path ends with /compliance-adapters/none"
            ;;
        *)
            _yci_test_report FAIL "internal_none: path ends with /compliance-adapters/none" \
                "got='$adapter_path'"
            ;;
    esac

    if [ -d "$adapter_path" ]; then
        _yci_test_report PASS "internal_none: adapter dir exists"
    else
        _yci_test_report FAIL "internal_none: adapter dir exists" \
            "not a directory: $adapter_path"
    fi
}

# ---------------------------------------------------------------------------
# Case 2 — commercial-example fixture → commercial adapter
# ---------------------------------------------------------------------------
test_commercial_resolves_commercial() {
    local sb="$1"

    if ! _loader_present; then
        _yci_test_report SKIP "commercial (load-profile absent)"; return 0
    fi
    if ! _adapter_loader_present; then
        _yci_test_report SKIP "commercial (adapter loader absent)"; return 0
    fi
    if [ ! -f "$_COMMERCIAL_FIXTURE" ]; then
        _yci_test_report FAIL "commercial: fixture not found at $_COMMERCIAL_FIXTURE"
        return 0
    fi

    mkdir -p "$sb/real/profiles"
    cp "$_COMMERCIAL_FIXTURE" "$sb/real/profiles/widgetco-example.yaml"

    local profile_json profile_rc
    profile_json="$("$LOADER" "$sb/real" widgetco-example 2>"$sb/load_err")"
    profile_rc=$?
    assert_exit 0 "$profile_rc" "commercial: load-profile exit 0"

    local adapter_path adapter_rc
    adapter_path="$(printf '%s\n' "$profile_json" | "$ADAPTER_LOADER" 2>"$sb/adapter_err")"
    adapter_rc=$?
    assert_exit 0 "$adapter_rc" "commercial: load-compliance-adapter exit 0"

    case "$adapter_path" in
        */compliance-adapters/commercial)
            _yci_test_report PASS "commercial: path ends with /compliance-adapters/commercial"
            ;;
        *)
            _yci_test_report FAIL "commercial: path ends with /compliance-adapters/commercial" \
                "got='$adapter_path'"
            ;;
    esac

    if [ -d "$adapter_path" ]; then
        _yci_test_report PASS "commercial: adapter dir exists"
    else
        _yci_test_report FAIL "commercial: adapter dir exists" \
            "not a directory: $adapter_path"
    fi

    if [ -f "${adapter_path}/evidence-schema.json" ]; then
        _yci_test_report PASS "commercial: evidence-schema.json present"
    else
        _yci_test_report FAIL "commercial: evidence-schema.json present" \
            "missing ${adapter_path}/evidence-schema.json"
    fi
}

# ---------------------------------------------------------------------------
# Case 3 — unknown regime → exit 2 + stderr phrase
# ---------------------------------------------------------------------------
test_unknown_regime_exits_2() {
    local sb="$1"

    if ! _adapter_loader_present; then
        _yci_test_report SKIP "unknown_regime (adapter loader absent)"; return 0
    fi

    local synthetic_json
    synthetic_json='{"customer":{"id":"fake"},"compliance":{"regime":"definitely-not-real","evidence_schema_version":1}}'

    local combined_output adapter_rc
    combined_output="$(printf '%s\n' "$synthetic_json" | "$ADAPTER_LOADER" 2>&1)"
    adapter_rc=$?

    assert_exit 2 "$adapter_rc" "unknown_regime: exit code is 2"

    assert_contains "$combined_output" "unknown compliance regime" \
        "unknown_regime: stderr contains 'unknown compliance regime'"

    # stdout must be empty on failure — capture stdout separately
    local stdout_only
    stdout_only="$(printf '%s\n' "$synthetic_json" | "$ADAPTER_LOADER" 2>/dev/null)" || true
    assert_eq "$stdout_only" "" "unknown_regime: stdout is empty on failure"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    printf '## %s\n' "test_compliance_adapter_resolution.sh"

    with_sandbox test_internal_resolves_none
    with_sandbox test_commercial_resolves_commercial
    with_sandbox test_unknown_regime_exits_2

    yci_test_summary
}

main
