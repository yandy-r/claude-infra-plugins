#!/usr/bin/env bash
# yci network-change-review — build-check-catalogs.sh unit tests
#
# Covers:
#   1. commercial adapter + rich label      (adapter + blast-radius sources)
#   2. none adapter + rich label            (adapter present; blast-radius still fires)
#   3. commercial adapter + empty label     (adapter checks emitted; blast-radius 0)
#   4. missing adapter dir                  (exit 2, ncr-adapter-unresolvable)
#   5. missing label file                   (exit 5, ncr-blast-radius-failed)
#   6. missing --adapter-dir flag           (exit non-zero with error)
#   7. output routing (--output <path>)     (file written; content matches stdout)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/helpers.sh"

# ---------------------------------------------------------------------------
# Resolve key paths via SKILL_ROOT / PLUGIN_ROOT exported by helpers.sh
# ---------------------------------------------------------------------------
BCC="${SKILL_ROOT}/scripts/build-check-catalogs.sh"
COMMERCIAL="${PLUGIN_ROOT}/skills/_shared/compliance-adapters/commercial"
NONE="${PLUGIN_ROOT}/skills/_shared/compliance-adapters/none"

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ---------------------------------------------------------------------------
# Label factories
# ---------------------------------------------------------------------------

make_rich_label() {
    # $1 = destination file path
    cat > "$1" <<'JSON'
{"label":"medium","direct_devices":[{"id":"dc1-edge-01","hostname":"dc1-edge-01.wgt.example.invalid"}],"services":[{"id":"svc-api","name":"API","slo_target":"99.9%"}],"dependencies":[{"from":"dc1-edge-01","to":"svc-api","kind":"link","type":"link"}]}
JSON
}

make_empty_label() {
    # $1 = destination file path
    echo '{"label":"low","direct_devices":[],"services":[],"dependencies":[]}' > "$1"
}

# ---------------------------------------------------------------------------
# py_check_schema — validate JSON shape and content constraints via python3
# $1 = file path containing catalog JSON
# $2 = human label for error output
# $3 = python snippet appended after the base assertions (optional)
# ---------------------------------------------------------------------------
py_check_schema() {
    local file="$1" label="$2" extra="${3:-}"
    python3 - "$file" <<PYEOF
import json, sys

d = json.load(open(sys.argv[1]))

assert "pre_check" in d and "post_check" in d, "missing top-level keys (pre_check / post_check)"

required_fields = ("id", "category", "source", "description", "applies_to")
for section in ("pre_check", "post_check"):
    for c in d[section]:
        for k in required_fields:
            assert k in c, f"missing field '{k}' in {section} entry: {c}"

${extra}

print("schema ok")
PYEOF
}

# Shared assertion block for commercial + rich label (single place to edit).
read -r -d '' ASSERTIONS_COMMERCIAL_RICH <<'PYA' || true
assert any(c["source"] == "adapter" for c in d["pre_check"]),       "no adapter-sourced pre-check"
assert any(c["source"] == "blast-radius" for c in d["pre_check"]),  "no blast-radius pre-check"
assert any(c["source"] == "adapter" for c in d["post_check"]),      "no adapter-sourced post-check"
assert any(c["source"] == "blast-radius" for c in d["post_check"]), "no blast-radius post-check"
assert any("dc1-edge-01" in str(c) for c in d["pre_check"] + d["post_check"]), "device dc1-edge-01 not referenced in any check"
assert any("svc-api" in str(c) for c in d["post_check"]),           "service svc-api not in any post-check"
PYA

# ---------------------------------------------------------------------------
# TEST 1 — commercial adapter + rich label
# ---------------------------------------------------------------------------
test_commercial_rich_label() {
    local label="${TMPDIR_TEST}/label-rich-commercial.json"
    local out="${TMPDIR_TEST}/out-commercial-rich.json"
    make_rich_label "$label"

    local rc
    bash "$BCC" --adapter-dir "$COMMERCIAL" --blast-radius-label "$label" --output "$out" && rc=0 || rc=$?
    assert_exit 0 "$rc" "commercial rich: exits 0"
    assert_file_exists "$out" "commercial rich: output file written"

    # --- JSON shape + content via python ----------------------------------------
    if py_check_schema "$out" "commercial-rich" "$ASSERTIONS_COMMERCIAL_RICH" > /dev/null 2>&1; then
        _yci_test_report PASS "commercial rich: schema and content checks pass"
    else
        # Re-run to surface the actual assertion message
        local detail
        detail="$(py_check_schema "$out" "commercial-rich" "$ASSERTIONS_COMMERCIAL_RICH" 2>&1 || true)"
        _yci_test_report FAIL "commercial rich: schema and content checks pass" "$detail"
    fi
}

