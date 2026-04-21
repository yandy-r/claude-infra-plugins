# yci Customer-Profile Error Messages

This file is the canonical source of user-visible error strings for the
`customer-profile` skill. Scripts emit these strings verbatim; tests assert
against them verbatim. **Change here first, then update scripts and tests.**
Enumerated errors derive from PRD §11.1 (resolver refusal), §5.2 (schema errors),
and §11.9 (secrets / data-root location). Adding a new error requires updating
this catalog, the emitting script, and the corresponding test in the same change.

---

## Exit-Code Convention

| Exit | Meaning                                                                               |
| ---- | ------------------------------------------------------------------------------------- |
| 0    | success                                                                               |
| 1    | resolver refusal or user-input error (invalid id, overwrite refused, etc.)            |
| 2    | schema violation (malformed YAML, missing required keys, unknown enum value)          |
| 3    | runtime / environment error (pyyaml missing, unwritable data root, permission denied) |

---

## Error Catalog

### Resolver (`resolve-customer.sh` — task 3.2)

---

### `resolver-no-active-customer`

- **ID**: `resolver-no-active-customer`
- **Producer**: `resolve-customer.sh`
- **Exit code**: 1
- **Trigger**: all three resolution tiers exhausted — `$YCI_CUSTOMER` unset/empty,
  no `.yci-customer` dotfile found from `$PWD` up to `$HOME`, and `state.json`
  either absent or has no non-empty `.active` field.
- **Message**:

  ```
  yci: no active customer.
    $YCI_CUSTOMER: unset
    .yci-customer: not found (searched from <cwd> up to <stop>)
    state.json: no active customer at <path>
  Run `/yci:init <customer>` to create a profile, or `/yci:switch <customer>` to activate one.
  ```

  When `$YCI_CUSTOMER` was set but rejected because it was whitespace-only,
  replace `unset` with `empty (whitespace-only)`.

- **Test coverage**: `test_resolve_customer.sh::test_no_active_customer`,
  `test_resolve_customer.sh::test_whitespace_env_shows_empty_hint`

---

### `resolver-invalid-id-format`

- **ID**: `resolver-invalid-id-format`
- **Producer**: `resolve-customer.sh`
- **Exit code**: 1
- **Trigger**: a customer ID was resolved from one of the tiers but fails the
  format constraint — allowed pattern is `[a-z0-9][a-z0-9-]*` (lowercase
  alphanumeric, interior hyphens only, no leading hyphen, no underscore, no
  uppercase). Example: `ACME`, `acme_corp`, `-acme`.
- **Message**:

  ```
  yci: invalid customer id: '<customer>'
    allowed pattern: [a-z0-9][a-z0-9-]*  (lowercase, hyphens only)
  Check $YCI_CUSTOMER, your .yci-customer dotfile, or state.json .active field.
  ```

- **Test coverage**: `test_resolve_customer.sh::test_invalid_id_format`

---

### `resolver-walkup-escaped-home`

> **Decision**: `precedence.md` specifies that the dotfile walk-up **stops** when
> the current directory equals `$HOME` (or `/`, whichever is first) and does NOT
> ascend past `$HOME`. When a dotfile exists only above `$HOME`, the walk reaches
> `$HOME` without finding one, treating the result as "not found" — a **silent
> fall-through** to Tier 3 (MRU), not an explicit error. This error ID is
> therefore **not emitted**. The case is covered by `resolver-no-active-customer`
> (when MRU also fails) or by a clean resolution from Tier 3.
>
> Test coverage: `test_resolve_customer.sh::test_walk_stops_at_home` confirms
> the walk-stops-at-HOME behavior without expecting an explicit error message.

---

### Data-Root Resolver (`resolve-data-root.sh` — task 3.1)

---

### `dataroot-unwritable`

- **ID**: `dataroot-unwritable`
- **Producer**: `resolve-data-root.sh`
- **Exit code**: 3
- **Trigger**: the resolved data-root path exists but is not writable by the
  current process (permission check fails).
- **Message**:

  ```
  yci: data root is not writable: <path>
    check directory permissions or set a writable path via --data-root or $YCI_DATA_ROOT
  ```

- **Test coverage**: `test_resolve_data_root.sh::test_dataroot_unwritable`

---

### `dataroot-invalid-path`

