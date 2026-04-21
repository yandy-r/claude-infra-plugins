# yci blast-radius Error Messages

This file is the canonical source of user-visible error strings for the
`blast-radius` skill. Scripts emit these strings verbatim; tests assert against
them verbatim. **Change here first, then update scripts and tests.**

Error families and the scripts that emit them:

| Family prefix | Emitting script                                         |
| ------------- | ------------------------------------------------------- |
| `br-*`        | `SKILL.md` orchestration (flag parsing, output routing) |
| `adapter-*`   | `scripts/adapter-file.sh`                               |
| `reason-*`    | `scripts/reason.sh`                                     |
| `render-*`    | `scripts/render-markdown.sh`                            |

Errors from `resolve-customer.sh`, `load-profile.sh`, and `resolve-data-root.sh`
are surfaced verbatim from the `customer-profile` skill's error catalogue — they
are not repeated here. See
`../customer-profile/references/error-messages.md` for those entries.

---

## Exit-Code Convention

| Exit | Meaning                                                                              |
| ---- | ------------------------------------------------------------------------------------ |
| 0    | success                                                                              |
| 1    | user-input error or missing resource (file not found, no active customer)            |
| 2    | schema violation (malformed file, missing required field, bad enum, unknown adapter) |
| 3    | runtime / environment error (pyyaml missing, permission denied)                      |

---

## Error Catalog

### Skill orchestration (`SKILL.md` flag parsing and output routing)

---

### `br-missing-change-file`

- **ID**: `br-missing-change-file`
- **Producer**: skill orchestration
- **Exit code**: 1
- **Trigger**: `--change-file` flag was not provided when invoking the skill.
- **Message**:

  ```
  yci: --change-file <path> is required
    provide a YAML or JSON change-input file; see references/change-input-schema.md
  ```

---

### `br-change-file-missing`

- **ID**: `br-change-file-missing`
- **Producer**: skill orchestration
- **Exit code**: 1
- **Trigger**: `--change-file <path>` was supplied but the file does not exist at
  the given path or is not readable by the current process.
- **Message**:

  ```
  yci: change file not found or not readable: <path>
    check the path and file permissions
  ```

---

### `br-change-file-malformed`

- **ID**: `br-change-file-malformed`
- **Producer**: skill orchestration
- **Exit code**: 2
- **Trigger**: the change file exists and is readable but fails YAML or JSON
  parsing. The parser is selected by file extension (`.json` → JSON parser;
  all others → YAML parser). The parse error is appended to the message.
- **Message**:

  ```
  yci: change file is not valid YAML/JSON: <path>
    <parse-error>
  Fix the syntax and retry.
  ```

  `<parse-error>` is the verbatim first line of the parser exception message.

---

### `br-change-file-schema`

- **ID**: `br-change-file-schema`
- **Producer**: skill orchestration
- **Exit code**: 2
- **Trigger**: the change file parses successfully but is missing one of the
  required top-level fields (`change_id`, `change_type`, `summary`, `targets`),
  or `change_type` contains a value outside the allowed enum set defined in
  `references/change-input-schema.md`.
- **Message** (missing field):

  ```
  yci: change file missing required field '<field>': <path>
    see references/change-input-schema.md for the required schema
  ```

- **Message** (bad enum):

  ```
  yci: invalid change_type value '<value>': <path>
    allowed values: <allowed-list>
    see references/change-input-schema.md for the canonical enum list
  ```

---

### `br-unknown-adapter`

- **ID**: `br-unknown-adapter`
- **Producer**: skill orchestration
- **Exit code**: 2
- **Trigger**: the resolved adapter name (from `--adapter` flag or
  `profile.inventory.adapter`) is not in the known set
  (`file`, `netbox`, `nautobot`, `servicenow-cmdb`, `infoblox`).
- **Message**:

  ```
  yci: unknown inventory adapter: '<adapter>'
    known adapters: file, netbox, nautobot, servicenow-cmdb, infoblox
    update the inventory.adapter field in your customer profile
  ```

---

### `br-adapter-not-implemented`

- **ID**: `br-adapter-not-implemented`
- **Producer**: skill orchestration
- **Exit code**: 2
- **Trigger**: the resolved adapter is a known but not-yet-implemented adapter
  (`netbox`, `nautobot`, `servicenow-cmdb`, `infoblox`). Only `file` is
  fully implemented. Points to the adapter stub for implementation guidance.
- **Message**:

  ```
  yci: inventory adapter '<adapter>' is not yet implemented
    stub and interface contract: ${CLAUDE_PLUGIN_ROOT}/skills/_shared/inventory-adapters/<adapter>/ADAPTER.md
    to use blast-radius now, set inventory.adapter: file in your customer profile
  ```

