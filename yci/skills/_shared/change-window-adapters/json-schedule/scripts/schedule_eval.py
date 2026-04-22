#!/usr/bin/env python3
# yci — JSON-schedule change-window adapter: evaluation logic.
#
# Minimum Python version: 3.11
#   - datetime.fromisoformat handles the full ISO-8601 range including the Z suffix.
#   - zoneinfo is stdlib (added in 3.9; Z handling in fromisoformat requires 3.11).
#
# Usage (invoked by check.sh):
#   schedule_eval.py --ts <iso8601-utc> --source <path>
#                    [--timezone <tz>] [--warn-before-minutes <int>]
#
# Exit codes:
#   0 — decision emitted
#   2 — source missing / malformed JSON / schema violation
#   3 — runtime error

import argparse
import json
import os
import sys
from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

ADAPTER_NAME = "json-schedule"
DEFAULT_WARN_BEFORE_MINUTES = 60


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _die(code: int, msg: str) -> None:
    """Print msg to stderr and exit with code."""
    print(msg, file=sys.stderr)
    sys.exit(code)


def _format_utc(dt: datetime) -> str:
    """Return a compact UTC string like 2026-04-22T14:00:00Z."""
    utc = dt.astimezone(UTC)
    return utc.strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------------------------------------------------------------------------
# Schema validation (stdlib only — no jsonschema dep)
# ---------------------------------------------------------------------------


def _validate_calendar(data: object, source_path: str) -> None:
    """Raise SystemExit(2) if data does not conform to the blackout-calendar schema."""
    if not isinstance(data, dict):
        _die(2, f"{ADAPTER_NAME} adapter: calendar file must be a JSON object: {source_path}")

    if "blackouts" not in data:
        _die(
            2,
            f"{ADAPTER_NAME} adapter: calendar file missing required key 'blackouts': {source_path}",
        )

    blackouts = data["blackouts"]
    if not isinstance(blackouts, list):
        _die(2, f"{ADAPTER_NAME} adapter: 'blackouts' must be a JSON array: {source_path}")

    for idx, entry in enumerate(blackouts):
        pointer = f"blackouts[{idx}]"
        if not isinstance(entry, dict):
            _die(2, f"{ADAPTER_NAME} adapter: {pointer} must be a JSON object: {source_path}")
        for req_key in ("start", "end"):
            if req_key not in entry:
                _die(
                    2,
                    f"{ADAPTER_NAME} adapter: {pointer} missing required key '{req_key}': {source_path}",
                )
            if not isinstance(entry[req_key], str):
                _die(
                    2,
                    f"{ADAPTER_NAME} adapter: {pointer}.{req_key} must be a string: {source_path}",
                )

        if "label" in entry and not isinstance(entry["label"], str):
            _die(2, f"{ADAPTER_NAME} adapter: {pointer}.label must be a string: {source_path}")

    wbm = data.get("warn_before_minutes")
    if wbm is not None and (not isinstance(wbm, int) or isinstance(wbm, bool)):
        _die(2, f"{ADAPTER_NAME} adapter: 'warn_before_minutes' must be an integer: {source_path}")

    tz_field = data.get("timezone")
    if tz_field is not None and not isinstance(tz_field, str):
        _die(2, f"{ADAPTER_NAME} adapter: 'timezone' must be a string: {source_path}")


# ---------------------------------------------------------------------------
# Decision logic
# ---------------------------------------------------------------------------


