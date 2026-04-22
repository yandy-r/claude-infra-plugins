# yci Customer Profile Schema

> **Source of truth**: PRD §5.2. This document mirrors that section verbatim and
> is the canonical reference for `load-profile.sh`, `init-profile.sh`, unit tests,
> and humans authoring profiles by hand.

A **customer profile** is a YAML document that describes one customer engagement.
It lives at `<data-root>/profiles/<customer-id>.yaml`, where `<data-root>` resolves
via the precedence chain: `--data-root <path>` > `$YCI_DATA_ROOT` > `~/.config/yci/`
(see PRD §5.1). Start a new profile from `_template.yaml` in the same directory.

---

## Top-level keys

| Key              | Required | Notes                                                           |
| ---------------- | -------- | --------------------------------------------------------------- |
| `customer`       | yes      | Stable identity of the customer; used as scope label everywhere |
| `engagement`     | yes      | Current SOW / engagement context                                |
| `compliance`     | yes      | Regime + evidence schema                                        |
| `inventory`      | yes      | CMDB / device-inventory adapter                                 |
| `approval`       | yes      | Approval-workflow adapter                                       |
| `deliverable`    | yes      | Output format and destination path                              |
| `safety`         | yes      | Default posture, change-window policy, scope enforcement        |
| `change_window`  | no       | Required only when `safety.change_window_required: true`        |
| `vaults`         | no       | Override for secrets-store path; defaults to data-root subtree  |
| `vendor_tooling` | no       | List of vendor/product/version entries for the engagement       |

---

## Per-subtree field tables

### `customer`

| Field          | Type   | Required | Allowed values | Notes                                         |
| -------------- | ------ | -------- | -------------- | --------------------------------------------- |
| `id`           | string | yes      | `[a-z0-9-]+`   | Stable slug; used as scope label in artifacts |
| `display_name` | string | yes      | any string     | Human-readable name for deliverable headers   |
| `branding`     | object | no       | —              | See nested fields below                       |

#### `customer.branding`

| Field       | Type   | Required | Notes                                                      |
| ----------- | ------ | -------- | ---------------------------------------------------------- |
| `logo_path` | string | no       | Absolute or `~/`-prefixed path to a PNG/SVG logo           |
| `color`     | string | no       | Hex color code (e.g., `'#003366'`) for deliverable styling |

> Consultant brand is always composited alongside customer brand (PRD §0 Q3).

---

### `engagement`

| Field        | Type   | Required | Allowed values                                     | Notes                                    |
| ------------ | ------ | -------- | -------------------------------------------------- | ---------------------------------------- |
| `id`         | string | yes      | `[a-z0-9-]+`                                       | Stable engagement slug                   |
| `type`       | string | yes      | `discovery`, `design`, `implementation`, `ongoing` | Engagement phase; see Enum section below |
| `sow_ref`    | string | yes      | any string                                         | SOW / contract reference number          |
| `scope_tags` | list   | yes      | any strings                                        | Tags used by scope-gate hook; match SOW  |
| `start_date` | string | yes      | `YYYY-MM-DD`                                       | Engagement start                         |
| `end_date`   | string | yes      | `YYYY-MM-DD`                                       | Engagement end                           |

---

### `compliance`

| Field                     | Type    | Required | Allowed values                        | Notes                                   |
| ------------------------- | ------- | -------- | ------------------------------------- | --------------------------------------- |
| `regime`                  | string  | yes      | see **Compliance regimes** enum below | Selects the compliance adapter          |
| `baa_reference`           | string  | no       | any string                            | BAA / DPA reference (HIPAA customers)   |
| `evidence_schema_version` | integer | yes      | `1` (current)                         | Adapter evidence-schema version to load |
| `signing`                 | object  | no       | see nested table below                | Profile-scoped evidence signing config  |

#### `compliance.signing`

Optional. When present, `yci:evidence-bundle` uses this subtree to select the
signing backend for the final evidence pack.

