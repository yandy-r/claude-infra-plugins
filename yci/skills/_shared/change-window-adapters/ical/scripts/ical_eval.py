#!/usr/bin/env python3
# yci — iCal change-window adapter: calendar evaluation logic.
#
# Accepts the same flags as check.sh (--ts, --source, --timezone,
# --warn-before-minutes), parses a local .ics file using a minimal
# RFC-5545-compliant line-folded parser (stdlib only), and emits a single
# JSON line on stdout with keys: decision, rationale, adapter, window_source.
#
# Exit codes:
#   0 — decision emitted
#   2 — adapter config error (source unreadable or malformed .ics)
#   3 — runtime error (zoneinfo unavailable or unexpected exception)

import argparse
import json
import re
import sys
from datetime import UTC, datetime, timedelta

# ---------------------------------------------------------------------------
# zoneinfo import — required. Fail fast with exit 3 if unavailable.
# ---------------------------------------------------------------------------
try:
    from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
except ImportError:
    print(
        "ical adapter: zoneinfo module not available (Python < 3.9 or tzdata missing)",
        file=sys.stderr,
    )
    sys.exit(3)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
ADAPTER_NAME = "ical"
LOOKAHEAD_DAYS = 14
LOOKBACK_DAYS = 14

# ---------------------------------------------------------------------------
# .ics line-folded parser
# ---------------------------------------------------------------------------


def _unfold_lines(text: str) -> list[str]:
    """Unfold RFC-5545 line-folded content lines into logical lines."""
    lines: list[str] = []
    for raw in text.splitlines():
        # A continuation line begins with a single SPACE or HTAB (RFC 5545 §3.1).
        if raw and raw[0] in (" ", "\t"):
            if lines:
                lines[-1] += raw[1:]
            else:
                # Continuation at start of file — keep as-is (defensive).
                lines.append(raw[1:])
        else:
            lines.append(raw)
    return lines


def _unescape_value(value: str) -> str:
    """Decode iCal text escapes: \\n -> newline, \\, -> comma, \\; -> semicolon."""
    value = re.sub(r"\\n", "\n", value)
    value = re.sub(r"\\,", ",", value)
    value = re.sub(r"\\;", ";", value)
    value = value.replace("\\\\", "\\")
    return value


def _percent_decode(value: str) -> str:
    """Percent-decode a string (handles %XX sequences)."""

    def _replace(m: re.Match) -> str:
        return chr(int(m.group(1), 16))

    return re.sub(r"%([0-9A-Fa-f]{2})", _replace, value)


def _decode_summary(raw: str) -> str:
    return _unescape_value(_percent_decode(raw))


# ---------------------------------------------------------------------------
# Date/time parsing helpers
# ---------------------------------------------------------------------------

_DATE_RE = re.compile(r"^(\d{4})(\d{2})(\d{2})$")
_DATETIME_LOCAL_RE = re.compile(r"^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})$")
_DATETIME_UTC_RE = re.compile(r"^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$")


