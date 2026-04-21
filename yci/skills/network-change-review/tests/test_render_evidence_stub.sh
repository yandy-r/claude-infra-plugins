#!/usr/bin/env bash
# yci network-change-review — render-evidence-stub.sh tests

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Source local helpers.sh (established API for this skill).
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/helpers.sh"

RENDER="${SKILL_ROOT_SCRIPTS}/render-evidence-stub.sh"
FIXTURE_PROFILE_YAML="${FIXTURES_ROOT}/profiles/widget-corp.yaml"

# 14 required fields from evidence-stub-schema.md
REQUIRED_FIELDS=(
    schema_version
    change_id
    change_summary
    customer_id
    profile_commit
    yci_commit
    timestamp_utc
    approver
    compliance_regime
    rollback_plan_path
    pre_check_artifacts
    post_check_artifacts
    blast_radius_label
    rollback_confidence
)

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
# Helper: build profile.json from widget-corp.yaml
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
# Helper: build a minimal change.json
# ---------------------------------------------------------------------------
make_change_json() {
    local dest="${1:-${TMP_BASE}/change.json}"
    python3 - "${dest}" <<'PYEOF'
import json, sys
data = {
    "raw": "interface GigabitEthernet0/0\n mtu 9000",
    "summary": "Adjust MTU on dc1-edge-01 to 9000",
    "device": "dc1-edge-01",
    "diff_type": "unified"
}
open(sys.argv[1], 'w').write(json.dumps(data))
PYEOF
    printf '%s' "${dest}"
}

# ---------------------------------------------------------------------------
# Helper: build a blast-radius label.json
# ---------------------------------------------------------------------------
make_label_json() {
    local label="${1:-medium}"
    local dest="${2:-${TMP_BASE}/label.json}"
    python3 -c "import json,sys; open(sys.argv[1],'w').write(json.dumps({'label': sys.argv[2], 'impact_level': sys.argv[2]}))" \
        "${dest}" "${label}"
    printf '%s' "${dest}"
}

# ---------------------------------------------------------------------------
# Helper: strip YAML --- fences and return the body
# ---------------------------------------------------------------------------
strip_yaml_fences() {
    python3 -c "
import re, sys
text = sys.argv[1]
text = re.sub(r'^---\s*\n', '', text, count=1)
text = re.sub(r'\n---\s*$', '', text)
print(text)
" "${1}"
}

# ---------------------------------------------------------------------------
# Helper: extract a field value from parsed YAML (prints value as string)
# ---------------------------------------------------------------------------
yaml_field() {
    local yaml_text="${1}" field="${2}"
    python3 - "${yaml_text}" "${field}" <<'PYEOF'
import yaml, sys
d = yaml.safe_load(sys.argv[1]) or {}
v = d.get(sys.argv[2], '')
if isinstance(v, list):
    print(repr(v))
else:
    print(v if v is not None else '')
PYEOF
}

# ---------------------------------------------------------------------------
# Helper: assert YAML parses successfully
# ---------------------------------------------------------------------------
assert_yaml_valid() {
    local text="${1}" name="${2:-assert_yaml_valid}"
    if python3 -c "import yaml, sys; yaml.safe_load(sys.argv[1])" "${text}" 2>/dev/null; then
        _yci_test_report PASS "${name}"
    else
        _yci_test_report FAIL "${name}" "YAML parse failed"
    fi
}

# ---------------------------------------------------------------------------
# test_happy_path
# ---------------------------------------------------------------------------

