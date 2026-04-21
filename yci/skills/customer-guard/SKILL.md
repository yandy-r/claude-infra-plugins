---
name: customer-guard
description: Ad-hoc cross-customer isolation check. Runs the customer-isolation detection library against a single path or text blob and reports allow/deny with the same catalogued errors as the PreToolUse hook. Useful for validating pastes and test fixtures before running a tool that would otherwise trigger the guard.
argument-hint: '<path-or-text> [--dry-run] [--data-root <path>]'
allowed-tools:
  - Read
  - Bash(cat:*)
  - Bash(test:*)
  - Bash(bash:*)
  - Bash(python3:*)
---

# yci:customer-guard Skill

Ad-hoc cross-customer isolation checker. Runs the same detection library the
PreToolUse hook uses, against a single path or text blob supplied by the user,
and reports the allow/deny decision with the same catalogued error IDs.

## Instructions

### Step 1 — Parse arguments

Read `$ARGUMENTS`. Strip `--dry-run` and `--data-root <path>` flags and note
their values if present. The remaining text is the input to check.

Detect the input type:

- **Path** — the remaining text starts with `/`, `~/`, `./`, or `../`.
- **Text blob** — anything else (including multi-line content).

### Step 2 — Resolve active customer

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/customer-profile/scripts/resolve-customer.sh"
```

If the script exits non-zero, print its stderr verbatim and abort — do NOT
proceed without a resolved customer.

Capture the customer ID from stdout as `ACTIVE_CUSTOMER`.

### Step 3 — Resolve data root

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/resolve-data-root.sh"
```

If `--data-root <path>` was present in `$ARGUMENTS`, pass `--data-root <path>`
to the script instead. Capture the result as `DATA_ROOT`.

### Step 4 — Construct a synthetic PreToolUse payload

Build a JSON object to feed the detection library:

- **Path input**:

  ```json
  { "tool_name": "Read", "tool_input": { "file_path": "<path>" }, "cwd": "<current-working-dir>" }
  ```

  Use `bash -c 'pwd'` to obtain `<current-working-dir>`.

- **Text blob input**:
  ```json
  { "tool_name": "Write", "tool_input": { "content": "<text>" } }
  ```
  Escape the text as a valid JSON string value.

### Step 5 — Run the detection library

Source `yci/skills/_shared/customer-isolation/detect.sh` in a subshell, with
the resolved environment variables set:

```bash
bash -c '
  export YCI_ACTIVE_CUSTOMER="<ACTIVE_CUSTOMER>"
  export YCI_DATA_ROOT_RESOLVED="<DATA_ROOT>"
  source "${CLAUDE_PLUGIN_ROOT}/skills/_shared/customer-isolation/detect.sh"
  echo "<synthetic-payload>" | isolation_check_payload
'
```

Capture the full stdout as `DECISION_JSON`.

### Step 6 — Report the decision

Print `DECISION_JSON` verbatim.

If the decision is `deny` (the JSON contains `"decision": "deny"`), also print
a human-readable summary. The emitted JSON shape is:

```json
{
  "decision": "deny",
  "collision": {
    "active": "<active-customer>",
    "foreign": "<foreign-customer>",
    "kind": "path" | "token",
    "evidence": "<offending-path-or-token>",
    "resolved": "<realpath>",          // path kind only
    "category": "<fingerprint-category>" // token kind only
  }
}
```

1. Extract `collision.kind` from the JSON.
2. If `kind == "path"`:
   - Error ID: `guard-path-collision`
   - Extract `collision.active`, `collision.foreign`, `collision.evidence`,
     `collision.resolved` from the JSON.
   - Print the full message from
     `yci/hooks/customer-guard/references/error-messages.md` for
     `guard-path-collision`, substituting the extracted values.
3. If `kind == "token"`:
   - Error ID: `guard-fingerprint-collision`
   - Extract `collision.active`, `collision.foreign`, `collision.category`,
     `collision.evidence` from the JSON.
   - Print the full message from
     `yci/hooks/customer-guard/references/error-messages.md` for
     `guard-fingerprint-collision`, substituting the extracted values.

### Step 7 — Honor --dry-run

If `--dry-run` was present in `$ARGUMENTS`, append the following note after the
decision output:

```
note: --dry-run active — this check is advisory only and did not consult the
actual hook runner. No tool call was blocked.
```

## Error Messages

All user-visible errors use the catalog in
`yci/hooks/customer-guard/references/error-messages.md`. Surface script stderr
verbatim — do NOT reformat or add extra context.

## Cross-References

- `yci/skills/_shared/customer-isolation/detect.sh` — detection library
- `yci/skills/customer-profile/scripts/resolve-customer.sh` — tier resolver
- `yci/skills/_shared/scripts/resolve-data-root.sh` — data-root helper
- `yci/hooks/customer-guard/references/error-messages.md` — canonical error copy

## Security

This skill is a CHECKER — it does not mutate files, write profiles, or activate
customers. Its `allowed-tools` list intentionally excludes Write, Edit,
MultiEdit, and NotebookEdit.