# ---------------------------------------------------------------------------
# TEST 2 — none adapter + rich label
# ---------------------------------------------------------------------------
test_none_rich_label() {
    local label="${TMPDIR_TEST}/label-rich-none.json"
    local out="${TMPDIR_TEST}/out-none-rich.json"
    make_rich_label "$label"

    local rc
    bash "$BCC" --adapter-dir "$NONE" --blast-radius-label "$label" --output "$out" && rc=0 || rc=$?
    assert_exit 0 "$rc" "none rich: exits 0"
    assert_file_exists "$out" "none rich: output file written"

    # Determine whether none/handoff-checklist.md exists (governs adapter-source expectation)
    local has_checklist=0
    [ -f "${NONE}/handoff-checklist.md" ] && has_checklist=1

    local adapter_pre_expect
    if [ "$has_checklist" -eq 1 ]; then
        adapter_pre_expect='assert any(c["source"] == "adapter" for c in d["pre_check"]), "none adapter: expected >=1 adapter-sourced pre-check (handoff-checklist.md present)"'
    else
        adapter_pre_expect='assert not any(c["source"] == "adapter" for c in d["pre_check"]), "none adapter: expected 0 adapter pre-checks (no handoff-checklist.md)"'
    fi

    if py_check_schema "$out" "none-rich" "
${adapter_pre_expect}
assert any(c[\"source\"] == \"blast-radius\" for c in d[\"pre_check\"]),  \"none adapter: blast-radius pre-checks missing\"
assert any(c[\"source\"] == \"blast-radius\" for c in d[\"post_check\"]), \"none adapter: blast-radius post-checks missing\"
" > /dev/null 2>&1; then
        _yci_test_report PASS "none rich: schema and source checks pass"
    else
        local detail
        detail="$(py_check_schema "$out" "none-rich" "
${adapter_pre_expect}
assert any(c[\"source\"] == \"blast-radius\" for c in d[\"pre_check\"]),  \"none adapter: blast-radius pre-checks missing\"
assert any(c[\"source\"] == \"blast-radius\" for c in d[\"post_check\"]), \"none adapter: blast-radius post-checks missing\"
" 2>&1 || true)"
        _yci_test_report FAIL "none rich: schema and source checks pass" "$detail"
    fi
}

# ---------------------------------------------------------------------------
# TEST 3 — commercial adapter + empty label
# ---------------------------------------------------------------------------
test_commercial_empty_label() {
    local label="${TMPDIR_TEST}/label-empty.json"
    local out="${TMPDIR_TEST}/out-commercial-empty.json"
    make_empty_label "$label"

    local rc
    bash "$BCC" --adapter-dir "$COMMERCIAL" --blast-radius-label "$label" --output "$out" && rc=0 || rc=$?
    assert_exit 0 "$rc" "commercial empty: exits 0"
    assert_file_exists "$out" "commercial empty: output file written"

    if py_check_schema "$out" "commercial-empty" '
assert any(c["source"] == "adapter" for c in d["pre_check"]),    "commercial empty: adapter checks missing despite adapter-dir"
assert not any(c["source"] == "blast-radius" for c in d["pre_check"]),  "commercial empty: unexpected blast-radius pre-check for empty label"
assert not any(c["source"] == "blast-radius" for c in d["post_check"]), "commercial empty: unexpected blast-radius post-check for empty label"
' > /dev/null 2>&1; then
        _yci_test_report PASS "commercial empty: adapter checks present; blast-radius checks absent"
    else
        local detail
        detail="$(py_check_schema "$out" "commercial-empty" '
assert any(c["source"] == "adapter" for c in d["pre_check"]),    "commercial empty: adapter checks missing despite adapter-dir"
assert not any(c["source"] == "blast-radius" for c in d["pre_check"]),  "commercial empty: unexpected blast-radius pre-check for empty label"
assert not any(c["source"] == "blast-radius" for c in d["post_check"]), "commercial empty: unexpected blast-radius post-check for empty label"
' 2>&1 || true)"
        _yci_test_report FAIL "commercial empty: adapter checks present; blast-radius checks absent" "$detail"
    fi
}

# ---------------------------------------------------------------------------
# TEST 4 — missing adapter dir → exit 2, ncr-adapter-unresolvable
# ---------------------------------------------------------------------------
test_missing_adapter_dir() {
    local label="${TMPDIR_TEST}/label-dummy.json"
    make_rich_label "$label"

    local stderr_out rc
    stderr_out="$(bash "$BCC" \
        --adapter-dir "/nonexistent/adapter/path" \
        --blast-radius-label "$label" 2>&1)" && rc=0 || rc=$?

    assert_exit 2 "$rc" "missing adapter dir: exits 2"
    assert_contains "ncr-adapter-unresolvable" "$stderr_out" "missing adapter dir: error id in stderr"
}

# ---------------------------------------------------------------------------
# TEST 5 — missing label file → exit 5, ncr-blast-radius-failed
# ---------------------------------------------------------------------------
test_missing_label_file() {
    local stderr_out rc
    stderr_out="$(bash "$BCC" \
        --adapter-dir "$COMMERCIAL" \
        --blast-radius-label "/nonexistent/label.json" 2>&1)" && rc=0 || rc=$?

    assert_exit 5 "$rc" "missing label file: exits 5"
    assert_contains "ncr-blast-radius-failed" "$stderr_out" "missing label file: error id in stderr"
}

# ---------------------------------------------------------------------------
# TEST 6 — missing --adapter-dir flag → exit non-zero
# ---------------------------------------------------------------------------
test_missing_flags() {
    local label="${TMPDIR_TEST}/label-dummy2.json"
    make_rich_label "$label"

    local stderr_out rc
    stderr_out="$(bash "$BCC" \
        --blast-radius-label "$label" 2>&1)" && rc=0 || rc=$?

    if [ "$rc" -ne 0 ]; then
        _yci_test_report PASS "missing --adapter-dir: exits non-zero (rc=$rc)"
    else
        _yci_test_report FAIL "missing --adapter-dir: exits non-zero (rc=$rc)" "expected non-zero exit, got 0"
    fi

    assert_contains "ncr-adapter-unresolvable" "$stderr_out" "missing --adapter-dir: error id in stderr"
}

# ---------------------------------------------------------------------------
# TEST 7 — output routing (--output vs stdout)
# ---------------------------------------------------------------------------
test_output_routing() {
    local label="${TMPDIR_TEST}/label-routing.json"
    local out_file="${TMPDIR_TEST}/out-routing.json"
    make_rich_label "$label"

    # Write via --output
    local rc_file rc_stdout
    bash "$BCC" --adapter-dir "$COMMERCIAL" --blast-radius-label "$label" --output "$out_file" && rc_file=0 || rc_file=$?
    assert_exit 0 "$rc_file" "output routing: --output exits 0"
    assert_file_exists "$out_file" "output routing: output file exists"

    # Write via stdout
    local stdout_content
    stdout_content="$(bash "$BCC" --adapter-dir "$COMMERCIAL" --blast-radius-label "$label")" && rc_stdout=0 || rc_stdout=$?
    assert_exit 0 "$rc_stdout" "output routing: stdout exits 0"

    local file_content
    file_content="$(cat "$out_file")"

    # Validate both are valid JSON
    assert_json_valid "$file_content" "output routing: --output content is valid JSON"
    assert_json_valid "$stdout_content" "output routing: stdout content is valid JSON"

    # Compare equivalence via python deep-equal
    assert_json_eq "$file_content" "$stdout_content" "output routing: --output and stdout are equivalent"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    printf '  running %s\n' "test_build_check_catalogs.sh"
    test_commercial_rich_label
    test_none_rich_label
    test_commercial_empty_label
    test_missing_adapter_dir
    test_missing_label_file
    test_missing_flags
    test_output_routing
    yci_test_summary
}

main "$@"
