---
name: customer-profile
description: Load, switch, and scaffold yci customer profiles. Use when the user runs /yci:switch, /yci:whoami, or /yci:init — or asks to see/change/create the active customer context. Resolves the active customer via the 4-tier precedence chain ($YCI_CUSTOMER > .yci-customer dotfile > MRU > refuse) and persists state to <data-root>/state.json. All downstream yci skills depend on this one — it is the load-bearing primitive for customer isolation.
argument-hint: '{switch|whoami|init} [<customer>] [--data-root <path>] [--force] [--allow-reserved]'
allowed-tools:
  - Read
  - Write
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/customer-profile/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/*.sh:*)
  - Bash(cat:*)
  - Bash(ls:*)
  - Bash(test:*)
  - Bash(python3:*)
  - Bash(mkdir:*)
  - Bash(cp:*)
  - Bash(chmod:*)
---

# yci:customer-profile Skill

This skill manages the active customer context for all yci workflows. It is the
load-bearing primitive for customer isolation — PRD §11.1 defines the authoritative
4-tier precedence chain (`$YCI_CUSTOMER` > `.yci-customer` dotfile > MRU state >
refuse) and PRD §5.2 defines the profile schema. Every downstream yci skill calls
`resolve-customer.sh` before touching any customer-scoped resource; a refusal from
that resolver propagates upward and aborts the workflow.

## Subcommands

The skill takes a MODE as its first positional argument. If MODE is missing or
unrecognised, print a one-line usage hint and exit 1.

- `switch <customer>` — resolve, load, and activate the named customer profile
- `whoami` — print the active customer context (who is currently active?)
- `init <customer>` — scaffold a new profile from `references/_template.yaml`

## Data Root

`<data-root>` resolves via `yci/skills/_shared/scripts/resolve-data-root.sh`:

1. `--data-root <path>` flag (highest precedence)
2. `$YCI_DATA_ROOT` env var
3. `~/.config/yci/` (default)

Do NOT hardcode the path anywhere — always call the helper. See the shared helper
for permission and canonicalization details.

## Precedence (switch and whoami)

Full spec: `references/precedence.md` (mirrors PRD §11.1).

Resolution stops at the first tier that yields a non-empty, valid value:

- **Tier 1** — `$YCI_CUSTOMER` env var (trimmed; set, non-empty, and valid wins)
- **Tier 2** — `.yci-customer` dotfile walk-up from `$PWD`; stops at `$HOME` or
  `/`, whichever comes first; never ascends past `$HOME`
- **Tier 3** — `state.json .active` field at `<data-root>/state.json` (MRU)
- **Tier 4** — REFUSE: emit `resolver-no-active-customer` to stderr, exit 1

Valid customer ID format: `[a-z0-9][a-z0-9-]*` (lowercase, hyphens only, no
leading hyphen, no underscore, no uppercase).

## Workflows

### Mode: switch

1. Validate the customer ID against `[a-z0-9][a-z0-9-]*`. On failure: emit
   `init-invalid-customer-id` (from `references/error-messages.md`) and exit 1.
2. Resolve data-root via `resolve-data-root.sh`.
3. Call `load-profile.sh <data-root> <customer>` to load and validate the YAML.
   - Profile not found → exit 1 with `loader-missing-file`.
   - Malformed YAML → exit 2 with `loader-malformed-yaml`.
   - Missing required key → exit 2 with `loader-missing-required-key`.
   - Unknown enum value → exit 2 with `loader-invalid-enum-value`.
4. On successful load, call `state_write_active <data-root> <customer>`
   (from `state-io.sh`) to persist the active customer.
   - Permission denied → exit 3 with `state-write-permission-denied`.
5. Print a one-line confirmation:
   `yci: switched to <customer> (<engagement.id>, <compliance.regime>, <safety.default_posture>)`
6. Exit 0.

### Mode: whoami

1. Resolve data-root via `resolve-data-root.sh`.
2. Call `resolve-customer.sh --data-root <data-root>` to determine the active
   customer via the 4-tier chain.
3. If the resolver exits 1 (refusal), surface the shorter command-oriented message
   `whoami-no-active-customer` from `references/error-messages.md` and exit 1.
4. Load the resolved profile via `load-profile.sh`.
5. Call `render-whoami.sh` to print the human-readable context summary.
6. Exit 0.

### Mode: init

1. Validate the customer ID against `[a-z0-9][a-z0-9-]*`. On failure: emit
   `init-invalid-customer-id` and exit 1.
2. Reject IDs starting with `_` (e.g., `_internal`, `_template`) unless
   `--allow-reserved` was passed. On rejection: emit `init-reserved-id` and exit 1.
3. Resolve data-root via `resolve-data-root.sh`.
4. Check whether `<data-root>/profiles/<customer>.yaml` already exists. If it does
   and `--force` was not passed: emit `init-profile-exists` and exit 1.
5. Call `init-profile.sh <data-root> <customer> [--force]` to copy the template.
6. Print a confirmation with:
   - The full path to the created file.
   - A pointer to `references/schema.md` for required fields.
   - A reminder to replace every `<TODO: ...>` placeholder before running
     `/yci:switch <customer>`.
7. Exit 0.

## Error Messages

All user-visible errors come from `references/error-messages.md`. When a script
exits non-zero, surface its stderr verbatim — do NOT reformat or add extra context.
The user must see the same text catalogued in the reference doc.

Exit-code convention (from `error-messages.md`):

| Exit | Meaning                                                         |
| ---- | --------------------------------------------------------------- |
| 0    | success                                                         |
| 1    | resolver refusal or user-input error (invalid id, overwrite)    |
| 2    | schema violation (malformed YAML, missing key, bad enum value)  |
| 3    | runtime / environment error (pyyaml missing, permission denied) |

## Prerequisites

The following scripts are **not yet installed** (land in B5):

- `scripts/load-profile.sh`
- `scripts/render-whoami.sh`
- `scripts/init-profile.sh`

Until B5 merges, the `switch`, `whoami`, and `init` workflows cannot complete.
If invoked before B5 lands, inform the user:

> "yci:customer-profile requires load-profile.sh, render-whoami.sh, and
> init-profile.sh (shipping in B5). Run `./scripts/validate.sh --only yci`
> to check installation status."

Then exit 1 without touching any data. The scripts already present
(`resolve-customer.sh`, `state-io.sh`, `profile-schema.sh`) are functional.

## Cross-References

- `references/schema.md` — profile schema (PRD §5.2 mirror)
- `references/precedence.md` — resolver precedence spec (PRD §11.1 mirror)
- `references/error-messages.md` — canonical error copy
- `references/_template.yaml` — init scaffold
- `scripts/resolve-customer.sh` — tier resolver
- `scripts/state-io.sh` — state.json atomic I/O
- `scripts/profile-schema.sh` — schema constants
- `../_shared/scripts/resolve-data-root.sh` — data-root helper

## When NOT to Use This Skill

- **Editing a profile** — users edit `<data-root>/profiles/<customer>.yaml` with
  their text editor. This skill does not provide an edit mode.
- **Listing all profiles** — no `/yci:list` yet; use `ls <data-root>/profiles/`.
- **Deleting a profile** — no `/yci:remove` yet; users delete the YAML file
  manually and prune `state.json` by switching to another customer (which rewrites
  `.active` and dedupes MRU).

## Security Reminders (PRD §11.9)

- Profiles **MUST NOT contain secrets**. Only `credential_ref` pointers into the
  active vaults subtree.
- The resolver's refusal path is load-bearing: every downstream yci hook calls
  `resolve-customer.sh` first and aborts on non-zero exit.
- The `.yci-customer` dotfile walk-up **never ascends past `$HOME`**, preventing
  ambient configuration from a shared or multi-user environment from leaking into
  the session.
