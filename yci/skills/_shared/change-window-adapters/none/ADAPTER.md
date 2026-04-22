# None Change-Window Adapter

## Adapter

`none`

## Purpose

Paranoid bookend. The default decision is **blocked** regardless of time, schedule, or any other
input. The adapter forces per-call opt-in: the operator must explicitly set `YCI_CWG_OVERRIDE=1` to
obtain an `allowed` decision. No schedule is consulted; none exists.

Use this for customers where the change-window posture is unknown or explicitly undefined, and where
the operator wants to acknowledge each destructive action individually rather than delegating the
decision to a policy file.

Contrast with:

- `always-open` — never blocks; suitable for unrestricted development contexts.
- `ical` / `json-schedule` — policy-based; block or allow by evaluating a schedule.

## Profile wiring

```yaml
change_window:
  adapter: none
  # no source field — none evaluates no external schedule
```

## Override envvar

`YCI_CWG_OVERRIDE=1` — set this to acknowledge the null policy for a single Claude session or tool
call. Scope it per-invocation where possible:

```bash
YCI_CWG_OVERRIDE=1 bash ...
```

Any value other than the literal string `1` (including `0`, `yes`, `true`, unset) leaves the
decision as `blocked`.

## Interface

`scripts/check.sh` accepts `--ts`, `--source`, `--timezone`, and `--warn-before-minutes` for
flag-surface compatibility but ignores all of them. Unknown flags exit 1 (usage error). The decision
is keyed solely off the `YCI_CWG_OVERRIDE` envvar.

## Security note

The envvar is the sole control boundary. If `YCI_CWG_OVERRIDE=1` is set for an entire shell session,
the adapter returns `allowed` for every call in that session. Scope the envvar per-invocation
(`YCI_CWG_OVERRIDE=1 bash …`) when single-call semantics are required.

## Testing

See `yci/hooks/change-window-gate/tests/test_none_adapter.sh`.