| Field      | Type   | Required | Allowed values                  | Notes                                                                  |
| ---------- | ------ | -------- | ------------------------------- | ---------------------------------------------------------------------- |
| `method`   | string | yes      | `minisign`, `ssh-keygen-y-sign` | Signing backend to use for the evidence bundle                         |
| `key_ref`  | string | yes      | any string                      | Path / vault reference for the signing key or allowed-signers config   |
| `identity` | string | cond.    | any string                      | Required when `method: ssh-keygen-y-sign`; mapped to `ssh-keygen -I`   |
| `pubkey`   | string | no       | any string                      | Optional public-key or verifier reference emitted into bundle metadata |

---

### `change_window`

Required when `safety.change_window_required: true`. If omitted and that flag is
`true`, the loader emits an error.

| Field      | Type   | Required | Allowed values                                                   | Notes                                                  |
| ---------- | ------ | -------- | ---------------------------------------------------------------- | ------------------------------------------------------ |
| `adapter`  | string | yes      | `ical`, `servicenow-cab`, `json-schedule`, `always-open`, `none` | Selects the changewindow adapter                       |
| `source`   | string | cond.    | file path or URL                                                 | Required for `ical`, `json-schedule`, `servicenow-cab` |
| `timezone` | string | no       | IANA tz string (e.g., `America/Chicago`)                         | Defaults to system timezone                            |

---

### `inventory`

| Field            | Type   | Required | Example values                                                        | Notes                                             |
| ---------------- | ------ | -------- | --------------------------------------------------------------------- | ------------------------------------------------- |
| `adapter`        | string | yes      | `file`, `manual`, `netbox`, `nautobot`, `servicenow-cmdb`, `infoblox` | CMDB adapter to load — see adapter note below     |
| `endpoint`       | string | cond.    | URL                                                                   | Required for API-backed adapters                  |
| `credential_ref` | string | cond.    | `<customer-id>/<key-name>`                                            | Reference into the vaults subtree; no raw secrets |
| `path`           | string | no       | any path                                                              | Override for inventory storage location           |

> **Adapter note** — `inventory.adapter` is validated as a non-empty string, not
> a closed enum. The values above are illustrative common adapters; new
> adapters can be added to a profile without a schema change, provided the
> consuming hook knows how to read them. `profile-schema.sh` reflects this
> (no `YCI_INVENTORY_ADAPTERS` enum array is declared).

---

### `approval`

| Field            | Type   | Required | Example values                                                               | Notes                                              |
| ---------------- | ------ | -------- | ---------------------------------------------------------------------------- | -------------------------------------------------- |
| `adapter`        | string | yes      | `github-pr`, `email-signoff`, `jira`, `servicenow-request`, `manual`, `none` | Approval-workflow adapter — see adapter note below |
| `endpoint`       | string | cond.    | URL                                                                          | Required for API-backed adapters                   |
| `credential_ref` | string | cond.    | `<customer-id>/<key-name>`                                                   | Reference into the vaults subtree; no raw secrets  |

> **Adapter note** — like `inventory.adapter`, `approval.adapter` is validated
> as a non-empty string, not a closed enum. The list above is illustrative.

---

### `vaults`

Optional top-level override. Defaults to `$YCI_DATA_ROOT/vaults/<customer-id>/`.

| Field  | Type   | Required | Notes                                                                  |
| ------ | ------ | -------- | ---------------------------------------------------------------------- |
| `path` | string | no       | Any path or URI (e.g., `onepassword://acme-vault`, `~/Dropbox/vault/`) |

---

### `deliverable`

| Field             | Type         | Required | Allowed values                                | Notes                                                        |
| ----------------- | ------------ | -------- | --------------------------------------------- | ------------------------------------------------------------ |
| `format`          | list[string] | yes      | `markdown`, `pdf`, `word`, `confluence`       | Output formats for this customer                             |
| `header_template` | string       | yes      | file path                                     | Dual-branded header template (PRD §0 Q3)                     |
| `handoff_format`  | string       | yes      | `git-repo`, `zip`, `confluence`, `pdf-bundle` | Delivery packaging for end-of-engagement handoff             |
| `path`            | string       | no       | any path                                      | Override for artifact storage; defaults to data-root subtree |

