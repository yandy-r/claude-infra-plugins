---
description: Load a yci customer profile and mark it active.
argument-hint: '<customer> [--data-root <path>]'
allowed-tools:
  - Read
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/customer-profile/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/*.sh:*)
  - Bash(cat:*)
  - Bash(test:*)
---

# /yci:switch

Load a yci customer profile from `<data-root>/profiles/<customer>.yaml` and mark it active.

## What it does

- Validates `<customer>` against the id format `[a-z0-9][a-z0-9-]*`.
- Loads and schema-validates the YAML profile (see `yci:customer-profile` → `references/schema.md`).
- Writes the resolved id to `<data-root>/state.json` and updates the MRU list.
- Prints a one-line confirmation: `yci: switched to <customer> (<engagement.id>, <compliance.regime>, <safety.default_posture>)`.

## Arguments

- `<customer>` — required. The profile id (e.g., `acme-corp`).
- `--data-root <path>` — optional. Overrides `$YCI_DATA_ROOT` and the `~/.config/yci/` default.

## Precedence for the active customer

This command SETS the active customer. Subsequent `/yci:whoami` calls without args read it back via the four-tier chain:

1. `$YCI_CUSTOMER` env var
2. `.yci-customer` dotfile (walk-up)
3. `<data-root>/state.json` `.active` field (what `/yci:switch` writes)
4. refuse

See `yci:customer-profile/references/precedence.md` for the full spec.

## Instructions

Load and follow the `yci:customer-profile` skill with mode `switch` and $ARGUMENTS.
