# yci change-window-gate hook — Operator Reference

## Purpose

The `change-window-gate` hook is a `PreToolUse` control that intercepts every Claude Code tool call
(matcher `"*"`) and blocks destructive tool calls during freeze or blackout windows defined in the
active customer profile. It implements PRD §6.1 P0.8: the operator must not accidentally apply
changes to a customer environment during a mandated change-freeze without an explicit override. The
hook runs **after** `customer-guard` under the combined `yci/hooks/hooks.json` manifest; this
ordering is load-bearing — `customer-guard` must deny cross-customer calls before this hook
evaluates window state (see PRD §5.4 and the
[plan decisions D2–D3](../../../docs/prps/plans/change-window-gate.plan.md)).

What this hook does NOT do: it does not block read-only tool calls (`Read`, `Grep`, `Glob`,
`WebFetch`, `WebSearch`, and non-destructive `Bash` commands); it does not enforce authorization or
compliance posture (those are `customer-guard` and the compliance-adapter surface); and it does not
intercept tools outside Claude Code — Cursor, Codex, and opencode have advisory stubs only (see
[references/capability-gaps.md](references/capability-gaps.md)).

## Install Check

> Both yci hooks are wired via `yci/hooks/hooks.json`. See `../customer-guard/README.md` for the
> first hook in the chain.

Confirm the yci plugin is enabled and the combined hook manifest is wired before relying on this
hook in a production engagement.

```bash
# Confirm yci plugin is enabled in Claude Code
claude plugins list | grep yci

# Confirm hooks.json is the registered manifest in plugin.json
python3 -c "
import json
with open('<path-to-yci-plugin>/.claude-plugin/plugin.json') as f:
    print(json.load(f).get('hooks'))
"
# Expect: "./hooks/hooks.json"

# Confirm hooks.json wires change-window-gate (two entries under PreToolUse)
python3 -c "
import json
with open('<path-to-yci-plugin>/hooks/hooks.json') as f:
    hooks = json.load(f)['hooks']['PreToolUse']
    for h in hooks[0]['hooks']:
        print(h['command'])
"
# Expect two lines — one for customer-guard/scripts/pretool.sh,
# one for change-window-gate/scripts/pretool.sh.
```

For a live dry-run probe that exercises the hook against a synthetic payload:

```bash
echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test.txt","content":"x"}}' \
  | YCI_CWG_DRY_RUN=1 bash yci/hooks/change-window-gate/scripts/pretool.sh
```

With `YCI_CWG_DRY_RUN=1` the hook logs a `[DRY-RUN-BLOCKED]` banner when it would block and exits 0
— a safe probe. If the hook exits non-zero or prints nothing, run `./scripts/validate.sh` to check
the full yci installation status.

## False-Positive Triage Workflow

When the hook blocks a tool call the operator intended to allow, follow these steps in order:

1. **Re-run with dry-run mode** to confirm the would-block reason without actually denying the call:

   ```bash
   YCI_CWG_DRY_RUN=1 <re-issue the failing tool call or script invocation>
   ```

   The hook emits a `[DRY-RUN-BLOCKED]:` banner to stderr and appends an audit entry, then allows
   the call. The banner includes the rationale from the adapter and the error ID.

2. **Inspect the audit log** for the full structured entry:

   ```text
   $YCI_DATA_ROOT/logs/change-window-gate.audit.log
   ```

   Each entry records the UTC timestamp, the blocked tool name, and the deny rationale.

3. **Identify the error ID** from the rationale (the prefix before the first colon, e.g.
   `cwg-destructive-in-blackout`). Consult
   [references/error-messages.md](references/error-messages.md) for per-ID guidance.

4. **Act on the error**:
   - `cwg-destructive-in-blackout` — the active customer's change-window adapter reported a blackout
     at the current time. Verify the schedule is correct; if the change is authorized out-of-band,
     use `YCI_CWG_OVERRIDE=1` (see below).
   - `cwg-no-profile-cannot-create` / `cwg-no-profile-destructive-write` — no active customer
     profile is set. Run `/yci:switch <customer-id>` first.
   - `cwg-adapter-load-failed` / `cwg-adapter-error` — the adapter configuration in the profile is
     broken. Inspect the profile's `change_window` block and adapter files.

5. **Re-run without dry-run** to confirm the issue is resolved:

   ```bash
   # unset YCI_CWG_DRY_RUN (or ensure it is unset)
   <re-issue the tool call>
   ```

## Override Envvar — `YCI_CWG_OVERRIDE=1`

Per-call (or per-session) override. When set to the literal string `1`, the hook exits 0 immediately
without evaluating any adapter — the tool call is allowed regardless of window state. The override
is checked both in `pretool.sh` (at step 2 of the decision flow) and in `window-decision.sh` (inside
`cwg_decide`).

Use `YCI_CWG_OVERRIDE=1` when:

- The operator holds independent break-glass authorization for a change during a freeze window.
- A change-window exception has been granted by the customer's CAB and the operator wants to retain
  the hook for all other calls in the session.

Scope the envvar as tightly as possible:

```bash
# Per-invocation (safest)
YCI_CWG_OVERRIDE=1 bash yci/hooks/change-window-gate/scripts/pretool.sh < payload.json

# Per-session (use only when multiple consecutive calls need override)
export YCI_CWG_OVERRIDE=1
# ... perform authorized calls ...
unset YCI_CWG_OVERRIDE
```

Unlike `YCI_CWG_DRY_RUN`, the override produces no audit-log entry — it short-circuits before any
logging. Document the override rationale in the engagement's change record outside of yci.

