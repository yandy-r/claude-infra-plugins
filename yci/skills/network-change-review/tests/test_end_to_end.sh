#!/usr/bin/env bash
# yci network-change-review — end-to-end acceptance test (step 6.1)
#
# Ship gate: validates every acceptance criterion from issue #32 against the
# real review.sh orchestrator and B1 fixtures.
#
# AC1: /yci:review <change> produces a review artifact in the active profile's
#       deliverable format.
# AC2: Output is dual-branded (customer + consultant).
# AC3: Cross-customer-guard verified (no other customer's identifiers leak).
# AC4: Rollback plan auto-derived by reversing the diff.
# AC5: End-to-end test against fixture profile + diff (scaffolding assertion).
#
# Usage: bash test_end_to_end.sh [--verbose]

set -uo pipefail
# NOTE: intentionally no -e; helpers track FAIL counts without killing the
# script, so all failures surface before exit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./helpers.sh
source "${SCRIPT_DIR}/helpers.sh"

# ---------------------------------------------------------------------------
# Key paths
# ---------------------------------------------------------------------------
# DATA_ROOT = $FIXTURES_ROOT so that inventory.root in widget-corp.yaml
# (../../../../blast-radius/tests/fixtures/inventory-widgetcorp, relative to
# profiles/) resolves correctly.
DATA_ROOT="$FIXTURES_ROOT"
REVIEW_SH="$SKILL_ROOT/scripts/review.sh"
DERIVE_ROLLBACK="$SKILL_ROOT/scripts/derive-rollback.sh"

# ---------------------------------------------------------------------------
# Shared temp dir — all orchestrator output lands here; cleaned on exit.
# ---------------------------------------------------------------------------
TMPOUT="$(mktemp -d)"
trap 'rm -rf "$TMPOUT"' EXIT

# ---------------------------------------------------------------------------
# Helper: build a normalized-change JSON envelope from a file and a diff_kind.
# ---------------------------------------------------------------------------
_build_envelope() {
    local diff_kind="$1"
    local input_file="$2"
    python3 - "$diff_kind" "$input_file" <<'PYEOF'
import json, sys
diff_kind  = sys.argv[1]
input_file = sys.argv[2]
raw        = open(input_file).read()
out = {
    "diff_kind": diff_kind,
    "raw":       raw,
    "summary":   f"Test envelope for {diff_kind}",
    "targets":   [],
}
print(json.dumps(out))
PYEOF
}

# ---------------------------------------------------------------------------
# AC1 — artifact emitted
# ---------------------------------------------------------------------------
test_ac1_artifact_emitted() {
    printf '\n--- AC1: artifact emitted ---\n'

    local out_dir="$TMPOUT/run1"
    local stdout_cap="$TMPOUT/run1.stdout"
    local stderr_cap="$TMPOUT/run1.stderr"
    local rc=0

    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$REVIEW_SH" \
        --change  "$FIXTURES_ROOT/changes/unified-diff.patch" \
        --customer widget-corp \
        --data-root "$DATA_ROOT" \
        --output-dir "$out_dir" \
        > "$stdout_cap" 2> "$stderr_cap" || rc=$?

    assert_exit_code 0 "$rc" "AC1: review.sh exits 0"

    # The final artifact path is the last non-empty line of stdout.
    # (render-artifact.sh also prints its intermediate workdir path to stdout,
    # so we take only the last line rather than assuming a single line.)
    local artifact_path
    artifact_path="$(grep -v '^$' "$stdout_cap" | tail -1)"

    if [ -n "$artifact_path" ]; then
        _yci_test_report PASS "AC1: stdout is non-empty (artifact path printed)"
    else
        _yci_test_report FAIL "AC1: stdout is non-empty (artifact path printed)"
    fi

    assert_matches ".*/run1/review\\.md$" "$artifact_path" \
        "AC1: stdout path ends with run1/review.md"

    assert_file_exists "$artifact_path" \
        "AC1: artifact file exists on disk"

    local line_count=0
    [ -f "$artifact_path" ] && line_count="$(wc -l < "$artifact_path")"
    if [ "$line_count" -gt 30 ]; then
        _yci_test_report PASS "AC1: artifact has > 30 lines ($line_count)"
    else
        _yci_test_report FAIL "AC1: artifact has > 30 lines ($line_count)"
    fi
}