Common `path` patterns: `~/Dropbox-<Customer>/deliverables/`,
`~/OneDrive-<Customer>/deliverables/`, `/Volumes/<NAS>/deliverables/`,
`~/Encrypted-Customers/<id>/` (see PRD §11.10).

---

### `vendor_tooling`

A list of objects. Each entry has:

| Field     | Type   | Required | Notes                                              |
| --------- | ------ | -------- | -------------------------------------------------- |
| `vendor`  | string | yes      | Vendor slug (e.g., `cisco`, `palo-alto`, `vmware`) |
| `product` | string | yes      | Product slug (e.g., `ios-xe`, `pan-os`)            |
| `version` | string | yes      | Semver or version string (e.g., `'17.9'`)          |

---

### `safety`

| Field                    | Type    | Required | Allowed values                         | Notes                                              |
| ------------------------ | ------- | -------- | -------------------------------------- | -------------------------------------------------- |
| `default_posture`        | string  | yes      | see **Safety postures** enum below     | Default for all yci workflows in this engagement   |
| `change_window_required` | boolean | yes      | `true`, `false`                        | If `true`, `change_window` key must be present     |
| `scope_enforcement`      | string  | yes      | see **Scope enforcement values** below | Behavior when scope-gate detects out-of-scope work |

---

## Enum sections

### Compliance regimes

Values for `compliance.regime` (PRD §11.2):

| Value        | Meaning                                           |
| ------------ | ------------------------------------------------- |
| `hipaa`      | HIPAA/HITECH — healthcare customers               |
| `pci`        | PCI-DSS — customers handling card data            |
| `sox`        | SOX — publicly-traded financial customers         |
| `soc2`       | SOC 2 — cloud-native commercial customers         |
| `iso27001`   | ISO 27001 — international / EU customers          |
| `nist`       | NIST 800-53 — federal customers                   |
| `commercial` | Generic best-practice, no specific named regime   |
| `none`       | No compliance framing (internal / lab / non-prod) |

---

### Safety postures

Values for `safety.default_posture` (PRD §11.7):

| Value     | Meaning                                                                |
| --------- | ---------------------------------------------------------------------- |
| `dry-run` | Produce plan/diff/review artifact only; never write or apply (default) |
| `review`  | Surface changes for human review before applying                       |
| `apply`   | Allow changes to proceed (requires explicit `--apply` flag at runtime) |

Default for all profiles is `dry-run`. The stock `_internal` profile uses `review`
(PRD §0 Q5).

---

### Engagement types

Values for `engagement.type` (PRD §5.2):

| Value            | Meaning                                           |
| ---------------- | ------------------------------------------------- |
| `discovery`      | Read-only assessment; no write operations allowed |
| `design`         | Architecture / design phase                       |
| `implementation` | Active build / configuration phase                |
| `ongoing`        | Ongoing managed service or support engagement     |

---

### Scope enforcement values

Values for `safety.scope_enforcement` (PRD §5.2, §6.1 P0.9):

| Value   | Meaning                                                         |
| ------- | --------------------------------------------------------------- |
| `warn`  | Log a warning when work appears outside SOW scope tags; proceed |
| `block` | Refuse to proceed until scope is confirmed or overridden        |
| `off`   | No scope checking (use only for `_internal` or lab profiles)    |

---

## Unknown-keys policy

The profile loader emits a **warning** on any unrecognised top-level key and
continues loading. This allows forward-compatible profiles (e.g., a profile
authored for a future `yci` version with a new optional key will still load on
an older version). Missing **required** keys cause an immediate **error** and
abort loading.

---

## Credentials note

Profiles **MUST NOT contain secrets**, credentials, tokens, passwords, or any
sensitive value. Use `credential_ref` fields as opaque pointers into the active
vaults subtree (e.g., `acme-healthcare/netbox-token`). The vault itself is
encrypted at rest (`age` or `sops` recommended) and lives outside any git
repository. See PRD §11.9.