---

### `br-output-path-refused`

- **ID**: `br-output-path-refused`
- **Producer**: skill orchestration
- **Exit code**: 1
- **Trigger**: the `--output <path>` argument resolves (after canonicalization)
  to a location outside `<data-root>/artifacts/<customer>/`. All output artifacts
  must land under the customer-scoped artifacts directory per PRD §5.1.
- **Message**:

  ```
  yci: output path refused: <resolved-path>
    output must be under <data-root>/artifacts/<customer>/
    remove --output to use the default artifacts location
  ```

---

### `br-format-invalid`

- **ID**: `br-format-invalid`
- **Producer**: skill orchestration
- **Exit code**: 2
- **Trigger**: `--format` was supplied with a value not in `{json, markdown, both}`.
- **Message**:

  ```
  yci: invalid --format value: '<value>'
    allowed values: json, markdown, both
  ```

---

### `br-output-conflict`

- **ID**: `br-output-conflict`
- **Producer**: skill orchestration
- **Exit code**: 1
- **Trigger**: `--output <path>` was supplied alongside `--format both`. A
  single output path cannot receive two separate artifact files (one JSON
  and one markdown). Either drop `--output` (letting the skill write to the
  default `<data-root>/artifacts/<customer>/blast-radius/` location) or pick a
  single format.
- **Message**:

  ```
  yci: --output cannot be combined with --format both
    br-output-conflict: pick a single format or omit --output to use the default artifacts location
  ```

---

### Adapter (`scripts/adapter-file.sh`)

---

### `adapter-path-missing`

- **ID**: `adapter-path-missing`
- **Producer**: `scripts/adapter-file.sh`
- **Exit code**: 1
- **Trigger**: the inventory root path passed to the adapter does not exist, is
  not readable, or is not a directory.
- **Message** (path does not exist):

  ```
  yci: inventory root not found: <path>
    adapter-path-missing
  ```

- **Message** (path unreadable):

  ```
  yci: inventory root unreadable: <path>
    adapter-path-missing: <os-error>
  ```

- **Message** (path exists but is not a directory):

  ```
  yci: inventory root is not a directory: <path>
    adapter-path-missing
  ```

---

### `adapter-path-escape`

- **ID**: `adapter-path-escape`
- **Producer**: `scripts/adapter-file.sh`
- **Exit code**: 1
- **Trigger**: a file under the inventory root canonicalizes to a path outside
  the root (symlink pointing outside the directory tree). The adapter rejects the
  entire inventory load to prevent path-escape attacks.
- **Message**:

  ```
  yci: path escapes inventory root: <resolved-path>
    adapter-path-escape
  ```

---

### `adapter-yaml-malformed`

- **ID**: `adapter-yaml-malformed`
- **Producer**: `scripts/adapter-file.sh`
- **Exit code**: 2
- **Trigger**: a YAML file under the inventory root fails to parse, or the
  parsed value is not a YAML mapping (top-level dict) as required by the
  file-adapter schema.
- **Message** (YAML parse error):

  ```
  yci: malformed YAML in <path>
    adapter-yaml-malformed: <parse-error>
  ```

- **Message** (record is not a mapping):

  ```
  yci: record must be a YAML mapping: <path>
    adapter-yaml-malformed
  ```

  `<parse-error>` is the verbatim first line of the pyyaml exception message.

---

### `adapter-schema-required`

- **ID**: `adapter-schema-required`
- **Producer**: `scripts/adapter-file.sh`
- **Exit code**: 2
- **Trigger**: an inventory record is missing a field required by the file-adapter
  schema. Required fields are documented in `references/file-adapter-layout.md`.
- **Message**:

  ```
  yci: inventory record missing required field '<field>': <file>
    see references/file-adapter-layout.md for required fields
  ```

---

### `adapter-schema-enum`

- **ID**: `adapter-schema-enum`
- **Producer**: `scripts/adapter-file.sh`
- **Exit code**: 2
- **Trigger**: an inventory record contains a value outside the allowed enum set
  for a field that has a fixed enumeration. Allowed values are defined in
  `references/file-adapter-layout.md`.
- **Message**:

  ```
  yci: invalid enum value for '<field>': '<value>' in <file>
    allowed values: <allowed-list>
    see references/file-adapter-layout.md for the canonical enum lists
  ```

---

### `adapter-id-mismatch`

- **ID**: `adapter-id-mismatch`
- **Producer**: `scripts/adapter-file.sh`
- **Exit code**: 2
- **Trigger**: the `id` field inside an inventory record does not match the
  basename of the file (without extension). The adapter enforces this invariant
  to catch accidental copy-paste errors.