def _parse_dt_value(
    value: str,
    tzid: str | None,
    fallback_tz_name: str,
    line_num: int,
) -> tuple[datetime, bool]:
    """
    Parse a DTSTART or DTEND value string into a UTC-aware datetime.

    Returns (utc_dt, is_all_day).

    Raises ValueError with a descriptive message on parse failure.
    """
    # Strip VALUE= prefix if present (e.g. VALUE=DATE:20260422 → 20260422).
    value = re.sub(r"^VALUE=DATE-TIME:", "", value, flags=re.IGNORECASE)
    value = re.sub(r"^VALUE=DATE:", "", value, flags=re.IGNORECASE)

    # UTC datetime: ends with Z.
    m = _DATETIME_UTC_RE.match(value)
    if m:
        yr, mo, dy, hh, mm, ss = (int(x) for x in m.groups())
        return datetime(yr, mo, dy, hh, mm, ss, tzinfo=UTC), False

    # Local datetime with TZID parameter.
    m = _DATETIME_LOCAL_RE.match(value)
    if m:
        yr, mo, dy, hh, mm, ss = (int(x) for x in m.groups())
        tz_name = tzid if tzid else fallback_tz_name
        try:
            tz = ZoneInfo(tz_name)
        except ZoneInfoNotFoundError as err:
            raise ValueError(f"zoneinfo: unknown timezone '{tz_name}' at line {line_num}") from err
        local_dt = datetime(yr, mo, dy, hh, mm, ss, tzinfo=tz)
        return local_dt.astimezone(UTC), False

    # All-day date: YYYYMMDD.
    m = _DATE_RE.match(value)
    if m:
        yr, mo, dy = (int(x) for x in m.groups())
        # Treat an all-day event as covering the full 24h day in UTC
        # (we use the fallback_tz_name for the start-of-day anchor).
        tz_name = tzid if tzid else fallback_tz_name
        try:
            tz = ZoneInfo(tz_name)
        except ZoneInfoNotFoundError as err:
            raise ValueError(f"zoneinfo: unknown timezone '{tz_name}' at line {line_num}") from err
        start = datetime(yr, mo, dy, 0, 0, 0, tzinfo=tz).astimezone(UTC)
        return start, True

    raise ValueError(f"unrecognised date/time value '{value}' at line {line_num}")


def _parse_property_line(line: str) -> tuple[str, dict[str, str], str]:
    """
    Split a logical iCal content line into (name, params, value).

    e.g. "DTSTART;TZID=America/Chicago:20260422T090000"
    → ("DTSTART", {"TZID": "America/Chicago"}, "20260422T090000")
    """
    # Property name is everything up to the first ':' or ';'.
    colon_pos = line.find(":")
    semi_pos = line.find(";")

    if colon_pos == -1:
        # Degenerate line — no colon. Treat whole line as name with empty value.
        return line.upper(), {}, ""

    if semi_pos != -1 and semi_pos < colon_pos:
        # Has parameters.
        name = line[:semi_pos].upper()
        param_str = line[semi_pos + 1 : colon_pos]
        value = line[colon_pos + 1 :]
        params: dict[str, str] = {}
        for part in param_str.split(";"):
            if "=" in part:
                k, _, v = part.partition("=")
                params[k.upper()] = v
        return name, params, value
    else:
        name = line[:colon_pos].upper()
        value = line[colon_pos + 1 :]
        return name, {}, value


# ---------------------------------------------------------------------------
# RRULE expansion helpers
# ---------------------------------------------------------------------------


def _parse_rrule(rrule_value: str) -> dict[str, str]:
    """Parse RRULE value string into a dict of RRULE parts."""
    parts: dict[str, str] = {}
    for segment in rrule_value.split(";"):
        if "=" in segment:
            k, _, v = segment.partition("=")
            parts[k.upper()] = v
    return parts