test_happy_path() {
    setup_tmp

    local profile_json
    profile_json="$(make_profile_json "${TMP_BASE}")"
    local change_json
    change_json="$(make_change_json "${TMP_BASE}/change.json")"
    local label_json
    label_json="$(make_label_json medium "${TMP_BASE}/label.json")"

    local output rc
    output="$(
        CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
        "${RENDER}" \
            --profile               "${profile_json}" \
            --change                "${change_json}" \
            --blast-radius-label    "${label_json}" \
            --rollback-confidence   high \
            --rollback-plan-path    rollback/dc1-edge-01-reverse.yaml \
        2>/dev/null
    )"
    rc=$?

    assert_exit 0 "${rc}" "happy-path: exits 0"

    local yaml_body
    yaml_body="$(strip_yaml_fences "${output}" 2>/dev/null || true)"

    assert_yaml_valid "${yaml_body}" "happy-path: YAML parses successfully"

    # All 14 required fields present and non-empty
    for field in "${REQUIRED_FIELDS[@]}"; do
        local val
        val="$(yaml_field "${yaml_body}" "${field}" 2>/dev/null || true)"
        if [[ -n "${val}" ]]; then
            _yci_test_report PASS "happy-path: field '${field}' present"
        else
            _yci_test_report FAIL "happy-path: field '${field}' present" \
                "field is empty or missing"
        fi
    done

    # approver == "_pending_"
    local approver
    approver="$(yaml_field "${yaml_body}" "approver" 2>/dev/null || true)"
    assert_eq "${approver}" "_pending_" "happy-path: approver == _pending_"

    # schema_version == "commercial/1" for commercial regime
    local schema_version
    schema_version="$(yaml_field "${yaml_body}" "schema_version" 2>/dev/null || true)"
    assert_eq "${schema_version}" "commercial/1" "happy-path: schema_version == commercial/1"

    # change_id matches pattern ^[a-f0-9]{8}-[0-9]{8}-[0-9]{4}$
    local change_id
    change_id="$(yaml_field "${yaml_body}" "change_id" 2>/dev/null || true)"
    if python3 -c "
import re, sys
sys.exit(0 if re.match(r'^[a-f0-9]{8}-[0-9]{8}-[0-9]{4}$', sys.argv[1]) else 1)
" "${change_id}" 2>/dev/null; then
        _yci_test_report PASS "happy-path: change_id matches pattern"
    else
        _yci_test_report FAIL "happy-path: change_id matches pattern" \
            "got: '${change_id}'"
    fi

    # timestamp_utc parseable as ISO8601
    local ts
    ts="$(yaml_field "${yaml_body}" "timestamp_utc" 2>/dev/null || true)"
    if python3 -c "
import datetime, sys
datetime.datetime.fromisoformat(sys.argv[1].rstrip('Z'))
" "${ts}" 2>/dev/null; then
        _yci_test_report PASS "happy-path: timestamp_utc is valid ISO8601"
    else
        _yci_test_report FAIL "happy-path: timestamp_utc is valid ISO8601" \
            "got: '${ts}'"
    fi

    # blast_radius_label matches the label from the input (medium)
    local brl
    brl="$(yaml_field "${yaml_body}" "blast_radius_label" 2>/dev/null || true)"
    assert_eq "${brl}" "medium" "happy-path: blast_radius_label == medium"

    # rollback_confidence matches the input flag (high)
    local rbc
    rbc="$(yaml_field "${yaml_body}" "rollback_confidence" 2>/dev/null || true)"
    assert_eq "${rbc}" "high" "happy-path: rollback_confidence == high"

    # pre_check_artifacts and post_check_artifacts are empty arrays
    local pre_arr
    pre_arr="$(yaml_field "${yaml_body}" "pre_check_artifacts" 2>/dev/null || true)"
    assert_eq "${pre_arr}" "[]" "happy-path: pre_check_artifacts == []"

    local post_arr
    post_arr="$(yaml_field "${yaml_body}" "post_check_artifacts" 2>/dev/null || true)"
    assert_eq "${post_arr}" "[]" "happy-path: post_check_artifacts == []"

    teardown_tmp
}

# ---------------------------------------------------------------------------
# test_profile_commit_inside_git_repo
# ---------------------------------------------------------------------------

