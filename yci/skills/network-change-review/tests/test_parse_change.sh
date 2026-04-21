#!/usr/bin/env bash
# yci network-change-review — parse-change.sh tests
# Tests cover: diff-kind detection, inventory resolution, error IDs, JSON validity.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/helpers.sh"

PARSE_CHANGE="${SKILL_ROOT}/scripts/parse-change.sh"
CHANGES_DIR="${FIXTURES_ROOT}/changes"
WIDGETCORP_INV="${SKILL_ROOT%/skills/network-change-review}/skills/blast-radius/tests/fixtures/inventory-widgetcorp"

# ---------------------------------------------------------------------------
# 1. unified-diff detection
# ---------------------------------------------------------------------------
test_unified_diff_detection() {
    local out stderr_out rc
    stderr_out="$(mktemp)"
    out="$("$PARSE_CHANGE" --input "${CHANGES_DIR}/unified-diff.patch" 2>"$stderr_out")"
    rc=$?
    rm -f "$stderr_out"

    assert_exit_code 0 "$rc" "unified-diff: exit 0"
    assert_json_field "$out" "diff_kind" "unified-diff" "unified-diff: diff_kind correct"

    local raw
    raw="$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('raw',''))" "$out" 2>/dev/null)"
    if [ -n "$raw" ]; then
        _yci_test_report PASS "unified-diff: raw non-empty"
    else
        _yci_test_report FAIL "unified-diff: raw non-empty" "raw field is empty"
    fi

    assert_contains "Unified diff" "$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('summary',''))" "$out" 2>/dev/null)" "unified-diff: summary contains 'Unified diff'"
    assert_json_array_nonempty "$out" "targets" "unified-diff: targets non-empty"
}

# ---------------------------------------------------------------------------
# 2. unified-diff with inventory root — target resolves to device
# ---------------------------------------------------------------------------
test_unified_diff_with_inventory() {
    local out rc
    out="$(YCI_INVENTORY_ROOT="${WIDGETCORP_INV}" \
           "$PARSE_CHANGE" --input "${CHANGES_DIR}/unified-diff.patch" 2>/dev/null)"
    rc=$?

    assert_exit_code 0 "$rc" "unified-diff+inventory: exit 0"

    # First target should resolve to kind=device
    local first_kind first_id
    first_kind="$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
arr = d.get('targets', [])
print(arr[0].get('kind','') if arr else '')
" "$out" 2>/dev/null)"
    assert_equals "device" "$first_kind" "unified-diff+inventory: targets[0].kind == device"

    # id should be dc1-edge-01 (matched from inventory)
    first_id="$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
arr = d.get('targets', [])
print(arr[0].get('id','') if arr else '')
" "$out" 2>/dev/null)"
    assert_equals "dc1-edge-01" "$first_id" "unified-diff+inventory: targets[0].id == dc1-edge-01"
}

# ---------------------------------------------------------------------------
# 2b. structured-yaml — multiple identifier keys in one step
# ---------------------------------------------------------------------------
test_structured_yaml_multi_identifiers() {
    local out rc
    out="$("$PARSE_CHANGE" --input "${CHANGES_DIR}/structured-multi-id.yaml" 2>/dev/null)"
    rc=$?

    assert_exit_code 0 "$rc" "structured-yaml multi-id: exit 0"
    assert_json_field "$out" "diff_kind" "structured-yaml" "structured-yaml multi-id: diff_kind"

    local n
    n="$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(len(d.get('targets', [])))
" "$out" 2>/dev/null)"
    if [ "$n" -ge 2 ]; then
        _yci_test_report PASS "structured-yaml multi-id: >=2 targets from one step"
    else
        _yci_test_report FAIL "structured-yaml multi-id: >=2 targets from one step" "got count=$n"
    fi
}

# ---------------------------------------------------------------------------
# 3. structured-yaml detection
# ---------------------------------------------------------------------------
test_structured_yaml_detection() {
    local out rc
    out="$("$PARSE_CHANGE" --input "${CHANGES_DIR}/structured-with-reverse.yaml" 2>/dev/null)"
    rc=$?

    assert_exit_code 0 "$rc" "structured-yaml: exit 0"
    assert_json_field "$out" "diff_kind" "structured-yaml" "structured-yaml: diff_kind correct"
    assert_json_array_nonempty "$out" "targets" "structured-yaml: targets non-empty"
}

