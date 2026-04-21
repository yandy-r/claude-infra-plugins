---
description: Ad-hoc cross-customer isolation check for a path or text blob using the customer-guard detection library.
argument-hint: '<path-or-text> [--dry-run] [--data-root <path>]'
allowed-tools:
  - Read
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/customer-guard/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/customer-profile/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/*.sh:*)
  - Bash(cat:*)
  - Bash(test:*)
---

# /yci:guard-check

Run a one-off cross-customer isolation check against a path or text blob. Wraps the `yci:customer-guard` skill, which invokes the same detection library the PreToolUse hook uses.

## What it does

- Detects whether the input looks like a filesystem path or a text blob.
- Resolves the active customer and data root.
- Constructs a synthetic PreToolUse payload and runs it through the customer-isolation detection library.
- Reports the allow/deny decision JSON with the same catalogued errors as the PreToolUse hook.

## Arguments

- `<path-or-text>` — required. A filesystem path (starts with `/`, `~/`, `./`, or `../`) or a text blob (any other input, including multi-line content).
- `--dry-run` — advisory check only; does not consult the actual hook runner.
- `--data-root <path>` — override `$YCI_DATA_ROOT` and the default `~/.config/yci/`.

## Instructions

Load and follow the `yci:customer-guard` skill, passing through `$ARGUMENTS`.