def _expand_rrule(
    dtstart_utc: datetime,
    rrule: dict[str, str],
    window_start: datetime,
    window_end: datetime,
    event_summary: str,
) -> list[datetime]:
    """
    Expand RRULE into occurrence datetimes within [window_start, window_end].

    Supports: FREQ=DAILY|WEEKLY|MONTHLY with COUNT or UNTIL.
    Unsupported modifiers (BYDAY, BYSETPOS, BYMONTH, BYMONTHDAY) trigger a
    stderr warning; occurrence expansion falls back to DTSTART only.
    """
    freq = rrule.get("FREQ", "").upper()
    if freq not in ("DAILY", "WEEKLY", "MONTHLY"):
        print(
            f"ical adapter: unsupported RRULE FREQ='{freq}' for event "
            f"'{event_summary}'; treating as single occurrence",
            file=sys.stderr,
        )
        return [dtstart_utc] if window_start <= dtstart_utc <= window_end else []

    unsupported_keys = {"BYDAY", "BYSETPOS", "BYMONTH", "BYMONTHDAY"}
    found_unsupported = unsupported_keys & set(rrule.keys())
    if found_unsupported:
        print(
            f"ical adapter: unsupported RRULE modifier(s) {sorted(found_unsupported)} "
            f"for event '{event_summary}'; treating as single occurrence",
            file=sys.stderr,
        )
        return [dtstart_utc] if window_start <= dtstart_utc <= window_end else []

    if freq == "DAILY":
        step = timedelta(days=1)
    elif freq == "WEEKLY":
        step = timedelta(weeks=1)
    else:  # MONTHLY — approximate 30-day step; acceptable within the 14-day lookahead window.
        step = timedelta(days=30)

    count_str = rrule.get("COUNT", "")
    until_str = rrule.get("UNTIL", "")

    max_count: int | None = int(count_str) if count_str else None
    until_dt: datetime | None = None
    if until_str:
        m = _DATETIME_UTC_RE.match(until_str)
        if m:
            yr, mo, dy, hh, mm, ss = (int(x) for x in m.groups())
            until_dt = datetime(yr, mo, dy, hh, mm, ss, tzinfo=UTC)
        else:
            m2 = _DATE_RE.match(until_str)
            if m2:
                yr, mo, dy = (int(x) for x in m2.groups())
                until_dt = datetime(yr, mo, dy, 23, 59, 59, tzinfo=UTC)

    occurrences: list[datetime] = []
    current = dtstart_utc
    iteration = 0
    # Guard against runaway expansion — cap at 10 000 iterations.
    while iteration < 10_000:
        if max_count is not None and iteration >= max_count:
            break
        if until_dt is not None and current > until_dt:
            break
        if current > window_end:
            break
        if current >= window_start:
            occurrences.append(current)
        current += step
        iteration += 1

    return occurrences


# ---------------------------------------------------------------------------
# .ics file parser — produces a list of events
# ---------------------------------------------------------------------------


class _Event:
    __slots__ = ("summary", "dtstart_utc", "dtend_utc", "rrule")

    def __init__(
        self,
        summary: str,
        dtstart_utc: datetime,
        dtend_utc: datetime,
        rrule: dict[str, str] | None,
    ) -> None:
        self.summary = summary
        self.dtstart_utc = dtstart_utc
        self.dtend_utc = dtend_utc
        self.rrule = rrule


