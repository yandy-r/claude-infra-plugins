# yci Customer-Guard Error Messages

This file is the canonical source of user-visible error strings for the
`customer-guard` hook. Scripts emit these strings verbatim; tests assert
against them verbatim. **Change here first, then update scripts and tests.**
Enumerated errors cover the full decision lifecycle: resolver refusal, path/fingerprint
collision detection, allowlist validation, dry-run banner, and runtime guard failures.
Adding a new error requires updating this catalog, the emitting script, and the
corresponding test in the same change.

---

## Exit-Code Convention

| Exit | Meaning                                                                                                                    |
| ---- | -------------------------------------------------------------------------------------------------------------------------- |
| 0    | success (hook emits decision JSON and exits 0 regardless of allow/deny outcome)                                            |
| 1    | unrecoverable refusal (e.g., no active customer + fail-closed default — hook exits non-zero instead of emitting deny JSON) |
| 2    | schema violation (malformed profile YAML)                                                                                  |
| 3    | runtime / environment error (malformed allowlist YAML, unwritable cache, missing dependency)                               |

---

## Error Catalog

---

### `guard-no-active-customer`

- **ID**: `guard-no-active-customer`
- **Producer**: `pretool.sh`
- **Exit code**: 0 in all paths (`pretool.sh` never exits non-zero — Claude Code
  reads the decision on stdout, and a non-zero exit would be interpreted as
  "hook errored" instead of "deny"). When `YCI_GUARD_FAIL_OPEN` is unset or `0`
  the hook emits the deny decision JSON below on stdout (fail-closed default).
  When `YCI_GUARD_FAIL_OPEN=1` the hook writes a stderr warning and exits 0
  with empty stdout (fail-open opt-in).
- **Trigger**: the active-customer resolver (`resolve-customer.sh`) exits
  non-zero — no `$YCI_CUSTOMER`, no `.yci-customer` dotfile, no `state.json` —
  so the hook cannot identify which customer's policy applies.
- **Message**:

  ```
  yci guard: no active customer; refusing to evaluate tool call fail-closed.
    set a customer with /yci:init <customer> or /yci:switch <customer>
    to allow evaluation without an active customer, set YCI_GUARD_FAIL_OPEN=1
  ```

- **Test coverage**: `test_pretool_no_active_customer.sh::test_fail_closed_default`

---

### `guard-profile-load-failed`

- **ID**: `guard-profile-load-failed`
- **Producer**: `inventory-fingerprint.py`
- **Exit code**: 2
- **Trigger**: the active or foreign customer's profile YAML cannot be parsed —
  either the file is syntactically invalid or `yaml.safe_load` raises an exception.
- **Message**:

  ```
  yci guard: failed to load profile YAML for customer '<customer>'.
    <parse-error>
  Verify the profile with /yci:whoami or fix the YAML syntax and retry.
  ```

  `<parse-error>` is the verbatim first line of the pyyaml exception message.

- **Test coverage**: `test_inventory_fingerprint.sh::test_malformed_profile`

---

### `guard-path-collision`

- **ID**: `guard-path-collision`
- **Producer**: `pretool.sh`
- **Exit code**: 0 (hook emits deny via decision JSON; script exits 0)
- **Trigger**: a candidate path, after symlink resolution and `realpath` normalization,
  resolves under another customer's canonical artifact root rather than the active
  customer's tree.
- **Message**:

  ```
  yci guard: cross-customer path collision.
    active customer:  <active-customer>
    foreign customer: <foreign-customer>
    offending path:   <original-path>
    resolved to:      <resolved-path>
  To allow this path, add it to <data-root>/profiles/<active-customer>.allowlist.yaml:
    paths:
      - <resolved-path>  # note: SOW/ticket reference required
  ```

- **Test coverage**: `test_pretool_deny_path.sh::test_path_collision`

---

### `guard-fingerprint-collision`

- **ID**: `guard-fingerprint-collision`
- **Producer**: `pretool.sh`
- **Exit code**: 0 (hook emits deny via decision JSON; script exits 0)
- **Trigger**: a candidate token extracted from the tool input matches another
  customer's fingerprint bundle (hostname, IP, account ID, namespace, etc.).
