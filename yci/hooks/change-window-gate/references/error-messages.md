# yci change-window-gate — Error Messages

This file is the canonical source of user-visible error strings for the `change-window-gate` hook.
Scripts emit these strings verbatim; tests assert against them verbatim. **Change here first, then
update scripts and tests.** Enumerated errors cover the full decision lifecycle: no-profile
classification (D7), profile load failure, adapter dispatch failure, adapter runtime errors, and
blackout enforcement. Adding a new error requires updating this catalog, the emitting script, and
the corresponding test in the same change.

---

## Exit-Code Convention

| Exit | Meaning                                                                              |
| ---- | ------------------------------------------------------------------------------------ |
| 0    | success — `pretool.sh` always exits 0; the deny JSON on stdout is the refusal signal |

The hook never exits non-zero under normal operation. A non-zero exit indicates a shell-level
failure (missing dependency, unrecoverable syntax error) that Claude Code interprets as "hook
errored" rather than "deny". All deliberate blocking is done by emitting deny JSON and exiting 0.

### Adapter exit codes

Adapters (`scripts/check.sh`) use a separate exit-code convention caught by `window-decision.sh`:

| Exit | Meaning                                                                       |
| ---- | ----------------------------------------------------------------------------- |
| 0    | decision emitted (any of `allowed`, `warning`, `blocked`)                     |
| 2    | adapter config error (source file missing, unreadable, or malformed JSON/ICS) |
| 3    | runtime error (`python3` not available, `zoneinfo` missing, etc.)             |

Non-zero adapter exits are caught by `cwg_decide` in `window-decision.sh` and translated to a
`cwg-adapter-error` blocked decision before reaching `pretool.sh`.

---

## Error Catalog

---

### `cwg-no-profile-cannot-create`

- **ID**: `cwg-no-profile-cannot-create`
- **Producer**: `pretool.sh`
- **Exit code**: 0 (deny emitted via decision JSON)
- **Trigger**: No active customer profile is resolvable (`$YCI_CUSTOMER` unset, no `.yci-customer`
  dotfile, `state.json` absent) **AND** the tool call is classified as customer-artifact creation
  (writes under `$YCI_DATA_ROOT/artifacts/` or paths matching deliverable conventions per D7 in
  `purpose-classifier.sh`).
- **Message**:

  ```text
  cwg-no-profile-cannot-create: cannot enforce a change window without an active customer profile; run /yci:switch <id> first
  ```

- **Operator guidance**: Run `/yci:switch <customer-id>` to activate a profile and retry the call.
  If the artifact is not customer-scoped, verify the target path — if it is genuinely under
  `$YCI_DATA_ROOT/artifacts/` but is not a customer deliverable, reconsider whether that path is the
  correct destination.

---

### `cwg-no-profile-destructive-write`

- **ID**: `cwg-no-profile-destructive-write`
- **Producer**: `pretool.sh`
- **Exit code**: 0 (deny emitted via decision JSON)
- **Trigger**: No active customer profile is resolvable **AND** the tool call is destructive (per
  `destructive-classifier.sh`) **AND** it is not classified as an init/setup path or artifact
  creation (D7 fallback — conservative block).
- **Message**:

  ```text
  cwg-no-profile-destructive-write: destructive operation (<tool_name>) requires an active customer profile; run /yci:switch <id> first
  ```

  `<tool_name>` is the Claude Code tool name (e.g. `Write`, `Edit`, `Bash`).

- **Operator guidance**: Run `/yci:switch <customer-id>` to activate a profile. If the destructive
  call is an init/setup action (e.g., `mkdir -p $YCI_DATA_ROOT`), it may have been misclassified;
  inspect `purpose-classifier.sh` and open an issue if the classification is wrong.

---

### `cwg-profile-load-error`

- **ID**: `cwg-profile-load-error`
- **Producer**: `pretool.sh` (via `load-profile.sh` subprocess) and `window-decision.sh` (profile
  JSON field extraction)
- **Exit code**: 0 (deny emitted via decision JSON)
- **Trigger**: The active customer profile was resolved (customer ID is known) but `load-profile.sh`
  exited non-zero, or the `change_window` block could not be parsed from the profile JSON by
  `window-decision.sh`.
- **Message** (from `pretool.sh`):

  ```text
  cwg-profile-load-error: could not load profile '<customer>'
  ```

  **Message** (from `window-decision.sh` JSON field extraction):

  ```text
  cwg-profile-load-error: <python-parse-error>
  ```

- **Operator guidance**: Verify the profile YAML with `/yci:whoami` or inspect
  `$YCI_DATA_ROOT/profiles/<customer>.yaml` directly. Common causes: malformed YAML, missing
  required fields, incorrect `change_window` block. Fix the YAML syntax and retry.

---

### `cwg-adapter-load-failed`

