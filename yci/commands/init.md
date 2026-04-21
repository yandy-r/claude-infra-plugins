---
description: Scaffold a new yci customer profile from _template.yaml.
argument-hint: '<customer> [--data-root <path>] [--force] [--allow-reserved]'
allowed-tools:
  - Read
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/customer-profile/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/*.sh:*)
  - Bash(cat:*)
  - Bash(ls:*)
  - Bash(test:*)
  - Bash(cp:*)
  - Bash(chmod:*)
  - Bash(mkdir:*)
---

# /yci:init

Scaffold a new yci customer profile. Copies `yci/skills/customer-profile/references/_template.yaml` into `<data-root>/profiles/<customer>.yaml` with `<TODO: ...>` placeholders you fill in before switching.

## What it does

- Validates `<customer>` against `[a-z0-9][a-z0-9-]*` (lowercase start, no leading hyphen).
- Rejects reserved ids (`_internal`, `_template`, any id starting with `_`) unless `--allow-reserved`.
- Creates `<data-root>/profiles/` with mode `0700` if absent.
- Refuses if `<data-root>/profiles/<customer>.yaml` already exists, unless `--force`.
- Copies the template with mode `0600`.
- Prints confirmation:

  ```
  yci: scaffolded profile at <path>
    edit the <TODO: ...> placeholders, then run: /yci:switch <customer>
  ```

## Arguments

- `<customer>` — required. Profile id (e.g., `acme-corp`).
- `--data-root <path>` — optional. Overrides `$YCI_DATA_ROOT` and the default `~/.config/yci/`.
- `--force` — overwrite an existing profile.
- `--allow-reserved` — permit `_template`, `_internal`, or other underscore-prefixed ids. Use when importing fixture profiles; not recommended for day-to-day operation.

## Security

Profiles NEVER contain secrets (see PRD §11.9). The scaffold uses `credential_ref` placeholders pointing at your vault. Never paste an inline secret.

## Instructions

Load and follow the `yci:customer-profile` skill with mode `init` and $ARGUMENTS.
