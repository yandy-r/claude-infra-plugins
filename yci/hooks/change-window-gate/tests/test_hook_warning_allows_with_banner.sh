#!/usr/bin/env bash
# End-to-end: warning.ics profile + Write → allow + stderr [WARNING] banner.
# shellcheck disable=SC1091
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

WARNING_FIXTURE="$(fixture_path "warning.ics")"

# ---------------------------------------------------------------------------
# Test: Write at ts 30 min before warning event → allow + stderr [WARNING]
# warning.ics event starts at 13:00Z; ts 12:30Z is 30 min before (within 60-min warn)
# We use YCI_CWG_TS envvar... wait, pretool.sh doesn't have a TS envvar.
# The hook uses current time. We need to fake the window decision.
# Strategy: use a warning.ics file whose event starts >60 min from now but
# the test overrides the ts via sourcing window-decision directly, OR
# we use the json-schedule fixture with a warning.schedule.json whose
# blackout starts at a time we can engineer.
#
# The hook's pretool.sh calls cwg_decide which calls date -u at the current
# time. Since we can't inject a timestamp into pretool.sh directly, we'll
# test warning via the warning.schedule.json with a blackout that starts
# exactly 30 minutes from "right now".
#
# A simpler approach: Use a fixture where the warning event is far enough
# in the past that we KNOW the decision will be "warning" for our test ts,
# but the hook uses real time. So we craft a fixture dynamically.
# ---------------------------------------------------------------------------

test_warning_allows_with_banner() {
    local sb="$1"
    local sandbox="${sb}/data"
    mkdir -p "${sandbox}/profiles"

    # Craft a warning.schedule.json whose blackout starts 30 min from now
    local now_plus_30
    now_plus_30="$(python3 -c "
from datetime import datetime, timedelta, UTC
t = datetime.now(UTC) + timedelta(minutes=30)
print(t.strftime('%Y-%m-%dT%H:%M:%SZ'))
")"
    local now_plus_90
    now_plus_90="$(python3 -c "
from datetime import datetime, timedelta, UTC
t = datetime.now(UTC) + timedelta(minutes=90)
print(t.strftime('%Y-%m-%dT%H:%M:%SZ'))
")"

    local dynamic_schedule="${sandbox}/warning-dynamic.json"
    python3 -c "
import json, sys
data = {
    'timezone': 'UTC',
    'warn_before_minutes': 60,
    'blackouts': [{
        'start': sys.argv[1],
        'end': sys.argv[2],
        'label': 'Upcoming maintenance (synthetic dynamic)'
    }]
}
print(json.dumps(data))
" "$now_plus_30" "$now_plus_90" > "$dynamic_schedule"

    write_profile_yaml "$sandbox" "widgetco-test" "json-schedule" "$dynamic_schedule" "UTC"
    export YCI_DATA_ROOT="$sandbox"
    export YCI_CUSTOMER="widgetco-test"
    unset YCI_CWG_OVERRIDE YCI_CWG_DRY_RUN

    local payload='{"tool_name":"Write","tool_input":{"file_path":"/tmp/output.txt"}}'

    local out_file err_file rc=0
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    printf '%s' "$payload" | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" \
        >"$out_file" 2>"$err_file" || rc=$?

    local out err
    out="$(< "$out_file")"
    err="$(< "$err_file")"
    rm -f "$out_file" "$err_file"

    assert_exit 0 "$rc" "warning: exit 0 (allow)"
    assert_eq "$out" "" "warning: stdout empty (allow)"
    assert_contains "$err" "[WARNING]" "warning: stderr has [WARNING] banner"

    unset YCI_CUSTOMER
    teardown_test_sandbox "$sandbox"
}

# ---------------------------------------------------------------------------
with_sandbox test_warning_allows_with_banner

yci_test_summary