test_profile_commit_inside_git_repo() {
    setup_tmp

    # profile.json lives inside TMP_BASE which is outside the repo; but we want
    # the profile to be in a directory that IS tracked by git.  We copy the
    # profile.json to a subdir of PLUGIN_ROOT (which is a git repo) so that
    # git rev-parse HEAD succeeds.
    local git_profile_dir="${PLUGIN_ROOT}/skills/network-change-review/tests/fixtures/profiles"
    local tmp_base_name
    tmp_base_name="$(basename "${TMP_BASE}")"
    local profile_json="${git_profile_dir}/../../../${tmp_base_name}-profile.json"
    # Simpler: build the JSON in TMP_BASE but then copy it into the git tree tmpfile.
    local tmp_profile_in_repo
    tmp_profile_in_repo="$(mktemp "${git_profile_dir}/tmp-profile-XXXXXXXX.json")"
    # Ensure cleanup even on early exit.
    # shellcheck disable=SC2064
    trap "rm -f '${tmp_profile_in_repo}'" RETURN

    python3 - "${FIXTURE_PROFILE_YAML}" "${tmp_profile_in_repo}" <<'PYEOF'
import sys, json, yaml
data = yaml.safe_load(open(sys.argv[1]).read())
open(sys.argv[2], 'w').write(json.dumps(data, default=str))
PYEOF

    local change_json
    change_json="$(make_change_json "${TMP_BASE}/change.json")"
    local label_json
    label_json="$(make_label_json high "${TMP_BASE}/label.json")"

    local output
    output="$(
        CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
        "${RENDER}" \
            --profile               "${tmp_profile_in_repo}" \
            --change                "${change_json}" \
            --blast-radius-label    "${label_json}" \
            --rollback-confidence   high \
            --rollback-plan-path    rollback/plan.yaml \
        2>/dev/null
    )" || true

    rm -f "${tmp_profile_in_repo}"

    local yaml_body
    yaml_body="$(strip_yaml_fences "${output}" 2>/dev/null || true)"

    local profile_commit
    profile_commit="$(yaml_field "${yaml_body}" "profile_commit" 2>/dev/null || true)"

    if [[ "${profile_commit}" != "unknown" && -n "${profile_commit}" ]]; then
        _yci_test_report PASS \
            "profile-commit-inside-repo: profile_commit is a real SHA"
    else
        _yci_test_report FAIL \
            "profile-commit-inside-repo: profile_commit is a real SHA" \
            "got: '${profile_commit}' (profile lives inside git repo)"
    fi

    teardown_tmp
}

# ---------------------------------------------------------------------------
# test_profile_commit_outside_git_repo
# ---------------------------------------------------------------------------

test_profile_commit_outside_git_repo() {
    setup_tmp

    # Copy the profile to a directory that is NOT a git repo.
    local outside_dir
    outside_dir="$(mktemp -d /tmp/ncr-outside-XXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -rf '${outside_dir}'" RETURN

    local profile_json="${outside_dir}/profile.json"
    python3 - "${FIXTURE_PROFILE_YAML}" "${profile_json}" <<'PYEOF'
import sys, json, yaml
data = yaml.safe_load(open(sys.argv[1]).read())
open(sys.argv[2], 'w').write(json.dumps(data, default=str))
PYEOF

    local change_json
    change_json="$(make_change_json "${TMP_BASE}/change.json")"
    local label_json
    label_json="$(make_label_json low "${TMP_BASE}/label.json")"

    local output
    output="$(
        CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
        "${RENDER}" \
            --profile               "${profile_json}" \
            --change                "${change_json}" \
            --blast-radius-label    "${label_json}" \
            --rollback-confidence   low \
            --rollback-plan-path    rollback/plan.yaml \
        2>/dev/null
    )" || true

    rm -rf "${outside_dir}"

    local yaml_body
    yaml_body="$(strip_yaml_fences "${output}" 2>/dev/null || true)"

    local profile_commit
    profile_commit="$(yaml_field "${yaml_body}" "profile_commit" 2>/dev/null || true)"

    assert_eq "${profile_commit}" "unknown" \
        "profile-commit-outside-repo: profile_commit == unknown"

    teardown_tmp
}

# ---------------------------------------------------------------------------
# test_missing_required_flag
# ---------------------------------------------------------------------------

