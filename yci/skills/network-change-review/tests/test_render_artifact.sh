#!/usr/bin/env bash
# yci network-change-review — render-artifact.sh tests

# Intentionally omit -e: several tests assert on non-zero exits from render-artifact.sh
# using `|| true` or explicit rc capture (see failure-path tests below).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Source local helpers.sh (established API for this skill).
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/helpers.sh"

RENDER="${SKILL_ROOT_SCRIPTS}/render-artifact.sh"
ADAPTER_DIR="${PLUGIN_ROOT}/skills/_shared/compliance-adapters/commercial"
FIXTURE_PROFILE_YAML="${FIXTURES_ROOT}/profiles/widget-corp.yaml"
FIXTURE_HEADER="${FIXTURES_ROOT}/profiles/widget-corp-header.md"

# ---------------------------------------------------------------------------
# Per-test tmp directory
# ---------------------------------------------------------------------------

TMP_BASE=""
setup_tmp() {
    TMP_BASE="$(mktemp -d)"
}
teardown_tmp() {
    [[ -n "${TMP_BASE}" && -d "${TMP_BASE}" ]] && rm -rf "${TMP_BASE}"
}

# ---------------------------------------------------------------------------
# Helper: build a profile.json from widget-corp.yaml
# Copies widget-corp-header.md next to the JSON so the relative path resolves.
# Prints the path to the profile.json.
# ---------------------------------------------------------------------------
make_profile_json() {
    local dest_dir="${1:-${TMP_BASE}}"
    local profile_json="${dest_dir}/profile.json"
    python3 - "${FIXTURE_PROFILE_YAML}" "${profile_json}" <<'PYEOF'
import sys, json, yaml
data = yaml.safe_load(open(sys.argv[1]).read())
open(sys.argv[2], 'w').write(json.dumps(data, default=str))
PYEOF
    printf '%s' "${profile_json}"
}

# ---------------------------------------------------------------------------
# Helper: create minimal content files for all required artifact inputs
# ---------------------------------------------------------------------------
make_inputs() {
    local d="${1:-${TMP_BASE}}"
    printf '## Change Plan\n\n1. Apply MTU change.\n2. Verify reachability.\n' > "${d}/change-plan.md"
    printf '## Diff Review\n\nRisk: Low. Single-line change.\n' > "${d}/diff-review.md"
    printf '## Blast Radius\n\n**Impact level:** medium\n\nAffected: dc1-edge-01.\n' > "${d}/blast-radius.md"
    printf '## Rollback Plan\n\n1. Revert MTU to 1500.\n2. Verify.\n' > "${d}/rollback.md"
    printf '[{"id":"PRE-01","source":"yci","category":"connectivity","description":"Ping test"}]\n' > "${d}/pre-checks.json"
    printf '[{"id":"POST-01","source":"yci","category":"connectivity","description":"Verify MTU"}]\n' > "${d}/post-checks.json"
}

# ---------------------------------------------------------------------------
# Helper: create a minimal valid evidence stub YAML
# Prints the path to the stub file.
# ---------------------------------------------------------------------------
make_evidence_stub() {
    local dest="${1:-${TMP_BASE}/evidence-stub.yaml}"
    cat > "${dest}" <<'YAML'
---
schema_version: commercial/1
change_id: a3f1b2c4-20260421-1430
change_summary: Adjust MTU on dc1-edge-01 to 9000
customer_id: widget-corp
profile_commit: d4e5f6a7
yci_commit: 78e907b3
timestamp_utc: "2026-04-21T14:30:00Z"
approver: _pending_
compliance_regime: commercial
rollback_plan_path: rollback/dc1-edge-01-reverse.yaml
pre_check_artifacts: []
post_check_artifacts: []
blast_radius_label: medium
rollback_confidence: high
---
YAML
    printf '%s' "${dest}"
}