def _parse_ics(source_path: str, fallback_tz_name: str) -> list[_Event]:
    """
    Parse a .ics file and return a list of _Event objects.

    Raises SystemExit(2) on malformed content, SystemExit(3) on zoneinfo errors.
    """
    try:
        with open(source_path, encoding="utf-8", errors="replace") as fh:
            raw = fh.read()
    except OSError as exc:
        print(f"ical adapter: cannot read source file: {exc}", file=sys.stderr)
        sys.exit(2)

    logical_lines = _unfold_lines(raw)
    events: list[_Event] = []

    in_vevent = False
    current: dict[str, object] = {}  # accumulates properties for the current VEVENT

    for line_num, line in enumerate(logical_lines, start=1):
        line = line.rstrip("\r")
        if not line:
            continue

        try:
            prop_name, params, value = _parse_property_line(line)
        except Exception:
            # Defensive: if the line cannot be parsed at all, skip it.
            continue

        if prop_name == "BEGIN" and value.upper() == "VEVENT":
            in_vevent = True
            current = {}
            continue

        if prop_name == "END" and value.upper() == "VEVENT":
            if in_vevent:
                # Attempt to build an _Event from accumulated properties.
                dtstart_raw = current.get("DTSTART_VALUE")
                dtend_raw = current.get("DTEND_VALUE")
                if dtstart_raw is None:
                    # DTSTART is required for VEVENT; skip malformed event.
                    print(
                        f"ical adapter: VEVENT near line {line_num} has no DTSTART; skipping",
                        file=sys.stderr,
                    )
                    in_vevent = False
                    current = {}
                    continue

                dtstart_tzid = current.get("DTSTART_TZID")  # type: ignore[assignment]
                dtend_tzid = current.get("DTEND_TZID")  # type: ignore[assignment]
                summary = str(current.get("SUMMARY", "(no summary)"))
                rrule_value = current.get("RRULE")

                try:
                    dtstart_utc, start_is_allday = _parse_dt_value(
                        str(dtstart_raw),
                        dtstart_tzid,  # type: ignore[arg-type]
                        fallback_tz_name,
                        line_num,
                    )
                except ValueError as exc:
                    print(
                        f"ical adapter: malformed .ics at line {line_num}: {exc}",
                        file=sys.stderr,
                    )
                    sys.exit(2)
                except ZoneInfoNotFoundError as exc:
                    print(
                        f"ical adapter: zoneinfo error at line {line_num}: {exc}",
                        file=sys.stderr,
                    )
                    sys.exit(3)

                if dtend_raw is not None:
                    try:
                        dtend_utc, _ = _parse_dt_value(
                            str(dtend_raw),
                            dtend_tzid,  # type: ignore[arg-type]
                            fallback_tz_name,
                            line_num,
                        )
                    except ValueError as exc:
                        print(
                            f"ical adapter: malformed .ics at line {line_num}: {exc}",
                            file=sys.stderr,
                        )
                        sys.exit(2)
                    except ZoneInfoNotFoundError as exc:
                        print(
                            f"ical adapter: zoneinfo error at line {line_num}: {exc}",
                            file=sys.stderr,
                        )
                        sys.exit(3)
                else:
                    # No DTEND: all-day events default to 24h; timed events to 0-duration.
                    dtend_utc = dtstart_utc + timedelta(days=1) if start_is_allday else dtstart_utc

                rrule: dict[str, str] | None = None
                if rrule_value is not None:
                    rrule = _parse_rrule(str(rrule_value))

                events.append(_Event(summary, dtstart_utc, dtend_utc, rrule))

            in_vevent = False
            current = {}
            continue

        if not in_vevent:
            continue

        # Inside a VEVENT — record recognised properties; skip unknown ones silently.
        if prop_name == "SUMMARY":
            current["SUMMARY"] = _decode_summary(value)
        elif prop_name == "DTSTART":
            # Handle VALUE=DATE: prefix embedded in params or in the value itself.
            if "VALUE" in params and params["VALUE"].upper() == "DATE":
                current["DTSTART_VALUE"] = "VALUE=DATE:" + value
            else:
                current["DTSTART_VALUE"] = value
            current["DTSTART_TZID"] = params.get("TZID")
        elif prop_name == "DTEND":
            if "VALUE" in params and params["VALUE"].upper() == "DATE":
                current["DTEND_VALUE"] = "VALUE=DATE:" + value
            else:
                current["DTEND_VALUE"] = value
            current["DTEND_TZID"] = params.get("TZID")
        elif prop_name == "RRULE":
            current["RRULE"] = value
        # All other properties (CATEGORIES, DESCRIPTION, X-*, etc.) are silently ignored.

    return events


# ---------------------------------------------------------------------------
# Decision logic
# ---------------------------------------------------------------------------