- **Message**:

  ```
  yci: record id '<record-id>' does not match filename '<basename>': <file>
    rename the file or correct the id field to restore consistency
  ```

---

### `adapter-pyyaml-missing`

- **ID**: `adapter-pyyaml-missing`
- **Producer**: `scripts/adapter-file.sh`
- **Exit code**: 3
- **Trigger**: `python3 -c "import yaml"` exits non-zero — the `pyyaml` library
  is not installed in the active Python environment.
- **Message**:

  ```
  yci: pyyaml not found — cannot parse inventory YAML
    pyyaml required — install via 'pip install pyyaml' or your distro's python3-yaml package
  ```

---

### Reasoner (`scripts/reason.sh`)

---

### `reason-missing-stdin`

- **ID**: `reason-missing-stdin`
- **Producer**: `scripts/reason.sh`
- **Exit code**: 1
- **Trigger**: stdin was a tty, empty, or contained non-JSON when the reasoner
  started. The reasoner expects a JSON object piped on stdin.
- **Message** (tty — no stdin provided):

  ```
  usage: reason.sh < payload.json
    reason-missing-stdin: no stdin provided
  ```

- **Message** (empty stdin):

  ```
  yci: reason.sh stdin empty
    reason-missing-stdin
  ```

- **Message** (non-JSON stdin):

  ```
  yci: reason.sh stdin is not valid JSON
    reason-missing-stdin: <json-parse-error>
  ```

---

### `reason-missing-required`

- **ID**: `reason-missing-required`
- **Producer**: `scripts/reason.sh`
- **Exit code**: 1
- **Trigger**: the JSON payload on stdin was valid but missing a required
  top-level key (`inventory`, `change`, `customer`), had the wrong shape
  (inventory/change not objects, customer not a string), or contained an
  invalid customer id.
- **Message** (missing key):

  ```
  yci: reason.sh payload missing required key '<key>'
    reason-missing-required
  ```

- **Message** (bad shape):

  ```
  yci: reason.sh payload shape invalid (inventory/change must be objects, customer must be string)
    reason-missing-required
  ```

- **Message** (invalid customer id):

  ```
  yci: invalid customer id '<customer>'
    reason-missing-required
  ```

---

### Renderer (`scripts/render-markdown.sh`)

---

### `render-missing-stdin`

- **ID**: `render-missing-stdin`
- **Producer**: `scripts/render-markdown.sh`
- **Exit code**: 1
- **Trigger**: stdin was a tty, empty, or contained non-JSON when the renderer
  started. The renderer expects the blast-radius label JSON piped on stdin.
- **Message** (tty — no stdin provided):

  ```
  usage: render-markdown.sh < label.json
    render-missing-stdin
  ```

- **Message** (empty stdin):

  ```
  yci: render-markdown.sh stdin empty
    render-missing-stdin
  ```

- **Message** (non-JSON stdin):

  ```
  yci: render-markdown.sh stdin is not valid JSON
    render-missing-stdin: <json-parse-error>
  ```

---

### `render-unsupported-version`

- **ID**: `render-unsupported-version`
- **Producer**: `scripts/render-markdown.sh`
- **Exit code**: 2
- **Trigger**: the `schema_version` field in the label JSON is not `1`. The
  renderer only supports label schema version 1; future versions will require an
  updated renderer.
- **Message**:

  ```
  yci: unsupported label schema version: <version> (expected 1)
    render-unsupported-version
  ```

---

## Style Guide

- **`yci:` prefix**: every message begins with `yci:` so users can immediately
  identify which tool produced the error, regardless of surrounding shell output.
- **Angle-bracket placeholders**: dynamic parts appear as `<placeholder>` in this
  catalogue (e.g., `<path>`, `<field>`, `<value>`). Scripts substitute the actual
  value at emit time; tests match on the static prefix or suffix to avoid brittle
  string copies.
- **No trailing period on the final line**: shell error convention; the terminal
  newline is sufficient sentence termination.
- **Multi-line continuation indent**: additional lines use a 2-space indent so the
  error block is visually grouped when printed to a terminal.
- **Remediation hint required for every exit-1 error**: every user-input error
  must tell the user what to do next. Exit-2 (schema) and exit-3 (runtime) errors
  should include a concrete action where one exists.
- **Upstream errors are not reformatted**: errors emitted by `resolve-customer.sh`,
  `load-profile.sh`, and `resolve-data-root.sh` are surfaced verbatim. This
  catalogue documents only the errors this skill and its three backing scripts
  can emit directly.
