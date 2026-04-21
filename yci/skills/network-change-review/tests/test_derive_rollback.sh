#!/usr/bin/env bash
# yci network-change-review — derive-rollback.sh tests
# Tests cover: all three reversal arms, round-trip identity, and all error paths.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/helpers.sh"

DERIVE_ROLLBACK="${SKILL_ROOT}/scripts/derive-rollback.sh"
CHANGES_DIR="${FIXTURES_ROOT}/changes"

# ---------------------------------------------------------------------------
# Helper: build a normalized-change JSON envelope from a file and a diff_kind
# Usage: build_envelope <diff_kind> <input_file>
# Prints the JSON to stdout.
# ---------------------------------------------------------------------------
build_envelope() {
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
# Helper: build envelope from a raw string (no file)
# Usage: build_envelope_raw <diff_kind> <raw_string>
# ---------------------------------------------------------------------------
build_envelope_raw() {
    local diff_kind="$1"
    local raw="$2"
    python3 -c "
import json, sys
out = {
    'diff_kind': sys.argv[1],
    'raw':       sys.argv[2],
    'summary':   'Test envelope (synthetic)',
    'targets':   [],
}
print(json.dumps(out))
" "$diff_kind" "$raw"
}

# ---------------------------------------------------------------------------
# 1. unified-diff reversal — + and - lines swapped; header paths swapped
# ---------------------------------------------------------------------------
test_unified_diff_reversal() {
    local envelope out rc
    envelope="$(build_envelope "unified-diff" "${CHANGES_DIR}/unified-diff.patch")"
    out="$(printf '%s' "$envelope" | "$DERIVE_ROLLBACK" 2>/dev/null)"
    rc=$?

    assert_exit_code 0 "$rc" "unified-diff reversal: exit 0"

    # The forward diff has "--- a/..." and "+++ b/..." — after reversal the
    # paths should be swapped: --- becomes what was +++, and vice versa.
    assert_contains "+++ a/configs/dc1-edge-01.wgt.example.invalid/interfaces.conf" "$out" \
        "unified-diff reversal: +++ path swapped to a/ path"
    assert_contains "--- b/configs/dc1-edge-01.wgt.example.invalid/interfaces.conf" "$out" \
        "unified-diff reversal: --- path swapped to b/ path"

    # The forward diff adds mtu 9000 (+) and removes mtu 1500 (-).
    # After reversal: mtu 9000 should be removed (-) and mtu 1500 added (+).
    assert_contains "-  mtu 9000" "$out" "unified-diff reversal: added line becomes removed"
    assert_contains "+  mtu 1500" "$out" "unified-diff reversal: removed line becomes added"
}

# ---------------------------------------------------------------------------
# 2. Round-trip identity — reverse(reverse(diff)) == original diff
# ---------------------------------------------------------------------------
test_round_trip_identity() {
    local envelope reversed_envelope original_raw reversed_out double_reversed_out rc1 rc2

    # First reversal
    envelope="$(build_envelope "unified-diff" "${CHANGES_DIR}/unified-diff.patch")"
    reversed_out="$(printf '%s' "$envelope" | "$DERIVE_ROLLBACK" 2>/dev/null)"
    rc1=$?
    assert_exit_code 0 "$rc1" "round-trip: first reversal exits 0"

    # Build envelope from the reversed diff
    reversed_envelope="$(build_envelope_raw "unified-diff" "$reversed_out")"

    # Second reversal — should recover original
    double_reversed_out="$(printf '%s' "$reversed_envelope" | "$DERIVE_ROLLBACK" 2>/dev/null)"
    rc2=$?
    assert_exit_code 0 "$rc2" "round-trip: second reversal exits 0"

    # Read original raw content from the patch file
    original_raw="$(cat "${CHANGES_DIR}/unified-diff.patch")"

    # Normalize both for comparison (strip trailing whitespace per line,
    # remove trailing blank lines) using python3 to be shell-safe.
    local norm_original norm_roundtrip
    norm_original="$(python3 -c "
import sys
raw = sys.argv[1]
lines = [l.rstrip() for l in raw.splitlines()]
# strip trailing empty lines
while lines and not lines[-1]:
    lines.pop()
print('\n'.join(lines))
" "$original_raw")"

    norm_roundtrip="$(python3 -c "
import sys
raw = sys.argv[1]
lines = [l.rstrip() for l in raw.splitlines()]
while lines and not lines[-1]:
    lines.pop()
print('\n'.join(lines))
" "$double_reversed_out")"

    if [ "$norm_original" = "$norm_roundtrip" ]; then
        _yci_test_report PASS "round-trip: reverse(reverse(diff)) == original"
    else
        _yci_test_report FAIL "round-trip: reverse(reverse(diff)) == original" \
            "double-reversed output diverges from original"
    fi
}

# ---------------------------------------------------------------------------
# 3. structured-yaml reversal — reverse: block emitted verbatim
# ---------------------------------------------------------------------------
test_structured_yaml_reversal() {
    local envelope out rc
    envelope="$(build_envelope "structured-yaml" "${CHANGES_DIR}/structured-with-reverse.yaml")"
    out="$(printf '%s' "$envelope" | "$DERIVE_ROLLBACK" 2>/dev/null)"
    rc=$?

    assert_exit_code 0 "$rc" "structured-yaml reversal: exit 0"

    # The fixture's reverse: block targets dc1-edge-01 and removes the OSPF network statement
    assert_contains "dc1-edge-01" "$out" "structured-yaml reversal: output contains device dc1-edge-01"
    assert_contains "no network 10.100.1.0" "$out" "structured-yaml reversal: output contains reverse CLI"
}

# ---------------------------------------------------------------------------
# 4. structured-yaml without reverse: block — exit 3, ncr-rollback-missing-reverse
# ---------------------------------------------------------------------------
test_structured_yaml_missing_reverse() {
    # Build a forward-only structured YAML (no reverse: key)
    local forward_only_yaml
    forward_only_yaml="$(mktemp /tmp/ncr-test-forward-only-XXXXXX.yaml)"
    cat > "$forward_only_yaml" <<'YAML'
forward:
  - device: dc1-edge-01
    cli: |
      router ospf 1
        network 10.100.1.0 0.0.0.255 area 0
YAML

    local envelope stderr_out rc err_content
    envelope="$(build_envelope "structured-yaml" "$forward_only_yaml")"
    stderr_out="$(mktemp)"
    set +e
    printf '%s' "$envelope" | "$DERIVE_ROLLBACK" 2>"$stderr_out"
    rc=$?
    set -e
    err_content="$(cat "$stderr_out")"
    rm -f "$forward_only_yaml" "$stderr_out"

    assert_exit_code 3 "$rc" "missing-reverse: exit 3"
    assert_contains "ncr-rollback-missing-reverse" "$err_content" \
        "missing-reverse: stderr contains ncr-rollback-missing-reverse"
}

# ---------------------------------------------------------------------------
# 5. playbook/ambiguous — exit 0, stdout MANUAL DERIVATION REQUIRED, stderr ncr-rollback-ambiguous
# ---------------------------------------------------------------------------
test_playbook_manual_derivation() {
    local envelope out stderr_out rc err_content
    envelope="$(build_envelope "playbook" "${CHANGES_DIR}/ambiguous.yaml")"
    stderr_out="$(mktemp)"
    out="$(printf '%s' "$envelope" | "$DERIVE_ROLLBACK" 2>"$stderr_out")"
    rc=$?
    err_content="$(cat "$stderr_out")"
    rm -f "$stderr_out"

    assert_exit_code 0 "$rc" "playbook: exit 0"
    assert_contains "MANUAL DERIVATION REQUIRED" "$out" \
        "playbook: stdout contains MANUAL DERIVATION REQUIRED"
    assert_contains "ncr-rollback-ambiguous" "$err_content" \
        "playbook: stderr contains ncr-rollback-ambiguous"
}

# ---------------------------------------------------------------------------
# 6. unknown diff_kind — exit 3, ncr-diff-unsupported-shape
# ---------------------------------------------------------------------------
test_unknown_diff_kind() {
    local envelope stderr_out rc err_content
    envelope="$(build_envelope_raw "garbage" "some raw content")"
    stderr_out="$(mktemp)"
    set +e
    printf '%s' "$envelope" | "$DERIVE_ROLLBACK" 2>"$stderr_out"
    rc=$?
    set -e
    err_content="$(cat "$stderr_out")"
    rm -f "$stderr_out"

    assert_exit_code 3 "$rc" "unknown-diff-kind: exit 3"
    assert_contains "ncr-diff-unsupported-shape" "$err_content" \
        "unknown-diff-kind: stderr contains ncr-diff-unsupported-shape"
}

# ---------------------------------------------------------------------------
# 7. unified-diff with headers only (no @@ hunks) — exit 3
# ---------------------------------------------------------------------------
test_header_only_unified_diff_rejected() {
    local header_only_raw stderr_out rc err_content envelope
    header_only_raw="$(printf '%s\n' \
        '--- a/foo.txt' \
        '+++ b/foo.txt')"

    envelope="$(build_envelope_raw "unified-diff" "$header_only_raw")"
    stderr_out="$(mktemp)"
    set +e
    printf '%s' "$envelope" | "$DERIVE_ROLLBACK" 2>"$stderr_out"
    rc=$?
    set -e
    err_content="$(cat "$stderr_out")"
    rm -f "$stderr_out"

    assert_exit_code 3 "$rc" "header-only: exit 3"
    assert_contains "ncr-diff-unsupported-shape" "$err_content" \
        "header-only: stderr contains ncr-diff-unsupported-shape"
}

# ---------------------------------------------------------------------------
# 8. binary diff rejection — exit 3, ncr-rollback-binary-unsupported
# ---------------------------------------------------------------------------
test_binary_diff_rejection() {
    # Construct a unified-diff whose raw field contains a binary marker line.
    local binary_raw stderr_out rc err_content envelope
    binary_raw="$(printf '%s\n' \
        '--- a/images/logo.png' \
        '+++ b/images/logo.png' \
        'Binary files a/images/logo.png and b/images/logo.png differ')"

    envelope="$(build_envelope_raw "unified-diff" "$binary_raw")"
    stderr_out="$(mktemp)"
    set +e
    printf '%s' "$envelope" | "$DERIVE_ROLLBACK" 2>"$stderr_out"
    rc=$?
    set -e
    err_content="$(cat "$stderr_out")"
    rm -f "$stderr_out"

    assert_exit_code 3 "$rc" "binary-diff: exit 3"
    assert_contains "ncr-rollback-binary-unsupported" "$err_content" \
        "binary-diff: stderr contains ncr-rollback-binary-unsupported"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    test_unified_diff_reversal
    test_round_trip_identity
    test_structured_yaml_reversal
    test_structured_yaml_missing_reverse
    test_playbook_manual_derivation
    test_unknown_diff_kind
    test_header_only_unified_diff_rejected
    test_binary_diff_rejection
    summary
}

main