def evaluate(
    ts: datetime,
    blackouts: list[dict],
    warn_before_minutes: int,
    file_tz: str | None,
    source_path: str,
) -> dict:
    """Evaluate ts against the blackout list and return the decision dict."""
    naive_warned = False

    def parse_entry_ts(ts_str: str, label: str) -> datetime:
        nonlocal naive_warned
        try:
            dt = datetime.fromisoformat(ts_str)
        except ValueError as exc:
            _die(
                2, f"{ADAPTER_NAME} adapter: invalid date-time string '{ts_str}' at {label}: {exc}"
            )

        if dt.tzinfo is not None:
            return dt.astimezone(UTC)

        # Naive timestamp.
        if file_tz:
            try:
                tz_obj = ZoneInfo(file_tz)
            except ZoneInfoNotFoundError:
                _die(2, f"{ADAPTER_NAME} adapter: unknown timezone '{file_tz}' in calendar file")
            return dt.replace(tzinfo=tz_obj).astimezone(UTC)  # type: ignore[union-attr]

        # No file-level timezone — treat as UTC, warn once.
        if not naive_warned:
            print(
                f"{ADAPTER_NAME} adapter: warning: naive timestamp '{ts_str}' at {label} "
                "treated as UTC (set top-level 'timezone' to avoid this warning)",
                file=sys.stderr,
            )
            naive_warned = True
        return dt.replace(tzinfo=UTC)

    # Normalize all blackout windows to aware UTC datetimes and validate ordering.
    normalized: list[tuple[datetime, datetime, str]] = []
    for idx, entry in enumerate(blackouts):
        pointer = f"blackouts[{idx}]"
        start_dt = parse_entry_ts(entry["start"], f"{pointer}.start")
        end_dt = parse_entry_ts(entry["end"], f"{pointer}.end")
        if start_dt >= end_dt:
            _die(
                2,
                f"{ADAPTER_NAME} adapter: {pointer} has start >= end ({entry['start']} >= {entry['end']}): {source_path}",
            )
        label = entry.get("label") or "blackout"
        normalized.append((start_dt, end_dt, label))

    # 1. Check if ts falls inside any blackout (inclusive start, exclusive end).
    for start_dt, end_dt, label in normalized:
        if start_dt <= ts < end_dt:
            rationale = f"{label} ({_format_utc(start_dt)} .. {_format_utc(end_dt)})"
            return {
                "decision": "blocked",
                "rationale": rationale,
                "adapter": ADAPTER_NAME,
                "window_source": source_path,
            }

    # 2. Check if any future blackout starts within warn_before_minutes.
    warn_delta = timedelta(minutes=warn_before_minutes)
    upcoming = sorted(
        ((start_dt, end_dt, label) for start_dt, end_dt, label in normalized if start_dt > ts),
        key=lambda x: x[0],
    )
    for start_dt, _end_dt, label in upcoming:
        diff = start_dt - ts
        if diff <= warn_delta:
            minutes_away = int(diff.total_seconds() // 60)
            rationale = f"blackout opens at {_format_utc(start_dt)} ({minutes_away}m away): {label}"
            return {
                "decision": "warning",
                "rationale": rationale,
                "adapter": ADAPTER_NAME,
                "window_source": source_path,
            }

    # 3. Allowed — determine next blackout start for the rationale.
    if upcoming:
        next_start = _format_utc(upcoming[0][0])
        rationale = f"no blackout covers ts; next blackout: {next_start}"
    else:
        rationale = "no blackout covers ts; next blackout: none"

    return {
        "decision": "allowed",
        "rationale": rationale,
        "adapter": ADAPTER_NAME,
        "window_source": source_path,
    }


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Evaluate a proposed change timestamp against a JSON blackout calendar.",
        add_help=True,
    )
    parser.add_argument("--ts", required=True, help="Proposed change timestamp in UTC ISO-8601.")
    parser.add_argument("--source", required=True, help="Path to the JSON blackout-calendar file.")
    parser.add_argument(
        "--timezone",
        default="UTC",
        help="IANA timezone for human-readable rationale (default: UTC).",
    )
    parser.add_argument(
        "--warn-before-minutes",
        type=int,
        default=None,
        help="Override warn_before_minutes from the calendar file.",
    )
    args = parser.parse_args()

    source_path = args.source

    # Load and parse JSON.
    try:
        with open(source_path, encoding="utf-8") as fh:
            raw = fh.read()
    except OSError as exc:
        _die(2, f"{ADAPTER_NAME} adapter: cannot read source file {source_path}: {exc}")

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        _die(2, f"{ADAPTER_NAME} adapter: malformed JSON at {source_path}: {exc}")

    # Validate schema.
    _validate_calendar(data, source_path)

    # Resolve warn_before_minutes: CLI flag > file field > default.
    if args.warn_before_minutes is not None:
        warn_before_minutes = args.warn_before_minutes
    else:
        warn_before_minutes = data.get("warn_before_minutes", DEFAULT_WARN_BEFORE_MINUTES)

    file_tz: str | None = data.get("timezone")

    # Parse the proposed timestamp.
    try:
        ts = datetime.fromisoformat(args.ts)
    except ValueError as exc:
        _die(2, f"{ADAPTER_NAME} adapter: invalid --ts value '{args.ts}': {exc}")

    ts = ts.replace(tzinfo=UTC) if ts.tzinfo is None else ts.astimezone(UTC)

    # Resolve absolute source path for consistent output.
    abs_source = os.path.abspath(source_path)

    result = evaluate(ts, data["blackouts"], warn_before_minutes, file_tz, abs_source)
    print(json.dumps(result, separators=(",", ":")))


if __name__ == "__main__":
    main()
