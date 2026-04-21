# Customer-Scope Precedence Specification

> **Canonical reference**: PRD §11.1 — "Authoritative customer-scope source".
> This document translates that section into an implementable spec for
> `resolve-customer.sh` (task 3.2), its unit tests, and every `yci` hook that
> must determine "which customer are we in?"

## Introduction

`resolve-customer.sh` is the single entry point for determining the active
customer ID in any `yci` skill, hook, or command. It must be called before
touching any customer-scoped resource. The resolver returns exactly one
customer ID string (via stdout) or exits with code 1.

**Why this matters**: cross-customer context leakage is the #1 security
concern for `yci` (PRD §2, threat model item 1 — "career-ending if it
happens"). A deterministic, auditable precedence chain ensures that any
given invocation can only be associated with one customer, that explicit
signals always override ambient ones, and that a silent fallback to the
wrong customer is structurally impossible. If no tier resolves, the resolver
refuses rather than guessing.

---

## Precedence Chain

Resolution stops at the first tier that yields a non-empty, valid value.

```
Tier 1 — $YCI_CUSTOMER env var             (explicit, session-scoped)
    │
    ▼ (only if unset or empty)
Tier 2 — .yci-customer dotfile walk-up     (project-scoped)
    │
    ▼ (only if not found or all blank/comments)
Tier 3 — MRU: state.json .active field     (session-state, last switched)
    │
    ▼ (only if absent or empty)
Tier 4 — REFUSE (exit 1)
```

---

## Per-Tier Specification

### Tier 1 — `$YCI_CUSTOMER` Environment Variable

**Signal**: set by the operator for session-scoped or pipeline-scoped overrides
(e.g., tmux per-customer windows, CI pipelines).

**Accept condition**: the variable is set AND its value after trimming leading
and trailing whitespace is non-empty.

**Rejection cases** (fall through to Tier 2):

- `$YCI_CUSTOMER` is unset.
- `$YCI_CUSTOMER` is the empty string (`YCI_CUSTOMER=""`).
- `$YCI_CUSTOMER` contains only whitespace (`YCI_CUSTOMER="   "`).

**Case sensitivity**: the value is case-sensitive. `ACME` and `acme` are
different strings.

**Format validation** (performed AFTER tier selection, not during resolution):
the resolver returns the raw trimmed string. The _loader_ (not the resolver)
validates that the ID matches the required format and that a profile file
exists. Format reference (for documentation and test purposes):

```
[a-z0-9][a-z0-9-]*
```

Examples of valid IDs: `acme`, `acme-healthcare`, `bigbank-cdc`.
Examples of invalid IDs: `ACME` (uppercase), `acme_corp` (underscore),
`-acme` (leading hyphen), `_internal` (leading underscore).

> **Reserved IDs** — IDs starting with `_` (e.g. `_internal`, `_template`) are
> reserved for template/example use and rejected by the regex above. See
> `init-profile.sh` `--allow-reserved` and the `init-reserved-id` entry in
> `error-messages.md` for the init-side policy.
> The resolver does NOT validate format or profile existence. It returns the
> trimmed string. Format validation and profile loading are the caller's
> responsibility.

---

### Tier 2 — `.yci-customer` Dotfile Walk-Up

**Signal**: a plain-text file in the project directory (or any ancestor)
declaring the customer for that directory tree.

**Algorithm**:

1. Start at `$PWD`. Resolve to an absolute path.
2. Look for `.yci-customer` in the current directory.
3. If not present, ascend one level (`dirname`). Repeat.
4. Stop (not found) when the current directory equals `$HOME` OR equals `/` —
   whichever is reached first.
5. **Never ascend past `$HOME`.** If the dotfile exists only in a parent of
   `$HOME`, it is ignored. This prevents picking up someone else's home
   directory configuration.

**When the file is found**:

- Read the file.
- Skip lines that are empty or start with `#` (comment lines).
- Take the first non-skipped line.
- Trim leading and trailing whitespace.
- If the trimmed value is non-empty, use it as the customer ID.
- If the file has no non-empty, non-comment lines, treat it as "not found"
  and continue the walk-up (the walk does NOT stop — ascend and look again).

**File format example**:

```
# This project is scoped to Acme Healthcare
# Last updated 2026-03-01
acme-healthcare
```

**Edge cases**:

- Empty file → treat as not found; continue walk.
- Whitespace-only file → treat as not found; continue walk.
- All-comment file → treat as not found; continue walk.
- Multiple non-comment lines → only the first non-empty, non-comment line
  is used; the rest are ignored.

---

### Tier 3 — MRU from `state.json`

**Signal**: the last customer activated via `/yci:switch <id>` or equivalent.
Stored in `<data-root>/state.json`.

**`<data-root>` resolution**: delegated to `resolve-data-root.sh` (task 3.1).
The resolver accepts `--data-root <path>` as a pass-through to that helper.
The path is NOT hardcoded.

**State file structure** (relevant fields):

```json
{
  "active": "acme-healthcare",
  "mru": ["acme-healthcare", "bigbank-cdc", "widgetco"]
}
```

**Accept condition**:

- `state.json` exists and is valid JSON.
- `.active` field is present, non-null, and non-empty after trim.

**Rejection cases** (fall through to Tier 4):

- `state.json` does not exist.
- `state.json` exists but is not valid JSON (parse error → treat as "no MRU";
  emit a warning to stderr).
- `.active` field is absent.
- `.active` is `null` or an empty string.

**Important**: the `.mru` array is history only. It is consumed by
`/yci:whoami --history` (future skill) and MUST NOT be used as a fallback
here. The MRU tier means "the most recently switched customer" — that is
`.active`, exclusively.

---

### Tier 4 — Refusal

When all three tiers fail to yield a customer ID, the resolver emits the
canonical error message to **stderr** and exits with code **1**.

Exit code 1 is reserved for "no customer resolved." Schema/format errors
exit with code 2.

---

## Error Copy

The exact text emitted on refusal (to stderr):

```
yci: no active customer.
  $YCI_CUSTOMER: unset
  .yci-customer: not found (searched from <cwd> up to <stop>)
  state.json: no active customer at <path>
Run `/yci:init <customer>` to create a profile, or `/yci:switch <customer>` to activate one.
```

**Placeholder substitution**:

| Placeholder | Substituted with                                            |
| ----------- | ----------------------------------------------------------- |
| `<cwd>`     | Absolute path of `$PWD` at invocation time                  |
| `<stop>`    | The directory where the walk stopped: either `$HOME` or `/` |
| `<path>`    | Absolute path of the `state.json` file that was checked     |

If `$YCI_CUSTOMER` was set but rejected (whitespace-only), replace
`unset` with `empty (whitespace-only)` to aid debugging.

This error text is the canonical form. `error-messages.md` (task 2.1) will
register it formally; this file is the source of truth for the shape.

---

## Data-Root Interaction

`<data-root>` is resolved at runtime by
`yci/skills/_shared/scripts/resolve-data-root.sh` (task 3.1). Resolution
order for that helper (not this resolver's concern, documented for
cross-reference):

1. `--data-root <path>` CLI flag.
2. `$YCI_DATA_ROOT` env var.
3. Default: `~/.config/yci/`.

`resolve-customer.sh` accepts `--data-root <path>` and forwards it to
`resolve-data-root.sh` when constructing the `state.json` path. The data
root is never hardcoded in this resolver.

---

## Security Invariants

The following properties MUST hold at all times:

- **No ascent past `$HOME`**: the dotfile walk never reads files in parent
  directories of `$HOME`. Prevents ambient configuration from a shared or
  multi-user environment from leaking into the session.

- **Explicit beats ambient**: Tier 1 (env) always wins over Tier 2 (dotfile)
  always wins over Tier 3 (MRU). A dotfile can never override an explicit
  env var. MRU can never override a dotfile.

- **Empty/whitespace is unset**: in all three tiers, a value that is empty
  or whitespace-only after trim is treated as "not provided" and the resolver
  falls through to the next tier. There is no "empty string customer."

- **Resolver returns ID only**: `resolve-customer.sh` outputs the customer ID
  string and nothing else. It does NOT load the profile YAML, validate that the
  profile file exists, or set any side-effect state. Those are the loader's
  and hook's responsibilities.

- **Refusal exits 1**: a resolver that cannot find a customer MUST exit 1.
  Exit code 0 means "a customer ID was printed to stdout." Callers MUST
  treat a non-zero exit as a hard failure and propagate it.

- **User-input errors exit 1**: invalid ID characters in `$YCI_CUSTOMER`, the
  dotfile, or `state.json`'s `.active` field exit 1 (same code as refusal) —
  this is a user-provided-data error, indistinguishable at the shell level
  from "no customer found." Canonical message: `resolver-invalid-id-format` in
  `error-messages.md`.

- **Data corruption exits 2**: `state.json` that exists but fails JSON parse
  exits 2 (canonical: `state-corrupt-json`). This is distinct from "no
  state.json found" (treated as no-MRU, falls through to refusal = exit 1).

---

## Test-Case Matrix

Every case below MUST have a corresponding unit test in `test_resolve_customer.sh`.

| Case                      | `$YCI_CUSTOMER`    | Dotfile at `$CWD`             | Dotfile at ancestor    | `state.json.active` | Expected result                   |
| ------------------------- | ------------------ | ----------------------------- | ---------------------- | ------------------- | --------------------------------- |
| env wins                  | `acme`             | `beta`                        | —                      | `gamma`             | `acme`                            |
| dotfile at cwd            | —                  | `beta`                        | —                      | `gamma`             | `beta`                            |
| dotfile at ancestor       | —                  | —                             | `beta` (in `$PWD/..`)  | `gamma`             | `beta`                            |
| mru only                  | —                  | —                             | —                      | `gamma`             | `gamma`                           |
| all empty                 | —                  | —                             | —                      | —                   | refuse (exit 1)                   |
| walk stops at `$HOME`     | —                  | —                             | `beta` (above `$HOME`) | —                   | refuse (exit 1)                   |
| empty env is ignored      | `""`               | `beta`                        | —                      | —                   | `beta`                            |
| whitespace-only dotfile   | —                  | `"   \n"`                     | `beta` (ancestor)      | —                   | `beta`                            |
| comment-only dotfile      | —                  | `"# comment\n"`               | `beta` (ancestor)      | —                   | `beta`                            |
| invalid id format         | `ACME` (uppercase) | —                             | —                      | —                   | refuse with "invalid id" (exit 2) |
| missing state.json        | —                  | —                             | —                      | (file absent)       | refuse (exit 1)                   |
| state.json no `.active`   | —                  | —                             | —                      | `{}`                | refuse (exit 1)                   |
| state.json `.active` null | —                  | —                             | —                      | `{"active":null}`   | refuse (exit 1)                   |
| whitespace-only env       | `"   "`            | `beta`                        | —                      | —                   | `beta`                            |
| multi-line dotfile        | —                  | `"# comment\nreal-id\nother"` | —                      | —                   | `real-id`                         |