# ---------------------------------------------------------------------------
# Helper: invoke render-artifact.sh with widget-corp fixture inputs.
# Usage: run_render <rollback_confidence> <output_path> [extra flags...]
# Returns the exit code of the renderer.
# ---------------------------------------------------------------------------
run_render() {
    local confidence="${1}"; local out="${2}"; shift 2
    mkdir -p "${TMP_BASE}/profiles"
    cp "${FIXTURE_PROFILE_YAML}" "${TMP_BASE}/profiles/widget-corp.yaml"
    CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
    YCI_DATA_ROOT_RESOLVED="${TMP_BASE}" \
    YCI_ACTIVE_CUSTOMER="widget-corp" \
    "${RENDER}" \
        --profile        "${TMP_BASE}/profile.json" \
        --adapter-dir    "${ADAPTER_DIR}" \
        --change-plan    "${TMP_BASE}/change-plan.md" \
        --diff-review    "${TMP_BASE}/diff-review.md" \
        --blast-radius-markdown "${TMP_BASE}/blast-radius.md" \
        --rollback       "${TMP_BASE}/rollback.md" \
        --rollback-confidence "${confidence}" \
        --pre-check-catalog   "${TMP_BASE}/pre-checks.json" \
        --post-check-catalog  "${TMP_BASE}/post-checks.json" \
        --evidence-stub  "${TMP_BASE}/evidence-stub.yaml" \
        --output         "${out}" \
        "$@" \
    >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# test_happy_path_widget_corp
# ---------------------------------------------------------------------------

test_happy_path_widget_corp() {
    setup_tmp

    make_profile_json "${TMP_BASE}" > /dev/null
    cp "${FIXTURE_HEADER}" "${TMP_BASE}/widget-corp-header.md"
    make_inputs "${TMP_BASE}"
    make_evidence_stub "${TMP_BASE}/evidence-stub.yaml" > /dev/null

    local out="${TMP_BASE}/artifact.md"
    local rc
    run_render high "${out}"
    rc=$?
    assert_exit_code 0 "$rc" "happy-path: render-artifact exits 0"

    assert_file_exists "${out}" "happy-path: output file exists"

    local content
    content="$(cat "${out}" 2>/dev/null || true)"
    local line_count
    line_count="$(wc -l < "${out}" 2>/dev/null || printf 0)"
    if [[ "${line_count}" -gt 20 ]]; then
        _yci_test_report PASS "happy-path: output > 20 lines"
    else
        _yci_test_report FAIL "happy-path: output > 20 lines" "got ${line_count} lines"
    fi

    assert_contains "**Prepared for Widget Corp**" "${content}" \
        "happy-path: customer-brand marker present"
    assert_contains "## Prepared by" "${content}" \
        "happy-path: consultant-brand marker present"

    # No unfilled {{...}} slots
    local unfilled
    unfilled="$(printf '%s' "${content}" | grep -oE '\{\{[^}]+\}\}' | head -1 || true)"
    if [[ -z "${unfilled}" ]]; then
        _yci_test_report PASS "happy-path: no unfilled slot markers"
    else
        _yci_test_report FAIL "happy-path: no unfilled slot markers" "found: ${unfilled}"
    fi

    # Section headings from artifact-template.md
    for heading in \
        "# Network Change Review" \
        "## Change Summary" \
        "## Change Plan" \
        "## Diff Review" \
        "## Blast Radius" \
        "## Rollback Plan" \
        "## Pre-Change Check Catalog" \
        "## Post-Change Check Catalog" \
        "## Evidence Stub"
    do
        assert_contains "${heading}" "${content}" "happy-path: heading '${heading}'"
    done

    teardown_tmp
}

# ---------------------------------------------------------------------------
# test_rollback_confidence_low
# ---------------------------------------------------------------------------

test_rollback_confidence_low() {
    setup_tmp

    make_profile_json "${TMP_BASE}" > /dev/null
    cp "${FIXTURE_HEADER}" "${TMP_BASE}/widget-corp-header.md"
    make_inputs "${TMP_BASE}"
    make_evidence_stub "${TMP_BASE}/evidence-stub.yaml" > /dev/null

    local out="${TMP_BASE}/artifact-low.md"
    local rc
    run_render low "${out}"
    rc=$?
    assert_exit_code 0 "$rc" "rollback-low: render-artifact exits 0"

    local content
    content="$(cat "${out}" 2>/dev/null || true)"

    # render-artifact.sh emits:
    #   > **⚠ Rollback Confidence: low**
    # when rollback_confidence is low or medium.
    if printf '%s' "${content}" | grep -qE '⚠|Rollback Confidence: low'; then
        _yci_test_report PASS "rollback-low: warning callout block present"
    else
        _yci_test_report FAIL "rollback-low: warning callout block present" \
            "expected ⚠ or 'Rollback Confidence: low' in output"
    fi

    teardown_tmp
}

# ---------------------------------------------------------------------------
# test_rollback_confidence_high
# ---------------------------------------------------------------------------

test_rollback_confidence_high() {
    setup_tmp

    make_profile_json "${TMP_BASE}" > /dev/null
    cp "${FIXTURE_HEADER}" "${TMP_BASE}/widget-corp-header.md"
    make_inputs "${TMP_BASE}"
    make_evidence_stub "${TMP_BASE}/evidence-stub.yaml" > /dev/null

    local out="${TMP_BASE}/artifact-high.md"
    local rc
    run_render high "${out}"
    rc=$?
    assert_exit_code 0 "$rc" "rollback-high: render-artifact exits 0"

    local content
    content="$(cat "${out}" 2>/dev/null || true)"

    # For high confidence the callout block should be absent.
    if ! printf '%s' "${content}" | grep -qE '⚠|Rollback Confidence: (low|medium)'; then
        _yci_test_report PASS "rollback-high: no warning callout block"
    else
        _yci_test_report FAIL "rollback-high: no warning callout block" \
            "unexpected callout found"
    fi

    teardown_tmp
}

# ---------------------------------------------------------------------------
# test_missing_branding_template
# ---------------------------------------------------------------------------

test_missing_branding_template() {
    setup_tmp

    # Build a profile.json that points header_template to a nonexistent file.
    local profile_json="${TMP_BASE}/profile.json"
    python3 - "${FIXTURE_PROFILE_YAML}" "${profile_json}" <<'PYEOF'
import sys, json, yaml
data = yaml.safe_load(open(sys.argv[1]).read())
data['deliverable']['header_template'] = '/nonexistent/path/no-such-header.md'
open(sys.argv[2], 'w').write(json.dumps(data, default=str))
PYEOF

    make_inputs "${TMP_BASE}"
    make_evidence_stub "${TMP_BASE}/evidence-stub.yaml" > /dev/null

    local out="${TMP_BASE}/artifact-bad-header.md"
    local stderr_out rc
    set +e
    stderr_out="$(
        CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
        "${RENDER}" \
            --profile        "${profile_json}" \
            --adapter-dir    "${ADAPTER_DIR}" \
            --change-plan    "${TMP_BASE}/change-plan.md" \
            --diff-review    "${TMP_BASE}/diff-review.md" \
            --blast-radius-markdown "${TMP_BASE}/blast-radius.md" \
            --rollback       "${TMP_BASE}/rollback.md" \
            --rollback-confidence high \
            --pre-check-catalog   "${TMP_BASE}/pre-checks.json" \
            --post-check-catalog  "${TMP_BASE}/post-checks.json" \
            --evidence-stub  "${TMP_BASE}/evidence-stub.yaml" \
            --output         "${out}" \
        2>&1 >/dev/null
    )"
    rc=$?
    set -e

    assert_exit 6 "${rc}" "missing-header: exits 6"
    assert_contains "ncr-branding-template-missing" "${stderr_out}" \
        "missing-header: stderr contains ncr-branding-template-missing"

    teardown_tmp
}