# ---------------------------------------------------------------------------
# AC2 — dual branding
# ---------------------------------------------------------------------------
test_ac2_dual_branding() {
    printf '\n--- AC2: dual branding ---\n'

    local artifact="$TMPOUT/run1/review.md"

    if [ ! -f "$artifact" ]; then
        _yci_test_report FAIL "AC2: artifact exists (prerequisite)"
        return
    fi

    local customer_count=0
    customer_count="$(grep -cF '**Prepared for Widget Corp**' "$artifact" 2>/dev/null || true)"
    if [ "$customer_count" -ge 1 ]; then
        _yci_test_report PASS "AC2: customer brand marker present (count=$customer_count)"
    else
        _yci_test_report FAIL "AC2: customer brand marker present (count=$customer_count)"
    fi

    # consultant-brand.md uses "## Prepared by" heading per references/consultant-brand.md
    local consultant_count=0
    consultant_count="$(grep -cE '(\*\*Prepared by\*\*|## Prepared by)' "$artifact" 2>/dev/null || true)"
    if [ "$consultant_count" -ge 1 ]; then
        _yci_test_report PASS "AC2: consultant brand marker present (count=$consultant_count)"
    else
        _yci_test_report FAIL "AC2: consultant brand marker present (count=$consultant_count)"
    fi

    # No unfilled {{...}} slots remain
    if ! grep -q '{{' "$artifact" 2>/dev/null; then
        _yci_test_report PASS "AC2: no unfilled slot markers remain"
    else
        local slots
        slots="$(grep -o '{{[^}]*}}' "$artifact" | sort -u | head -5 | tr '\n' ' ')"
        _yci_test_report FAIL "AC2: no unfilled slot markers remain (found: $slots)"
    fi
}

# ---------------------------------------------------------------------------
# AC3 (control) — sanity-check that the fixture actually contains bigbank ids
# ---------------------------------------------------------------------------
test_ac3_control_bigbank_ids_in_fixture() {
    printf '\n--- AC3 control: bigbank identifiers present in cross-customer fixture ---\n'

    local fixture="$FIXTURES_ROOT/changes/cross-customer-leak.patch"

    if [ ! -f "$fixture" ]; then
        _yci_test_report FAIL "AC3 control: cross-customer-leak.patch exists"
        return
    fi

    local content
    content="$(cat "$fixture")"

    assert_contains "bbk-dc2-edge-01" "$content" \
        "AC3 control: bigbank hostname bbk-dc2-edge-01 in fixture"

    assert_contains "10.200." "$content" \
        "AC3 control: bigbank IP prefix 10.200. in fixture"

    assert_contains "SOW-BBK-2025-07" "$content" \
        "AC3 control: bigbank SOW ref SOW-BBK-2025-07 in fixture"
}

# ---------------------------------------------------------------------------
# AC3 — cross-customer leak refused (exit 7)
# ---------------------------------------------------------------------------
test_ac3_cross_customer_leak_refused() {
    printf '\n--- AC3: cross-customer leak refused ---\n'

    local out_dir="$TMPOUT/run2"
    local stderr_cap="$TMPOUT/run2.stderr"
    local rc=0

    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$REVIEW_SH" \
        --change  "$FIXTURES_ROOT/changes/cross-customer-leak.patch" \
        --customer widget-corp \
        --data-root "$DATA_ROOT" \
        --output-dir "$out_dir" \
        > /dev/null 2> "$stderr_cap" || rc=$?

    assert_exit_code 7 "$rc" "AC3: review.sh exits 7 for cross-customer change"

    local stderr_content
    stderr_content="$(cat "$stderr_cap")"
    assert_contains "ncr-cross-customer-leak-detected" "$stderr_content" \
        "AC3: stderr contains ncr-cross-customer-leak-detected"

    if [ ! -f "$out_dir/review.md" ]; then
        _yci_test_report PASS "AC3: no review.md written for refused change"
    else
        _yci_test_report FAIL "AC3: no review.md written for refused change"
    fi
}

# ---------------------------------------------------------------------------
# AC4a — rollback present in run1 output
# ---------------------------------------------------------------------------
test_ac4_rollback_present() {
    printf '\n--- AC4a: rollback present ---\n'

    local rollback_file="$TMPOUT/run1/rollback.txt"
    local artifact="$TMPOUT/run1/review.md"

    assert_file_exists "$rollback_file" "AC4a: rollback.txt exists"

    if [ -f "$artifact" ]; then
        if grep -q "Rollback Plan" "$artifact" 2>/dev/null; then
            _yci_test_report PASS "AC4a: artifact contains 'Rollback Plan' heading"
        else
            _yci_test_report FAIL "AC4a: artifact contains 'Rollback Plan' heading"
        fi

        # Rollback section should contain at least one +/- diff line
        local rollback_content_lines
        rollback_content_lines="$(grep -c '^[+-]' "$artifact" 2>/dev/null)" || rollback_content_lines=0
        # Strip leading/trailing whitespace (wc -l / grep -c can pad on some systems)
        rollback_content_lines="${rollback_content_lines//[[:space:]]/}"
        if [ "${rollback_content_lines:-0}" -ge 1 ] 2>/dev/null; then
            _yci_test_report PASS "AC4a: rollback section has diff +/- lines ($rollback_content_lines)"
        else
            _yci_test_report FAIL "AC4a: rollback section has diff +/- lines ($rollback_content_lines)"
        fi
    else
        _yci_test_report FAIL "AC4a: artifact exists (prerequisite for rollback heading check)"
    fi
}

