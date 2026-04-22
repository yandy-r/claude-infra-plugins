# JSON-schedule change-window adapter

## Purpose

Minimum-viable change-window adapter for operators who do not maintain an iCal calendar server.
Reads a small JSON blackout-calendar file and emits an `allowed`, `warning`, or `blocked` decision.
Intended as the simplest possible on-ramp: a single JSON file checked into the customer's config
directory is sufficient to enforce change-window controls.

See PRD §5.2 for the change-window adapter model and PRD §5.4 for the adapter catalogue.

## Requirements

**Python ≥ 3.11** is required. `datetime.fromisoformat` gained full ISO-8601 support (including the
`Z` suffix) in Python 3.11. The evaluation script (`scripts/schedule_eval.py`) will exit 3 on older
interpreters when it encounters `Z`-suffixed timestamps. The repo's `pyproject.toml` targets
`py311`, so this is consistent with the project baseline.

## Profile wiring

Add a `change_window` block to the customer profile (YAML representation):

```yaml
change_window:
  adapter: json-schedule
  source: ~/.config/yci/customers/<slug>/blackouts.json
  timezone: America/Chicago # optional; for human-readable rationale
```

Fields:

- `adapter` — must be `json-schedule`.
- `source` — absolute (or `~`-expanded) path to the JSON blackout-calendar file.
- `timezone` — optional IANA timezone name; passed to `check.sh` as `--timezone` for rationale
  formatting only. Does not affect timestamp parsing (use `timezone` inside the JSON file for that).

## File format

See `schema.json` for the formal JSON Schema (draft-07). Example:

```json
{
  "blackouts": [
    {
      "start": "2026-04-22T14:00:00Z",
      "end": "2026-04-22T20:00:00Z",
      "label": "Production freeze"
    },
    {
      "start": "2026-04-25T00:00:00Z",
      "end": "2026-04-26T00:00:00Z",
      "label": "CAB blackout"
    }
  ],
  "warn_before_minutes": 60,
  "timezone": "America/Chicago"
}
```

Top-level fields:

| Field                 | Type    | Required | Description                                                                                                     |
| --------------------- | ------- | -------- | --------------------------------------------------------------------------------------------------------------- |
| `blackouts`           | array   | yes      | List of blackout windows.                                                                                       |
| `warn_before_minutes` | integer | no       | Minutes before blackout start to issue a warning. Default: 60.                                                  |
| `timezone`            | string  | no       | IANA timezone for interpreting naive timestamps in `blackouts`. If absent, naive timestamps are treated as UTC. |

Per-entry fields (`blackouts[]`):

| Field   | Type   | Required | Description                                           |
| ------- | ------ | -------- | ----------------------------------------------------- |
| `start` | string | yes      | ISO-8601 date-time. Prefer UTC (`Z` suffix).          |
| `end`   | string | yes      | ISO-8601 date-time. Must be strictly after `start`.   |
| `label` | string | no       | Human-readable name shown in the hook deny-rationale. |

## Interface

### Flags

| Flag                      | Required | Default | Description                                                              |
| ------------------------- | -------- | ------- | ------------------------------------------------------------------------ |
| `--ts <iso8601>`          | yes      | —       | Proposed change timestamp in UTC ISO-8601.                               |
| `--source <path>`         | yes      | —       | Path to the JSON blackout-calendar file.                                 |
| `--timezone <tz>`         | no       | `UTC`   | IANA timezone for human-readable rationale only.                         |
| `--warn-before-minutes N` | no       | 60      | Override `warn_before_minutes` from the file. CLI flag takes precedence. |

### Emitted JSON (stdout, single line)

```json
{
  "decision": "allowed|warning|blocked",
  "rationale": "<string>",
  "adapter": "json-schedule",
  "window_source": "<abs-path>"
}
```

### Exit codes

| Code | Meaning                                                                 |
| ---- | ----------------------------------------------------------------------- |
| 0    | Decision emitted successfully.                                          |
| 2    | Source file missing / unreadable, malformed JSON, or schema violation.  |
| 3    | Runtime error (e.g. `python3` not in PATH, `schedule_eval.py` missing). |

## Decision thresholds

1. **`blocked`** — `ts` falls within any blackout window (inclusive start, exclusive end).
   Rationale: `"<label> (<start_utc> .. <end_utc>)"`.

2. **`warning`** — no blackout covers `ts`, but the next upcoming blackout starts within
   `warn_before_minutes` of `ts`. Rationale: `"blackout opens at <start_utc> (<N>m away): <label>"`.

3. **`allowed`** — `ts` is outside all blackout windows and no blackout is imminent. Rationale:
   `"no blackout covers ts; next blackout: <start_utc or 'none'>"`.

## Authoring tips

- Prefer UTC timestamps (`...Z`) to avoid ambiguity. The `Z` suffix is unambiguous and requires no
  top-level `timezone` field.
- If you must use local time, set the top-level `timezone` field. All naive timestamps in
  `blackouts` are interpreted in that zone. Mixing aware and naive timestamps in the same file is
  valid but confusing — avoid it.
- A blackout with `start >= end` is a schema error and causes exit 2. The adapter validates this on
  every invocation.
- `label` is optional but strongly recommended — it appears verbatim in the hook deny-rationale text
  that operators see in Claude Code.
- Overlapping blackouts are intentional and supported. Any blackout that covers `ts` triggers
  `blocked`; the first matching window's label is used in the rationale.

## Security note

The evaluation script (`scripts/schedule_eval.py`) uses only Python stdlib: `argparse`, `json`,
`datetime`, `zoneinfo`, `os`, `sys`. There is no network access, no shell invocation, and no `eval`.
The source file must be a readable local path — no URLs are accepted. The `json` module raises
`JSONDecodeError` on malformed input; the script propagates this as exit 2 rather than crashing.

## Testing

See `yci/hooks/change-window-gate/tests/test_json_schedule_adapter.sh` (fixture-backed tests added
in the change-window-gate hook batch).