- **ID**: `dataroot-invalid-path`
- **Producer**: `resolve-data-root.sh`
- **Exit code**: 3
- **Trigger**: the `--data-root` argument (or `$YCI_DATA_ROOT` value) cannot be
  canonicalized — the path is syntactically invalid, contains null bytes, or
  `realpath` / equivalent normalization fails.
- **Message**:

  ```
  yci: cannot resolve data root path: '<path>'
    ensure the path is a valid absolute or expandable path
  ```

- **Test coverage**: `test_resolve_data_root.sh::test_dataroot_invalid_path`

---

### Loader (`load-profile.sh` — task 5.1)

---

### `loader-missing-file`

- **ID**: `loader-missing-file`
- **Producer**: `load-profile.sh`
- **Exit code**: 1
- **Trigger**: the expected profile YAML file does not exist at the resolved path
  `<data-root>/profiles/<customer-id>.yaml`.
- **Message**:

  ```
  yci: profile not found: <path>
    create a new profile with `/yci:init <customer>` or copy _template.yaml
  ```

- **Test coverage**: `test_load_profile.sh::test_missing_file`

---

### `loader-malformed-yaml`

- **ID**: `loader-malformed-yaml`
- **Producer**: `load-profile.sh`
- **Exit code**: 2
- **Trigger**: `python3 -c "import yaml; yaml.safe_load(...)"` raises a
  `yaml.YAMLError` — the file is not valid YAML.
- **Message**:

  ```
  yci: malformed YAML in profile: <path>
    <parse-error>
  Fix the YAML syntax and retry.
  ```

  `<parse-error>` is the verbatim first line of the pyyaml exception message.

- **Test coverage**: `test_load_profile.sh::test_malformed_yaml`

---

### `loader-missing-required-key`

- **ID**: `loader-missing-required-key`
- **Producer**: `load-profile.sh`
- **Exit code**: 2
- **Trigger**: a required top-level key (see `schema.md` — `customer`,
  `engagement`, `compliance`, `inventory`, `approval`, `deliverable`, `safety`)
  or a required nested key within those subtrees is absent from the loaded YAML.
- **Message**:

  ```
  yci: missing required field '<field>' in profile: <path>
    see yci/skills/customer-profile/references/schema.md for required fields
  ```

- **Test coverage**: `test_load_profile.sh::test_missing_required_key`

---

### `loader-invalid-enum-value`

- **ID**: `loader-invalid-enum-value`
- **Producer**: `load-profile.sh`
- **Exit code**: 2
- **Trigger**: a field that accepts a fixed enum set receives a value not in that
  set. Enum fields and their canonical allowed values (from `schema.md`):
  - `compliance.regime`: `hipaa`, `pci`, `sox`, `soc2`, `iso27001`, `nist`,
    `commercial`, `none`
  - `engagement.type`: `discovery`, `design`, `implementation`, `ongoing`
  - `safety.default_posture`: `dry-run`, `review`, `apply`
  - `safety.scope_enforcement`: `warn`, `block`, `off`
  - `change_window.adapter`: `ical`, `servicenow-cab`, `json-schedule`,
    `always-open`, `none`
  - `deliverable.handoff_format`: `git-repo`, `zip`, `confluence`, `pdf-bundle`
- **Message**:

  ```
  yci: invalid value for '<field>': '<value>'
    allowed values: <allowed-list>
    see yci/skills/customer-profile/references/schema.md for the canonical enum lists
  ```

- **Test coverage**: `test_load_profile.sh::test_invalid_enum_value`

---

### `loader-pyyaml-missing`

- **ID**: `loader-pyyaml-missing`
- **Producer**: `load-profile.sh`
- **Exit code**: 3
- **Trigger**: `python3 -c "import yaml"` exits non-zero — the `pyyaml` library
  is not installed in the active Python environment.
- **Message**:

  ```
  yci: pyyaml not found — cannot parse YAML profiles
    pyyaml required — install via 'pip install pyyaml' or your distro's python3-yaml package
  ```

- **Test coverage**: `test_load_profile.sh::test_pyyaml_missing`

---

### State I/O (`state-io.sh` — task 3.3)

---

### `state-corrupt-json`

- **ID**: `state-corrupt-json`
- **Producer**: `state-io.sh`
- **Exit code**: 2
- **Trigger**: `state.json` exists but fails to parse as valid JSON (e.g.,
  truncated file, hand-edited corruption, encoding issue).