# ---------------------------------------------------------------------------
# AC4b — rollback is mechanical inverse (round-trip)
# ---------------------------------------------------------------------------
test_ac4_rollback_mechanical_inverse() {
    printf '\n--- AC4b: rollback is mechanical inverse ---\n'

    local rollback_file="$TMPOUT/run1/rollback.txt"

    if [ ! -f "$rollback_file" ]; then
        _yci_test_report FAIL "AC4b: rollback.txt exists (prerequisite)"
        return
    fi

    local orig
    orig="$(cat "$FIXTURES_ROOT/changes/unified-diff.patch")"

    local rollback
    rollback="$(cat "$rollback_file")"

    # Build a normalized-change envelope wrapping the rollback content (which
    # itself is a unified diff), then run derive-rollback.sh on it.  The
    # result should equal the original diff (reverse-of-reverse = identity).
    local rev2_env
    rev2_env="$(python3 -c "
import json, sys, os
rollback = open(sys.argv[1]).read()
out = {
    'diff_kind': 'unified-diff',
    'raw':       rollback,
    'summary':   'round-trip test',
    'targets':   [],
}
print(json.dumps(out))
" "$rollback_file")"

    local rev2=""
    local derive_rc=0
    rev2="$(echo "$rev2_env" | bash "$DERIVE_ROLLBACK")" || derive_rc=$?

    assert_exit_code 0 "$derive_rc" "AC4b: derive-rollback.sh exits 0 on rollback input"

    # Normalize whitespace for comparison (strip trailing spaces; ignore blank-line diffs)
    local orig_norm rev2_norm
    orig_norm="$(printf '%s' "$orig" | sed 's/[[:space:]]*$//')"
    rev2_norm="$(printf '%s' "$rev2"  | sed 's/[[:space:]]*$//')"

    if [ "$orig_norm" = "$rev2_norm" ]; then
        _yci_test_report PASS "AC4b: rollback is mechanical inverse of input (round-trip identity)"
    else
        _yci_test_report FAIL "AC4b: rollback is mechanical inverse of input (round-trip identity)"
        # Emit a short diff hint to stderr for debugging
        printf '    orig  (first 5 lines): %s\n' "$(printf '%s' "$orig_norm"  | head -5)" >&2
        printf '    rev2  (first 5 lines): %s\n' "$(printf '%s' "$rev2_norm"  | head -5)" >&2
    fi
}

# ---------------------------------------------------------------------------
# AC5 — supporting files present and non-empty
# ---------------------------------------------------------------------------
test_ac5_supporting_files() {
    printf '\n--- AC5: supporting files ---\n'

    local out_dir="$TMPOUT/run1"

    for fname in review.md rollback.txt catalog.json evidence-stub.yaml blast-radius-label.json; do
        local fpath="$out_dir/$fname"
        assert_file_exists "$fpath" "AC5: $fname exists"
        if [ -f "$fpath" ]; then
            if [ -s "$fpath" ]; then
                _yci_test_report PASS "AC5: $fname is non-empty"
            else
                _yci_test_report FAIL "AC5: $fname is non-empty"
            fi
        fi
    done

    # evidence-stub.yaml must contain "approver: _pending_"
    local evidence_stub="$out_dir/evidence-stub.yaml"
    if [ -f "$evidence_stub" ]; then
        if grep -q "approver: _pending_" "$evidence_stub" 2>/dev/null; then
            _yci_test_report PASS "AC5: evidence-stub.yaml contains 'approver: _pending_'"
        else
            _yci_test_report FAIL "AC5: evidence-stub.yaml contains 'approver: _pending_'"
        fi
    fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    test_ac1_artifact_emitted
    test_ac2_dual_branding
    test_ac3_control_bigbank_ids_in_fixture
    test_ac3_cross_customer_leak_refused
    test_ac4_rollback_present
    test_ac4_rollback_mechanical_inverse
    test_ac5_supporting_files
    summary
}
main "$@"