- **ID**: `cwg-adapter-load-failed`
- **Producer**: `window-decision.sh` (via `load-change-window-adapter.sh` dispatcher)
- **Exit code**: 0 (deny emitted via decision JSON)
- **Trigger**: The dispatcher (`load-change-window-adapter.sh`) exited non-zero — either the adapter
  name in `change_window.adapter` is unknown (not in `YCI_CW_ADAPTERS_SHIPPED`), the adapter
  directory is missing required files, or the profile could not be parsed by the dispatcher.
- **Message**:

  ```text
  cwg-adapter-load-failed: <dispatcher-stderr>
  ```

  `<dispatcher-stderr>` is the verbatim stderr output from `load-change-window-adapter.sh`, which
  includes the adapter name and the specific failure reason.

- **Operator guidance**: Check `change_window.adapter` in the customer profile. Shipped adapters
  are: `ical`, `json-schedule`, `always-open`, `none`. If the named adapter is `servicenow-cab` or
  another deferred adapter, it is listed in `YCI_CW_ADAPTERS_DEFERRED` and has not yet been
  implemented — use a shipped adapter or open an issue to track implementation. Confirm the adapter
  directory under `yci/skills/_shared/change-window-adapters/<name>/` is present and contains
  `ADAPTER.md` and `scripts/check.sh`.

---

### `cwg-adapter-error`

- **ID**: `cwg-adapter-error`
- **Producer**: `window-decision.sh` (adapter invocation and output validation)
- **Exit code**: 0 (deny emitted via decision JSON)
- **Trigger**: One of two conditions:
  1. The adapter's `scripts/check.sh` exited non-zero or produced empty stdout.
  2. The adapter emitted stdout that is not valid JSON or whose `decision` field is not one of
     `allowed`, `warning`, `blocked`.
- **Message** (non-zero exit or empty stdout):

  ```text
  cwg-adapter-error: <adapter-stderr|empty stdout|exit code N>
  ```

  **Message** (malformed output):

  ```text
  cwg-adapter-error: malformed adapter output: <validation-error>
  ```

- **Operator guidance**: Invoke the adapter's `check.sh` directly to reproduce the error:

  ```bash
  bash yci/skills/_shared/change-window-adapters/<name>/scripts/check.sh \
    --ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --source "<source-path>" \
    --timezone "<iana-tz>"
  ```

  Check that the source file (`.ics` or `.json`) exists, is readable, and is well-formed. For the
  `ical` adapter, verify that `DTSTART`/`DTEND` use a supported format. For `json-schedule`,
  validate the file against `json-schedule/schema.json`.

---

### `cwg-destructive-in-blackout`

- **ID**: `cwg-destructive-in-blackout`
- **Producer**: `pretool.sh` (dispatched when `cwg_decide` returns `decision: blocked`)
- **Exit code**: 0 (deny emitted via decision JSON)
- **Trigger**: The active customer profile was loaded and the window-decision orchestrator returned
  `decision: blocked` from the configured adapter — the current UTC timestamp falls within a freeze
  or blackout window defined in the adapter's source (`.ics` file or JSON schedule).
- **Message**:

  ```text
  cwg-destructive-in-blackout: <adapter-rationale>
  ```

  `<adapter-rationale>` is the verbatim `rationale` field from the adapter's decision JSON, which
  includes the blackout window label, UTC-normalized start/end times, and adapter name.

- **Operator guidance**: The change window is active. Options:
  1. Wait until the blackout window ends and retry the call.
  2. If you have break-glass authorization, set `YCI_CWG_OVERRIDE=1` for the call and document the
     override in the engagement's change record.
  3. Use `YCI_CWG_DRY_RUN=1` to observe the block without enforcing, while the change is being
     approved.
  4. If the blackout schedule is incorrect, update the source file and verify with the adapter
     directly.

---

### `cwg-internal-error`

- **ID**: `cwg-internal-error`
- **Producer**: `pretool.sh` (catch-all for unexpected `cwg_decide` output)
- **Exit code**: 0 (deny emitted via decision JSON; fail-closed)
- **Trigger**: `window-decision.sh`'s `cwg_decide` returned a `decision` value that is not
  `allowed`, `warning`, or `blocked` — an unexpected/malformed decision string. The hook fails
  closed to prevent accidental tool calls during an undefined state.
- **Message**:

  ```text
  cwg-internal-error: unexpected decision value '<decision>' from window-decision; failing closed
  ```

- **Operator guidance**: This indicates a bug in `window-decision.sh` or one of its adapter
  callsites. Set `YCI_CWG_DRY_RUN=1` to allow the call while investigating; do not use
  `YCI_CWG_OVERRIDE=1` as a permanent fix. File a bug report with the full stderr output and the
  adapter name from the customer profile.

---

## Style Guide

Error messages follow the same conventions as
`yci/hooks/customer-guard/references/error-messages.md`: all messages use a lowercase `cwg-<id>:`
prefix so operators immediately identify the hook as the error source regardless of surrounding
shell noise; multi-line bodies use a 2-space continuation indent; every `emit_deny` call in
`pretool.sh` passes a literal string with no untrusted variable arguments embedded directly into the
format string; and every deny message must end with an actionable hint telling the operator exactly
what to do next.