## Dry-Run Envvar — `YCI_CWG_DRY_RUN=1`

Log-only mode. When the hook would emit a `blocked` deny decision, it instead:

- Prints a `yci change-window-gate [DRY-RUN-BLOCKED]: <rationale>` banner to stderr.
- Appends one line to `$YCI_DATA_ROOT/logs/change-window-gate.audit.log` with UTC timestamp, tool
  name, and rationale.
- Exits 0 (the tool call proceeds).

Use `YCI_CWG_DRY_RUN=1` for:

- **False-positive triage**: observe whether the hook would block a call and why, without disrupting
  the session.
- **Profile validation**: verify that the `change_window` block and adapter are wired correctly
  before enforcing.
- **Post-change audit**: review all would-be-blocked calls in the audit log.

The audit log is written best-effort — if `$YCI_DATA_ROOT/logs/` is not writable, the hook emits the
stderr banner and still exits 0 without failing.

## Behavior Without an Active Profile (D7)

When no customer profile is resolvable (the resolver returns non-zero and `$YCI_CUSTOMER` is unset),
the hook classifies the pending tool call by purpose class rather than failing closed
unconditionally. This enables bootstrap and init workflows to function before a profile exists,
while still blocking destructive customer-facing calls (plan decision D7; see
`scripts/purpose-classifier.sh` for the classifier source):

| Purpose class                            | Example tool calls                                                                                                             | Decision                                       |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------- |
| **Init / setup / dependency-resolution** | Writes to `$YCI_DATA_ROOT/profiles/`, package installs (`npm install`, `pip install`, `brew install`), `/yci:init` scaffolding | `allowed` with stderr advisory                 |
| **Customer-artifact creation**           | `Write`/`Edit`/`NotebookEdit` under `$YCI_DATA_ROOT/artifacts/` or paths matching deliverable conventions                      | `blocked` — `cwg-no-profile-cannot-create`     |
| **Other destructive write**              | Any other `Write`, `Edit`, `NotebookEdit`, or destructive `Bash` command                                                       | `blocked` — `cwg-no-profile-destructive-write` |
| **Read-only**                            | `Read`, `Grep`, `Glob`, `WebFetch`, non-destructive `Bash`                                                                     | `allowed` (exits before this classification)   |

Run `/yci:switch <customer-id>` to activate a profile and remove these restrictions.

## Error Reference

The hook emits structured deny reasons using catalogued error IDs. Every deny message routes through
the catalog — no ad-hoc strings. When the hook emits an unexpected deny or error ID, cross-reference
against the catalog for the full message template, trigger condition, and operator guidance.

See [references/error-messages.md](references/error-messages.md) for the full catalog of `cwg-*`
error IDs.

Quick index:

- `cwg-no-profile-cannot-create` — destructive + no active profile + artifact creation path
- `cwg-no-profile-destructive-write` — destructive + no active profile + non-init path
- `cwg-profile-load-error` — active profile found but could not be loaded
- `cwg-adapter-load-failed` — dispatcher could not resolve the adapter named in the profile
- `cwg-adapter-error` — adapter `check.sh` crashed or emitted malformed JSON
- `cwg-destructive-in-blackout` — adapter reported `blocked` for the current timestamp
- `cwg-internal-error` — unexpected decision value from `window-decision.sh` (fail-closed)

## Capability Gaps

Cross-target hook support varies. See [references/capability-gaps.md](references/capability-gaps.md)
for the per-target verdict. As of Phase 0, only Claude Code ships a functional hook; Cursor and
opencode parity are deferred to Phase 1a; Codex is unsupported with an advisory stub only.

## Security Note

**Bypass vectors**: Setting `YCI_CWG_OVERRIDE=1` removes all blocking for the duration the envvar is
set. Setting `YCI_CWG_DRY_RUN=1` converts every block to a logged allow. Setting
`safety.change_window_required: false` in the customer profile (or configuring the `always-open`
adapter) disables window enforcement for that profile entirely. These are intentional — the operator
is trusted; this hook exists to prevent accidental destructive calls during freeze windows, not
adversarial behavior by a hostile operator.

**What this hook does NOT do**: it does not cross-check timestamps in the tool payload against the
change window (only `date -u` at invocation time is evaluated). A future enhancement could inspect
`git log --since` or similar hints to catch retrospective replays. It does not validate that the
tool call's stated intent matches the actual bytes written — that is a scope-gate concern (PRD §6.1
P0.4).

**The `none` adapter** is the paranoid bookend: it blocks all destructive calls unless
`YCI_CWG_OVERRIDE=1` is set explicitly. Use it for customers where a change window is undefined and
per-call acknowledgment is required.

## Related

- [`customer-guard` hook](../customer-guard/README.md) — runs before this hook under the shared
  matcher; enforces the zero-cross-customer-leaks invariant.
- [`yci/hooks/hooks.json`](../hooks.json) — the combined manifest wiring both hooks.
- [`yci/skills/_shared/change-window-adapters/`](../../skills/_shared/change-window-adapters/) — the
  adapter directory (`ical`, `json-schedule`, `always-open`, `none`).
- [`yci/skills/_shared/scripts/load-change-window-adapter.sh`](../../skills/_shared/scripts/load-change-window-adapter.sh)
  — the dispatcher that resolves `change_window.adapter` from the active profile.
- [`yci/CONTRIBUTING.md`](../../CONTRIBUTING.md) — change-window adapter contract and how to add a
  new adapter.
- [`docs/prps/plans/change-window-gate.plan.md`](../../../docs/prps/plans/change-window-gate.plan.md)
  — full implementation plan and locked decisions D1–D7.