# ---------------------------------------------------------------------------
# test_inline_branding_string
# ---------------------------------------------------------------------------

test_inline_branding_string() {
    setup_tmp

    # Build a profile.json with an inline markdown string (no / or .md suffix).
    local inline_brand="Inline Widget Brand Consulting Engagement 2026"
    local profile_json="${TMP_BASE}/profile.json"
    python3 - "${FIXTURE_PROFILE_YAML}" "${profile_json}" "${inline_brand}" <<'PYEOF'
import sys, json, yaml
data = yaml.safe_load(open(sys.argv[1]).read())
data['deliverable']['header_template'] = sys.argv[3]
open(sys.argv[2], 'w').write(json.dumps(data, default=str))
PYEOF

    make_inputs "${TMP_BASE}"
    make_evidence_stub "${TMP_BASE}/evidence-stub.yaml" > /dev/null

    local out="${TMP_BASE}/artifact-inline.md"

    mkdir -p "${TMP_BASE}/profiles"
    cp "${FIXTURE_PROFILE_YAML}" "${TMP_BASE}/profiles/widget-corp.yaml"
    local rc
    set +e
    CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
    YCI_DATA_ROOT_RESOLVED="${TMP_BASE}" \
    YCI_ACTIVE_CUSTOMER="widget-corp" \
    "${RENDER}" \
        --profile        "${profile_json}" \
        --adapter-dir    "${ADAPTER_DIR}" \
        --change-plan    "${TMP_BASE}/change-plan.md" \
        --diff-review    "${TMP_BASE}/diff-review.md" \
        --blast-radius-markdown "${TMP_BASE}/blast-radius.md" \
        --rollback       "${TMP_BASE}/rollback.md" \
        --rollback-confidence high \
        --pre-check-catalog   "${TMP_BASE}/pre-checks.json" \
        --post-check-catalog  "${TMP_BASE}/post-checks.json" \
        --evidence-stub  "${TMP_BASE}/evidence-stub.yaml" \
        --output         "${out}" \
    >/dev/null 2>&1
    rc=$?
    set -e
    assert_exit_code 0 "$rc" "inline-brand: render-artifact exits 0"

    local content
    content="$(cat "${out}" 2>/dev/null || true)"

    assert_contains "${inline_brand}" "${content}" \
        "inline-brand: output embeds inline brand string"

    teardown_tmp
}

