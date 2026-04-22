#!/usr/bin/env bash
# Direct adapter invocations for the ical change-window adapter.
# shellcheck disable=SC1091
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ICAL_CHECK="${CLAUDE_PLUGIN_ROOT}/skills/_shared/change-window-adapters/ical/scripts/check.sh"

BLOCKED_FIXTURE="$(fixture_path "blocked.ics")"
OPEN_FIXTURE="$(fixture_path "open.ics")"
WARNING_FIXTURE="$(fixture_path "warning.ics")"
TZID_FIXTURE="$(fixture_path "blocked-tzid.ics")"

# ---------------------------------------------------------------------------
# Test: ts inside blocked window → blocked with SUMMARY in rationale
# ---------------------------------------------------------------------------
test_ical_ts_blocked() {
    local out rc
    out="$("$ICAL_CHECK" --ts "2026-04-22T12:00:00Z" --source "$BLOCKED_FIXTURE" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "ical blocked: exit 0"
    assert_decision "$out" "blocked" "ical blocked: decision=blocked"
    assert_decision_contains "$out" "Production freeze" "ical blocked: SUMMARY in rationale"
}

# ---------------------------------------------------------------------------
# Test: ts 30 min before 60-min warn window → warning
# ---------------------------------------------------------------------------
test_ical_ts_warning() {
    local out rc
    # warning.ics has event at 13:00Z; ts 12:30Z is 30 min before (within 60-min warn)
    out="$("$ICAL_CHECK" --ts "2026-04-22T12:30:00Z" --source "$WARNING_FIXTURE" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "ical warning: exit 0"
    assert_decision "$out" "warning" "ical warning: decision=warning"
    assert_decision_contains "$out" "Upcoming maintenance" "ical warning: SUMMARY in rationale"
}

# ---------------------------------------------------------------------------
# Test: ts well outside any event → allowed
# ---------------------------------------------------------------------------
test_ical_ts_allowed() {
    local out rc
    # open.ics has event at 2030-01-01; ts 2026-04-22 is well outside
    out="$("$ICAL_CHECK" --ts "2026-04-22T12:00:00Z" --source "$OPEN_FIXTURE" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "ical allowed: exit 0"
    assert_decision "$out" "allowed" "ical allowed: decision=allowed"
}

# ---------------------------------------------------------------------------
# Test: malformed .ics → exit 2
# ---------------------------------------------------------------------------
test_ical_malformed() {
    local sb="$1"
    local bad_ics="${sb}/bad.ics"
    # Write a truly malformed ICS (bad DTSTART format triggers parse error)
    cat > "$bad_ics" <<'EOF'
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
DTSTART:NOT-A-DATE
DTEND:ALSO-NOT-A-DATE
SUMMARY:Malformed event
END:VEVENT
END:VCALENDAR
EOF
    local rc=0
    "$ICAL_CHECK" --ts "2026-04-22T12:00:00Z" --source "$bad_ics" >/dev/null 2>&1 || rc=$?
    assert_exit 2 "$rc" "ical malformed: exit 2"
}

# ---------------------------------------------------------------------------
test_ical_missing_dtstart_is_error() {
    local sb="$1"
    local bad_ics="${sb}/missing-dtstart.ics"
    cat > "$bad_ics" <<'EOF'
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
DTEND:20260422T130000Z
SUMMARY:Missing start
END:VEVENT
END:VCALENDAR
EOF
    local rc=0
    "$ICAL_CHECK" --ts "2026-04-22T12:00:00Z" --source "$bad_ics" >/dev/null 2>&1 || rc=$?
    assert_exit 2 "$rc" "ical missing DTSTART: exit 2"
}

# ---------------------------------------------------------------------------
test_ical_monthly_rrule_falls_back_to_single_dtstart() {
    local sb="$1"
    local monthly_ics="${sb}/monthly.ics"
    cat > "$monthly_ics" <<'EOF'
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
DTSTART:20260401T120000Z
DTEND:20260401T130000Z
RRULE:FREQ=MONTHLY;COUNT=3
SUMMARY:Monthly fallback
END:VEVENT
END:VCALENDAR
EOF
    local out rc
    out="$("$ICAL_CHECK" --ts "2026-04-22T12:00:00Z" --source "$monthly_ics" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "ical monthly fallback: exit 0"
    assert_decision "$out" "allowed" "ical monthly fallback: decision=allowed"
}

# ---------------------------------------------------------------------------
test_ical_interval_rrule_falls_back_to_single_dtstart() {
    local sb="$1"
    local interval_ics="${sb}/interval.ics"
    cat > "$interval_ics" <<'EOF'
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
DTSTART:20260420T120000Z
DTEND:20260420T130000Z
RRULE:FREQ=DAILY;INTERVAL=2;COUNT=3
SUMMARY:Interval fallback
END:VEVENT
END:VCALENDAR
EOF
    local out rc
    out="$("$ICAL_CHECK" --ts "2026-04-21T12:30:00Z" --source "$interval_ics" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "ical interval fallback: exit 0"
    assert_decision "$out" "allowed" "ical interval fallback: decision=allowed"
}

# ---------------------------------------------------------------------------
# Test: TZID=America/Chicago boundary
# blocked-tzid.ics: event 09:00-17:00 Central = 14:00-22:00 UTC
# ts 16:00 UTC = inside the Central window → blocked
# ---------------------------------------------------------------------------
test_ical_tzid_boundary() {
    local out rc
    # 16:00 UTC = 11:00 Chicago; event is 14:00-22:00 UTC → blocked
    out="$("$ICAL_CHECK" --ts "2026-04-22T16:00:00Z" --source "$TZID_FIXTURE" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "ical tzid: exit 0"
    assert_decision "$out" "blocked" "ical tzid: 16:00Z inside 14:00-22:00Z window → blocked"
    assert_decision_contains "$out" "Central timezone" "ical tzid: SUMMARY in rationale"
}

# ---------------------------------------------------------------------------
# Test: ts before Central window (outside 14:00-22:00 UTC) → allowed
# ---------------------------------------------------------------------------
test_ical_tzid_outside() {
    local out rc
    # 12:00 UTC is before the 14:00Z start → allowed
    out="$("$ICAL_CHECK" --ts "2026-04-22T12:00:00Z" --source "$TZID_FIXTURE" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "ical tzid outside: exit 0"
    assert_decision "$out" "allowed" "ical tzid outside: 12:00Z before 14:00Z start → allowed"
}

# ---------------------------------------------------------------------------
test_ical_missing_ts_is_usage_error() {
    local rc=0
    "$ICAL_CHECK" --source "$BLOCKED_FIXTURE" >/dev/null 2>&1 || rc=$?
    assert_exit 1 "$rc" "ical missing ts: exit 1"
}

# ---------------------------------------------------------------------------
with_sandbox test_ical_ts_blocked
with_sandbox test_ical_ts_warning
with_sandbox test_ical_ts_allowed
with_sandbox test_ical_malformed
with_sandbox test_ical_missing_dtstart_is_error
with_sandbox test_ical_monthly_rrule_falls_back_to_single_dtstart
with_sandbox test_ical_interval_rrule_falls_back_to_single_dtstart
with_sandbox test_ical_tzid_boundary
with_sandbox test_ical_tzid_outside
with_sandbox test_ical_missing_ts_is_usage_error

yci_test_summary