- **Message**:

  ```
  yci guard: cross-customer identifier collision.
    active customer:  <active-customer>
    foreign customer: <foreign-customer>
    category:         <fingerprint-category>
    offending token:  <token>
  To allow this token, add it to <data-root>/profiles/<active-customer>.allowlist.yaml:
    tokens:
      - <token>  # note: SOW/ticket reference required
  ```

- **Test coverage**: `test_pretool_deny_fingerprint.sh::test_fingerprint_collision`

---

### `guard-allowlist-malformed`

- **ID**: `guard-allowlist-malformed`
- **Producer**: `allowlist.sh`
- **Exit code**: 3
- **Trigger**: the allowlist YAML file at the expected path exists but fails to
  parse — `yaml.safe_load` raises an exception indicating malformed YAML.
- **Message**:

  ```
  yci guard: allowlist YAML at '<path>' is malformed.
    <parse-error>
  Reproduce the error with: python3 -c "import yaml; yaml.safe_load(open('<path>'))"
  ```

  `<parse-error>` is the verbatim first line of the pyyaml exception message.

- **Test coverage**: `test_allowlist.sh::test_malformed`

---

### `guard-dry-run-would-block`

- **ID**: `guard-dry-run-would-block`
- **Producer**: `pretool.sh`
- **Exit code**: 0 (hook emits allow JSON on stdout; would-block event written to stderr and audit log)
- **Trigger**: `YCI_GUARD_DRY_RUN=1` is set AND a path collision or fingerprint
  collision would otherwise cause the hook to emit a deny decision.
- **Message**:

  ```
  YCI GUARD: DRY-RUN MODE ACTIVE — would-block logged to <path>.
    tool call would have been denied (collision detected)
    audit entry written to: <path>
    set YCI_GUARD_DRY_RUN=0 or unset to enforce blocking
  ```

- **Test coverage**: `test_pretool_dry_run.sh::test_dry_run_would_block`

---

### `guard-missing-tool-input`

- **ID**: `guard-missing-tool-input`
- **Producer**: `pretool.sh`
- **Exit code**: 0 (emits warn to stderr and allows by default; exits 1 under `YCI_GUARD_STRICT=1`)
- **Trigger**: the JSON received on stdin is missing expected keys (e.g., no
  `tool_input` field), making it impossible to evaluate the call for collisions.
- **Message**:

  ```
  yci guard: tool input missing expected fields; skipping evaluation.
    received keys: <key-list>
    set YCI_GUARD_STRICT=1 to fail-closed on malformed hook input
  ```

- **Test coverage**: `test_pretool_allow.sh::test_missing_fields_fail_open`

---

### `guard-symlink-escape`

- **ID**: `guard-symlink-escape`
- **Producer**: `pretool.sh`
- **Exit code**: 0 (hook emits deny via decision JSON; script exits 0)
- **Trigger**: a path argument is located inside the active customer's directory
  tree by string prefix, but `realpath` resolves the symlink chain to a location
  under a foreign customer's canonical root.
- **Message**:

  ```
  yci guard: symlink escape into another customer's tree.
    link:             <link-path>
    resolved to:      <resolved-path>
    foreign customer: <foreign-customer>
  Remove or retarget the symlink; cross-customer symlinks are not permitted.
  ```

- **Test coverage**: `test_pretool_symlink_escape.sh::test_symlink_escape`

---

## Style Guide

Error messages in this catalog follow the same conventions as
`yci/skills/customer-profile/references/error-messages.md`: all messages use a
lowercase `yci guard:` prefix so users immediately identify the hook as the
error source regardless of surrounding shell noise; multi-line bodies use a
2-space continuation indent so the block is visually grouped at the terminal;
every `printf` in the emitting script is written as a separate call per line so
variable arguments never leak unsafely into the format string; and every
exit-1 error (unrecoverable refusal) must end with an actionable hint line
telling the operator exactly what to do next.

---

## Test-Assertion Helpers

The test harness exposes an `assert_error_id <id> "$stderr"` function that
locates the entry for `<id>` in this file, extracts the first code-block line
after the `- **ID**:` bullet (stripping anything from the first `<` character
onward), and greps `$stderr` for that literal prefix. Because extraction strips
from `<` onward, every `Message:` code block's first line **must** contain
distinctive free text before any `<placeholder>` token — the guard prefix
`yci guard: <distinctive phrase>` is what the assertion actually matches. Tests
therefore reference errors by catalog ID only and never copy-paste message
strings, so a single wording change here propagates to all assertions on the
next test run.