test_missing_required_flag() {
    setup_tmp

    local change_json
    change_json="$(make_change_json "${TMP_BASE}/change.json")"
    local label_json
    label_json="$(make_label_json high "${TMP_BASE}/label.json")"

    # Omit --profile; expect non-zero exit and a friendly error on stderr.
    local stderr_out rc
    set +e
    stderr_out="$(
        CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
        "${RENDER}" \
            --change                "${change_json}" \
            --blast-radius-label    "${label_json}" \
            --rollback-confidence   high \
            --rollback-plan-path    rollback/plan.yaml \
        2>&1 >/dev/null
    )"
    rc=$?
    set -e

    if [[ "${rc}" -ne 0 ]]; then
        _yci_test_report PASS "missing-flag: exits non-zero"
    else
        _yci_test_report FAIL "missing-flag: exits non-zero" "got exit 0"
    fi

    if [[ -n "${stderr_out}" ]]; then
        _yci_test_report PASS "missing-flag: friendly error on stderr"
    else
        _yci_test_report FAIL "missing-flag: friendly error on stderr" "stderr was empty"
    fi

    teardown_tmp
}

# ---------------------------------------------------------------------------
# test_invalid_json_input
# ---------------------------------------------------------------------------

test_invalid_json_input() {
    setup_tmp

    local profile_json
    profile_json="$(make_profile_json "${TMP_BASE}")"

    # Write a malformed JSON file for --change.
    local bad_change="${TMP_BASE}/bad-change.json"
    printf '{not valid json at all' > "${bad_change}"

    local label_json
    label_json="$(make_label_json high "${TMP_BASE}/label.json")"

    local stderr_out rc
    set +e
    stderr_out="$(
        CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
        "${RENDER}" \
            --profile               "${profile_json}" \
            --change                "${bad_change}" \
            --blast-radius-label    "${label_json}" \
            --rollback-confidence   high \
            --rollback-plan-path    rollback/plan.yaml \
        2>&1 >/dev/null
    )"
    rc=$?
    set -e

    if [[ "${rc}" -ne 0 ]]; then
        _yci_test_report PASS "invalid-json: exits non-zero"
    else
        _yci_test_report FAIL "invalid-json: exits non-zero" "got exit 0"
    fi

    if [[ -n "${stderr_out}" ]]; then
        _yci_test_report PASS "invalid-json: error on stderr"
    else
        _yci_test_report FAIL "invalid-json: error on stderr" "stderr was empty"
    fi

    teardown_tmp
}

# ---------------------------------------------------------------------------
# test_output_routing
# ---------------------------------------------------------------------------

test_output_routing() {
    setup_tmp

    local profile_json
    profile_json="$(make_profile_json "${TMP_BASE}")"
    local change_json
    change_json="$(make_change_json "${TMP_BASE}/change.json")"
    local label_json
    label_json="$(make_label_json high "${TMP_BASE}/label.json")"

    # Capture stdout version.
    local stdout_output
    stdout_output="$(
        CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
        "${RENDER}" \
            --profile               "${profile_json}" \
            --change                "${change_json}" \
            --blast-radius-label    "${label_json}" \
            --rollback-confidence   high \
            --rollback-plan-path    rollback/plan.yaml \
        2>/dev/null
    )"

    # Run again with --output and verify the file.
    local out_file="${TMP_BASE}/stub-file.yaml"
    CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" \
    "${RENDER}" \
        --profile               "${profile_json}" \
        --change                "${change_json}" \
        --blast-radius-label    "${label_json}" \
        --rollback-confidence   high \
        --rollback-plan-path    rollback/plan.yaml \
        --output                "${out_file}" \
    >/dev/null 2>&1 || true

    assert_file_exists "${out_file}" "output-routing: file written"

    local file_content
    file_content="$(cat "${out_file}" 2>/dev/null || true)"

    if [[ -n "${stdout_output}" ]]; then
        _yci_test_report PASS "output-routing: stdout output non-empty"
    else
        _yci_test_report FAIL "output-routing: stdout output non-empty" "stdout was empty"
    fi

    if [[ -n "${file_content}" ]]; then
        _yci_test_report PASS "output-routing: file content non-empty"
    else
        _yci_test_report FAIL "output-routing: file content non-empty" "file was empty"
    fi

    assert_contains "schema_version" "${stdout_output}" \
        "output-routing: stdout contains schema_version"
    assert_contains "schema_version" "${file_content}" \
        "output-routing: file contains schema_version"

    teardown_tmp
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

main() {
    test_happy_path
    test_profile_commit_inside_git_repo
    test_profile_commit_outside_git_repo
    test_missing_required_flag
    test_invalid_json_input
    test_output_routing
    yci_test_summary
}

main