- **Message**:

  ```
  yci: corrupt state file: <path>
    state.json failed JSON parse — delete or repair the file to continue
  ```

- **Test coverage**: `test_state_io.sh::test_corrupt_json`

---

### `state-write-permission-denied`

- **ID**: `state-write-permission-denied`
- **Producer**: `state-io.sh`
- **Exit code**: 3
- **Trigger**: an attempt to write `state.json` fails with a filesystem
  permission error (EACCES / EPERM).
- **Message**:

  ```
  yci: cannot write state file: <path>
    permission denied — check directory ownership and mode (expected 0700)
  ```

- **Test coverage**: `test_state_io.sh::test_write_permission_denied`

---

### Initializer (`init-profile.sh` — task 5.1)

---

### `init-profile-exists`

- **ID**: `init-profile-exists`
- **Producer**: `init-profile.sh`
- **Exit code**: 1
- **Trigger**: the target profile YAML file `<data-root>/profiles/<customer-id>.yaml`
  already exists and `--force` was not passed.
- **Message**:

  ```
  yci: profile already exists: <path>
    pass --force to overwrite, or choose a different customer id
  ```

- **Test coverage**: `test_init_profile.sh::test_profile_exists`

---

### `init-invalid-customer-id`

- **ID**: `init-invalid-customer-id`
- **Producer**: `init-profile.sh`
- **Exit code**: 1
- **Trigger**: the customer ID argument passed to `init-profile.sh` fails the
  format constraint `[a-z0-9][a-z0-9-]*`.
- **Message**:

  ```
  yci: invalid customer id: '<customer>'
    allowed pattern: [a-z0-9][a-z0-9-]*  (lowercase, hyphens only)
  ```

- **Test coverage**: `test_init_profile.sh::test_invalid_customer_id`

---

### `init-reserved-id`

- **ID**: `init-reserved-id`
- **Producer**: `init-profile.sh`
- **Exit code**: 1
- **Trigger**: the customer ID starts with an underscore (e.g., `_internal`,
  `_template`), indicating a reserved namespace, and `--allow-reserved` was not
  passed.
- **Message**:

  ```
  yci: reserved customer id: '<customer>'
    ids starting with '_' are reserved for internal use
    pass --allow-reserved to create a reserved-namespace profile
  ```

- **Test coverage**: `test_init_profile.sh::test_reserved_id`

---

### Renderer (`render-whoami.sh` — task 5.1)

---

### `whoami-no-active-customer`

- **ID**: `whoami-no-active-customer`
- **Producer**: `render-whoami.sh`
- **Exit code**: 1
- **Trigger**: same root cause as `resolver-no-active-customer` — the resolver
  returns exit 1 before the renderer can display any profile. The renderer
  surfaces a shorter, command-oriented message appropriate for interactive use.
- **Message**:

  ```
  yci: no active customer — run /yci:init <customer> or /yci:switch <customer>
  ```

- **Test coverage**: `test_render_whoami.sh::test_no_active_customer`

---

## Style Guide

- **`yci:` prefix**: every message begins with `yci:` so users immediately
  identify which tool produced the error, regardless of shell noise around it.
- **Angle-bracket placeholders**: dynamic parts appear as `<placeholder>` in this
  catalog (e.g., `<path>`, `<field>`, `<customer>`, `<value>`). Scripts substitute
  the actual value at emit time; tests match on the static prefix/suffix to avoid
  brittle string copies.
- **No trailing period on the final line**: shell error convention; the terminal
  newline is sufficient sentence termination.
- **Multi-line continuation indent**: additional lines in a message use a 2-space
  indent so the error block is visually grouped when printed to a terminal.
- **Remediation hint required for every exit-1 error**: every user-input or
  resolver-refusal error must tell the user what to do next. Exit-2 (schema) and
  exit-3 (runtime) errors should include a hint where a concrete action exists.

---

## Test-Assertion Helpers

The test harness at `tests/helpers.sh` (task 5.2) will expose an
`assert_error_id <id>` function that reads the `Message` block for the given
error ID from this file and matches the actual command output against it.
Tests reference errors by their catalog ID — never by copy-pasting the message
string — so that a single wording change here propagates to all assertions
automatically on the next test run.
