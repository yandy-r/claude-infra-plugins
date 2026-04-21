---
description: Print the active yci customer (id, display name, engagement, compliance regime, safety posture).
argument-hint: '[--data-root <path>]'
allowed-tools:
  - Read
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/customer-profile/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/*.sh:*)
  - Bash(cat:*)
  - Bash(test:*)
---

# /yci:whoami

Print the active yci customer context — a human-readable summary of who `yci` currently thinks you are operating for.

## What it does

- Resolves the active customer via the four-tier precedence chain:
  1. `$YCI_CUSTOMER` env var
  2. `.yci-customer` dotfile (walk-up from CWD, stopping at `$HOME`)
  3. `<data-root>/state.json` `.active` field
  4. refuse — no active customer
- Loads and schema-validates the resolved profile.
- Renders a concise summary:

```
yci: active customer = <customer.id>
  display name   : <customer.display_name>
  engagement     : <engagement.id> (<engagement.type>, SOW <engagement.sow_ref>)
  dates          : <engagement.start_date> → <engagement.end_date>
  compliance     : <compliance.regime> (evidence schema v<compliance.evidence_schema_version>)
  safety posture : <safety.default_posture>  (scope: <safety.scope_enforcement>, change-window-required: <safety.change_window_required>)
  scope tags     : <engagement.scope_tags joined by ", ">
```

## Arguments

- `--data-root <path>` — optional. Overrides `$YCI_DATA_ROOT` and the default `~/.config/yci/`.

## Failure modes

- No active customer → exit 1 with the canonical refusal message pointing at `/yci:init` or `/yci:switch`.
- Stored active customer's profile is missing or malformed → propagate the loader error.

## Instructions

Load and follow the `yci:customer-profile` skill with mode `whoami` and $ARGUMENTS.
