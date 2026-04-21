---
name: hello
description: 'Proof-of-life skill for the yci plugin — confirms the skill pipeline resolves end-to-end. Prints a one-line greeting from yci. Phase 0; replaced by yci:whoami when the customer-profile machinery lands.'
---

# yci:hello — Proof-of-Life

## Purpose

This skill exists to confirm that the yci plugin's skill pipeline resolves
end-to-end in Phase 0. It has no production functionality.

## Expected Output

When invoked, respond with exactly:

```
yci is alive; active profile: <unset in Phase 0>
```

No tool calls are required. The response is purely instructional prose.

## What's Next

This skill is temporary scaffolding for Phase 0 validation. It will be
replaced by `yci:whoami` once the following Phase 1 components ship:

- `$YCI_DATA_ROOT/state.json` — the persistent customer-profile store
- The customer-profile loader that reads and validates `state.json` at
  skill invocation time

See the yci PRD at `docs/prps/prds/yci.prd.md` §6.1 (Customer Data Root
design) and §11 (Phase 1 milestone) for the full roadmap.

## Notes

- No configuration or environment variables are read by this skill.
- `$YCI_DATA_ROOT` is not yet set in Phase 0; the `<unset>` literal in
  the output is intentional.
- Do not build anything on top of this skill — use `yci:whoami` once it
  is available.