# ---------------------------------------------------------------------------
# test_missing_output_flag
# ---------------------------------------------------------------------------

test_missing_output_flag() {
    setup_tmp

    make_profile_json "${TMP_BASE}" > /dev/null
    cp "${FIXTURE_HEADER}" "${TMP_BASE}/widget-corp-header.md"
    make_inputs "${TMP_BASE}"
    make_evidence_stub "${TMP_BASE}/evidence-stub.yaml" > /dev/null

    local stderr_out rc
    set +e
    stderr_out="$(
        CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
        "${RENDER}" \
            --profile        "${TMP_BASE}/profile.json" \
            --adapter-dir    "${ADAPTER_DIR}" \
            --change-plan    "${TMP_BASE}/change-plan.md" \
            --diff-review    "${TMP_BASE}/diff-review.md" \
            --blast-radius-markdown "${TMP_BASE}/blast-radius.md" \
            --rollback       "${TMP_BASE}/rollback.md" \
            --rollback-confidence high \
            --pre-check-catalog   "${TMP_BASE}/pre-checks.json" \
            --post-check-catalog  "${TMP_BASE}/post-checks.json" \
            --evidence-stub  "${TMP_BASE}/evidence-stub.yaml" \
        2>&1 >/dev/null
    )"
    rc=$?
    set -e

    if [[ "${rc}" -ne 0 ]]; then
        _yci_test_report PASS "missing-output: exits non-zero"
    else
        _yci_test_report FAIL "missing-output: exits non-zero" "got exit 0"
    fi

    if [[ -n "${stderr_out}" ]]; then
        _yci_test_report PASS "missing-output: friendly error on stderr"
    else
        _yci_test_report FAIL "missing-output: friendly error on stderr" "stderr was empty"
    fi

    teardown_tmp
}

# ---------------------------------------------------------------------------
# test_evidence_stub_embedded — artifact-template.md embeds {{evidence_stub}} as-is
# ---------------------------------------------------------------------------

test_evidence_stub_embedded() {
    setup_tmp

    make_profile_json "${TMP_BASE}" > /dev/null
    cp "${FIXTURE_HEADER}" "${TMP_BASE}/widget-corp-header.md"
    make_inputs "${TMP_BASE}"
    make_evidence_stub "${TMP_BASE}/evidence-stub.yaml" > /dev/null

    local out="${TMP_BASE}/artifact-stub-check.md"
    local rc
    run_render high "${out}"
    rc=$?
    assert_exit_code 0 "$rc" "evidence-stub: render-artifact exits 0"

    local content
    content="$(cat "${out}" 2>/dev/null || true)"

    assert_contains "## Evidence Stub" "${content}" "evidence-stub: section heading present"
    assert_contains "<details>" "${content}" "evidence-stub: collapsible details block present"
    assert_contains "change_id:" "${content}" "evidence-stub: stub YAML content embedded in artifact"

    teardown_tmp
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

main() {
    test_happy_path_widget_corp
    test_rollback_confidence_low
    test_rollback_confidence_high
    test_missing_branding_template
    test_inline_branding_string
    test_missing_output_flag
    test_evidence_stub_embedded
    yci_test_summary
}

main
