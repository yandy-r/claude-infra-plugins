# iCal change-window adapter

## Purpose

This adapter evaluates a proposed-change timestamp against one or more `VEVENT` entries in a local
`.ics` file and emits a `blocked | warning | allowed` decision. It is the recommended adapter for
teams that manage change windows via Google Calendar, Outlook, or any other iCal-compatible calendar
export.

## Profile wiring

```yaml
change_window:
  adapter: ical
  source: ~/.config/yci/customers/acme/change-windows.ics # absolute or $HOME-relative path
  timezone: America/Chicago # IANA timezone; used in rationale text only
```

Reference PRD §5.2 for the full `change_window` profile block schema.

## Interface

### Flags

| Flag                      | Required | Default | Description                                                                    |
| ------------------------- | -------- | ------- | ------------------------------------------------------------------------------ |
| `--ts <iso8601>`          | yes      | —       | Proposed-change timestamp in UTC ISO-8601 (e.g. `2026-04-22T14:30:00Z`).       |
| `--source <path>`         | yes      | —       | Absolute path to the `.ics` file.                                              |
| `--timezone <iana>`       | no       | `UTC`   | IANA timezone name. Used only in rationale strings; all decisions are UTC.     |
| `--warn-before-minutes N` | no       | `60`    | Emit `warning` when the next blocking event starts within N minutes of `--ts`. |

### Emitted JSON (stdout, one line)

```json
{
  "decision": "allowed|warning|blocked",
  "rationale": "<string>",
  "adapter": "ical",
  "window_source": "<abs-path>"
}
```

### Exit codes

| Code | Meaning                                                              |
| ---- | -------------------------------------------------------------------- |
| `0`  | Decision emitted (any of `allowed`, `warning`, `blocked`).           |
| `2`  | Adapter config error: source file missing, unreadable, or malformed. |
| `3`  | Runtime error: `python3` not available, `zoneinfo` missing, etc.     |

Non-zero exits are caught by the caller (`window-decision.sh`) and translated into a `blocked`
verdict with `rationale: cwg-adapter-error: <stderr>`.

## Supported `.ics` features

- `VEVENT` blocks delimited by `BEGIN:VEVENT` / `END:VEVENT`
- `DTSTART` / `DTEND` with:
  - UTC suffix `Z` (e.g. `20260422T140000Z`)
  - `TZID=<iana>:<yyyymmddThhmmss>` property parameter
  - `VALUE=DATE:<yyyymmdd>` (all-day events; treated as covering the full 24-hour day in UTC)
  - Naive local date-time (resolved via the event's `TZID` if present, else `--timezone`, else
    `UTC`)
- `SUMMARY` — used in the rationale string (percent-decoded; `\n`, `\,`, `\;` escapes unescaped)
- `RRULE` with `FREQ=DAILY|WEEKLY` and either `COUNT=<int>` or `UNTIL=<yyyymmddThhmmssZ>`

## Unsupported (Phase 2+ scope)

- **`RRULE FREQ=MONTHLY`, `INTERVAL`, `BYDAY`, `BYSETPOS`, `BYMONTH`, `BYMONTHDAY`** — adapter emits
  a stderr warning and treats the `DTSTART` as a single occurrence. These modifiers can produce
  complex expansion and are deferred to Phase 1+.
- **Inline `VTIMEZONE` definitions** — adapter resolves timezone names via `zoneinfo` (system
  tzdata). Inline `VTIMEZONE` blocks are silently skipped; the `TZID` property parameter on
  `DTSTART`/`DTEND` must be a valid IANA name for resolution to succeed.
- **`VTODO`, `VJOURNAL`, `VALARM`** — adapter only scans `VEVENT` components; all other component
  types are ignored.
- **Recurring events beyond 14-day lookahead** — occurrence expansion is bounded to
  `[ts - 14d, ts + 14d]`. Events with recurrence rules that first appear outside this window are not
  evaluated.

## Security note

The `.ics` parser is hand-rolled and stdlib-only. It does not execute any content embedded in the
file, does not resolve relative URIs, and does not fetch remote calendars. The `--source` path must
be a readable local file. The adapter will reject source files that do not exist or are not readable
rather than silently falling back.

## Decision thresholds

| Condition                                                            | Decision  |
| -------------------------------------------------------------------- | --------- |
| Any `VEVENT` occurrence covers `ts` (inclusive start, exclusive end) | `blocked` |
| Next `VEVENT` occurrence starts within `warn-before-minutes` of `ts` | `warning` |
| No covering or near-future event found                               | `allowed` |

## Testing

See `yci/hooks/change-window-gate/tests/test_ical_adapter.sh` (fixture-backed; covers covered /
warning / outside / malformed / timezone-boundary cases).
