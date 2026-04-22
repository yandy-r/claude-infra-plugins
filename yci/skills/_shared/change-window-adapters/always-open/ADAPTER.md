# always-open change-window adapter

## Purpose

Bookend adapter: never enforces a change window. Use with:

- The `_internal` homelab profile (PRD §Q5) where there is no enforcement policy.
- Profiles during early yci adoption, before a real adapter (iCal / JSON-schedule / ServiceNow) is
  authored.
- As the ship-first adapter (PRD §11.4) so the dispatcher + hook can be tested end-to-end before the
  heavier adapters land.

## Profile wiring

```yaml
change_window:
  adapter: always-open
```

No `source` or `timezone` needed — the adapter ignores them.

## Interface

`scripts/check.sh` accepts the same flags as other change-window adapters for call-site uniformity
but ignores all of them. Always emits:

```json
{
  "decision": "allowed",
  "rationale": "always-open adapter: no change-window enforced",
  "adapter": "always-open",
  "window_source": null
}
```

`check.sh` exits 0 for normal operation, including known ignored flags. Unknown or invalid flags
exit non-zero (`1`), so operators should still check the exit status when troubleshooting adapter
invocation failures.

## Security note

The adapter does no I/O beyond the one-line stdout print. It never reads `--source`; callers may
safely pass a nonexistent path.

## Testing

See `yci/hooks/change-window-gate/tests/test_always_open_adapter.sh`.