def _fmt_utc(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def evaluate(
    ts: datetime,
    events: list[_Event],
    warn_before_minutes: int,
    source_path: str,
) -> dict[str, str]:
    """
    Evaluate ts against expanded event occurrences and return a decision dict.
    """
    window_start = ts - timedelta(days=LOOKBACK_DAYS)
    window_end = ts + timedelta(days=LOOKAHEAD_DAYS)

    # Build list of (occurrence_start_utc, dtend_utc_for_occurrence, summary).
    # For recurring events, dtend is offset from dtstart by the original duration.
    occurrences: list[tuple[datetime, datetime, str]] = []

    for event in events:
        duration = event.dtend_utc - event.dtstart_utc
        if event.rrule:
            starts = _expand_rrule(
                event.dtstart_utc,
                event.rrule,
                window_start,
                window_end,
                event.summary,
            )
            for occ_start in starts:
                occurrences.append((occ_start, occ_start + duration, event.summary))
        else:
            # Single occurrence — include if it overlaps the window at all.
            if event.dtstart_utc <= window_end and event.dtend_utc >= window_start:
                occurrences.append((event.dtstart_utc, event.dtend_utc, event.summary))

    # Sort by start time for predictable rationale (first match wins).
    occurrences.sort(key=lambda t: t[0])

    warn_delta = timedelta(minutes=warn_before_minutes)

    # 1. Check if ts is covered by any event (blocked).
    for occ_start, occ_end, summary in occurrences:
        if occ_start <= ts < occ_end:
            rationale = f"{summary} ({_fmt_utc(occ_start)} .. {_fmt_utc(occ_end)})"
            return {
                "decision": "blocked",
                "rationale": rationale,
                "adapter": ADAPTER_NAME,
                "window_source": source_path,
            }

    # 2. Check if any event starts soon (warning).
    upcoming = [
        (occ_start, occ_end, summary)
        for occ_start, occ_end, summary in occurrences
        if ts <= occ_start <= ts + warn_delta
    ]
    if upcoming:
        occ_start, _occ_end, summary = upcoming[0]
        minutes_away = int((occ_start - ts).total_seconds() / 60)
        rationale = f"window opens at {_fmt_utc(occ_start)} ({minutes_away}m away): {summary}"
        return {
            "decision": "warning",
            "rationale": rationale,
            "adapter": ADAPTER_NAME,
            "window_source": source_path,
        }

    # 3. Allowed — find the next future event for context.
    future = [(occ_start, summary) for occ_start, _, summary in occurrences if occ_start > ts]
    if future:
        next_start, next_summary = future[0]
        rationale = f"no iCal event covers ts; next event: {_fmt_utc(next_start)} ({next_summary})"
    else:
        rationale = "no iCal event covers ts; next event: none in lookahead"

    return {
        "decision": "allowed",
        "rationale": rationale,
        "adapter": ADAPTER_NAME,
        "window_source": source_path,
    }


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="iCal change-window adapter — evaluate a timestamp against a .ics file.",
        add_help=True,
    )
    parser.add_argument("--ts", required=True, help="Proposed-change timestamp (UTC ISO-8601).")
    parser.add_argument("--source", required=True, help="Absolute path to the .ics file.")
    parser.add_argument(
        "--timezone", default="UTC", help="IANA timezone for rationale (default: UTC)."
    )
    parser.add_argument(
        "--warn-before-minutes",
        type=int,
        default=60,
        dest="warn_before_minutes",
        help="Warn when the next event starts within N minutes (default: 60).",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> None:
    if argv is None:
        argv = sys.argv[1:]

    args = _parse_args(argv)

    # Validate timezone (used only for rationale; errors still need to be caught early).
    try:
        ZoneInfo(args.timezone)
    except ZoneInfoNotFoundError:
        print(
            f"ical adapter: unknown timezone '{args.timezone}'",
            file=sys.stderr,
        )
        sys.exit(3)

    # Parse --ts.
    ts_str = args.ts
    try:
        # Accept trailing Z as UTC.
        if ts_str.endswith("Z"):
            ts = datetime.fromisoformat(ts_str[:-1]).replace(tzinfo=UTC)
        else:
            ts = datetime.fromisoformat(ts_str)
            ts = ts.replace(tzinfo=UTC) if ts.tzinfo is None else ts.astimezone(UTC)
    except ValueError as exc:
        print(f"ical adapter: invalid --ts value '{ts_str}': {exc}", file=sys.stderr)
        sys.exit(2)

    # Parse .ics file.
    events = _parse_ics(args.source, args.timezone)

    # Evaluate.
    result = evaluate(ts, events, args.warn_before_minutes, args.source)

    # Emit — exactly one compact JSON line.
    print(json.dumps(result, separators=(",", ":")))
    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001
        print(f"{type(exc).__name__}: {exc}", file=sys.stderr)
        sys.exit(3)
