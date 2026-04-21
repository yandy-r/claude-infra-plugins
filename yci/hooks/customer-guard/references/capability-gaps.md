# customer-guard: per-target capability gaps

## Overview

This document records per-target hook-support verdicts for the `customer-guard` hook.
The authoritative source for all HOOKS.PreToolUse verdicts is
`ycc/skills/_shared/references/target-capability-matrix.md`. The relevant row is:

```
| HOOKS.PreToolUse  | supported | partial     | unsupported | partial     |
```

(columns: claude | cursor | codex | opencode)

The core stance mirrors `ycc/skills/hooks-workflow/references/support-notes.md`:
`customer-guard` refuses to fabricate config for an unsupported target.
Cross-platform hook parity does not exist; this document explains the gaps rather
than papering over them.

---

### Claude Code

**Verdict**: `supported`

**Ships in this PR**: Full implementation — `hook.json`, `pretool.sh`, decision-JSON
emitter, and `plugin.json` registration. Claude Code is the primary target for
`customer-guard`; no feature is deferred for this target.

**Deferred to**: None. Claude Code is the authoritative runtime and receives the
complete hook implementation.

**Stub path**: n/a

---

### Cursor

**Verdict**: `partial`

**Ships in this PR**: Nothing runtime-visible. The generator fleet does not yet emit
`yci` into `.cursor-plugin/`; Cursor users do not receive any hook artifact from this
PR.

**Deferred to**: Phase 1a — cross-target bundle generator extension. When the generator
emits `yci` into `.cursor-plugin/`, a Cursor `.mdc` rule file at
`.cursor-plugin/rules/yci-customer-guard.mdc` will carry the guard policy as a rule
embedding. Per the capability matrix, hooks are not natively runnable in Cursor;
the `.mdc` rule will be advisory documentation, not executed config.

**Stub path**: n/a (this PR does not commit a Cursor `.mdc`)

---

### Codex

**Verdict**: `unsupported`

**Ships in this PR**: A comment-only TOML advisory stub
(`yci/hooks/customer-guard/targets/codex/codex-config-fragment.toml`) that reserves
the fragment name and documents the deferred wiring intent. No executable TOML keys
are emitted.

**Deferred to**: Phase 1b — if/when Codex GAs `features.codex_hooks` (currently
`unsupported` per the target-capability-matrix research audit of April 2026), the
advisory stub will be promoted to a real TOML config snippet wiring `pretool.sh` to
the PreToolUse-equivalent event.

**Stub path**: `yci/hooks/customer-guard/targets/codex/codex-config-fragment.toml`

---

### opencode

**Verdict**: `partial`

**Ships in this PR**: Nothing runtime-visible. The generator fleet does not yet emit
`yci` into `.opencode-plugin/`; opencode users do not receive any hook artifact from
this PR.

**Deferred to**: Phase 1a — cross-target bundle generator extension. Phase 1b —
optional `@yandy/opencode-yci-hooks` TypeScript plugin (per the
target-capability-matrix note on `tool.execute.before`) that would upgrade opencode
from `partial` to `supported` by providing a native pre-tool event handler for
`customer-guard`.

**Stub path**: n/a

---

`yci refuses to fabricate config for an unsupported target.`
See [hooks-workflow support-notes](../../../../ycc/skills/hooks-workflow/references/support-notes.md) for the canonical anti-parity stance.