# ---------------------------------------------------------------------------
# 4. playbook detection
# ---------------------------------------------------------------------------
test_playbook_detection() {
    local out rc
    out="$("$PARSE_CHANGE" --input "${CHANGES_DIR}/ambiguous.yaml" 2>/dev/null)"
    rc=$?

    assert_exit_code 0 "$rc" "playbook: exit 0"
    assert_json_field "$out" "diff_kind" "playbook" "playbook: diff_kind correct"
}

# ---------------------------------------------------------------------------
# 5. missing --input flag
# ---------------------------------------------------------------------------
test_missing_input_flag() {
    local out rc
    set +e
    out="$("$PARSE_CHANGE" 2>&1)"
    rc=$?
    set -e

    if [ "$rc" -ne 0 ]; then
        _yci_test_report PASS "missing --input: exit non-zero"
    else
        _yci_test_report FAIL "missing --input: exit non-zero" "exit was 0"
    fi

    assert_contains "ncr-diff-unsupported-shape" "$out" "missing --input: stderr contains error ID"
}

# ---------------------------------------------------------------------------
# 6. nonexistent input file
# ---------------------------------------------------------------------------
test_nonexistent_input_file() {
    local out rc
    set +e
    out="$("$PARSE_CHANGE" --input "/tmp/ncr-test-nonexistent-$(date +%s).patch" 2>&1)"
    rc=$?
    set -e

    if [ "$rc" -ne 0 ]; then
        _yci_test_report PASS "nonexistent file: exit non-zero"
    else
        _yci_test_report FAIL "nonexistent file: exit non-zero" "exit was 0"
    fi

    assert_contains "ncr-diff-unsupported-shape" "$out" "nonexistent file: stderr contains error ID"
}

# ---------------------------------------------------------------------------
# 7. unresolvable targets with inventory root — exit 3, ncr-targets-unresolvable
# ---------------------------------------------------------------------------
test_unresolvable_targets_with_inventory() {
    local tmp_patch rc stderr_out

    # Create a temp unified-diff with paths that won't match any inventory entry
    tmp_patch="$(mktemp /tmp/ncr-test-XXXXXX.patch)"
    cat > "$tmp_patch" <<'PATCH'
--- a/configs/zzz-no-match-device-xyz/interfaces.conf
+++ b/configs/zzz-no-match-device-xyz/interfaces.conf
@@ -1,2 +1,2 @@
-old line
+new line
PATCH

    stderr_out="$(mktemp)"
    set +e
    YCI_INVENTORY_ROOT="${WIDGETCORP_INV}" \
        "$PARSE_CHANGE" --input "$tmp_patch" 2>"$stderr_out"
    rc=$?
    set -e
    local err_content
    err_content="$(cat "$stderr_out")"
    rm -f "$tmp_patch" "$stderr_out"

    assert_exit_code 3 "$rc" "unresolvable-targets: exit 3"
    assert_contains "ncr-targets-unresolvable" "$err_content" "unresolvable-targets: stderr contains ncr-targets-unresolvable"
}

# ---------------------------------------------------------------------------
# 8. JSON output validity
# ---------------------------------------------------------------------------
test_json_output_validity() {
    local out rc
    out="$("$PARSE_CHANGE" --input "${CHANGES_DIR}/unified-diff.patch" 2>/dev/null)"
    rc=$?

    assert_exit_code 0 "$rc" "json-validity: parse-change exits 0"

    if printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
        _yci_test_report PASS "json-validity: output is valid JSON"
    else
        _yci_test_report FAIL "json-validity: output is valid JSON" "python3 json.load failed"
    fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    test_unified_diff_detection
    test_unified_diff_with_inventory
    test_structured_yaml_multi_identifiers
    test_structured_yaml_detection
    test_playbook_detection
    test_missing_input_flag
    test_nonexistent_input_file
    test_unresolvable_targets_with_inventory
    test_json_output_validity
    summary
}

main
