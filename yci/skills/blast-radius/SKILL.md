---
name: blast-radius
description: Produce a typed blast-radius label (tenants, services, devices, dependencies, downstream consumers, RTO band, confidence, coverage gaps) for a proposed change against the active customer's inventory. Use when the user runs /yci:blast-radius, asks "what breaks if I change X", needs impact analysis before a CAB submission, or needs the structured JSON label consumed by yci:network-change-review, yci:mop, yci:evidence-bundle, and the change-window-gate hook. Reads the active customer profile's inventory.adapter (file minimum; netbox stub).
argument-hint: '[--change-file <path>] [--format json|markdown|both] [--output <path>] [--adapter <name>] [--data-root <path>]'
allowed-tools:
  - Read
  - Write
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/blast-radius/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/customer-profile/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/*.sh:*)
  - Bash(cat:*)
  - Bash(test:*)
  - Bash(mkdir:*)
  - Bash(python3:*)
  - Bash(sha256sum:*)
---

# yci:blast-radius Skill

This skill produces a typed blast-radius label for a proposed change against the
active customer's inventory. Given a change-input file and the customer's normalized
inventory, it runs a structured reasoning pass to identify directly affected devices,
services, tenants, dependencies, and downstream consumers, assigns an RTO band and a
confidence score, and flags coverage gaps where inventory data is insufficient to
reason. It does NOT mutate any data (no writes to inventory or state outside the
artifacts directory), it does NOT call vendor MCPs or live device APIs, and it does
NOT approve or reject changes — those decisions belong to the downstream consumers
of the label (`yci:cab-prep`, `yci:mop`, the change-window-gate hook).

## Inputs

### Change-input file (`--change-file <path>`)

The primary input is a change-input file in YAML (default) or JSON format. The
file extension determines the parser: `.json` uses the JSON parser; any other
extension (including `.yaml` and `.yml`) uses the YAML parser.

The full schema for this file is documented in `references/change-input-schema.md`.
Required fields at minimum:

- `change_id` — unique identifier for the change record (e.g., `WIDGET-CR-2024-A`)
- `change_type` — enum classifying the change category
- `summary` — human-readable description of the change
- `targets` — list of inventory identifiers the change will touch

If `--change-file` is omitted entirely, the skill exits 1 with
`br-missing-change-file`. If the path is provided but does not exist or is
unreadable, the skill exits 1 with `br-change-file-missing`.

### Optional overrides

- `--adapter <name>` — forces a specific inventory adapter, overriding the
  `inventory.adapter` value in the active customer profile. Known values:
  `file`, `netbox`, `nautobot`, `servicenow-cmdb`, `infoblox`. Only `file` is
  fully implemented; `netbox`, `nautobot`, `servicenow-cmdb`, and `infoblox`
  exit 2 with `br-adapter-not-implemented` and point to the stub in
  `_shared/inventory-adapters/<name>/ADAPTER.md`. Any other value exits 2
  with `br-unknown-adapter`.
- `--data-root <path>` — overrides the data-root resolution chain (see Data Root
  section in `yci:customer-profile`). Passed directly to `resolve-data-root.sh`.
- `--format json|markdown|both` — controls output format (default `json`). See
  Outputs section.
- `--output <path>` — explicit output path. When omitted with `--format both`,
  the skill writes two artifact files under
  `<data-root>/artifacts/<customer>/blast-radius/`. When provided, the path must
  resolve under `<data-root>/artifacts/<customer>/`; paths outside that boundary
  are rejected with `br-output-path-refused` (exit 1).

## Outputs

### Format: `json` (default)

The blast-radius label JSON is written to stdout, or to `--output` if provided.
The label schema is fully documented in `references/label-schema.md` and
`references/label-schema.json`. Key top-level fields (names and enum values
mirror `references/label-schema.json` verbatim):

- `schema_version` — label schema version (integer, currently `1`)
- `change_id` — echoed from the change-input
- `customer` — active customer ID
- `inventory_adapter` — adapter that produced the inventory
  (`file` | `netbox` | `nautobot` | `servicenow-cmdb` | `infoblox` | `none`)
- `inventory_source_fingerprint` — `sha256:<64-hex>` digest of the
  inventory snapshot used for this reasoning pass
- `generated_at` — RFC3339 / ISO-8601 UTC timestamp
- `tenants` — list of tenant IDs affected
- `services` — list of service objects (`id`, `criticality`, `rto_band`,
  optional `owner_tenant`) affected
- `direct_devices` — list of device objects (`id`, `role`, optional `site`)
  directly targeted by the change
- `dependencies` — edges walked during reasoning (`from`, `to`, `type`)
- `downstream_consumers` — services and tenants consuming the targeted
  resources (`id`, `kind`, `distance`)
- `rto_band` — aggregate recovery-time objective band
  (`lt-5m` | `5m-1h` | `1h-4h` | `gt-4h` | `unknown`)
- `confidence` — reasoning confidence score (`high` | `medium` | `low`)
- `coverage_gaps` — list of gap objects where inventory data was insufficient

### Format: `markdown`

The label JSON is piped through `render-markdown.sh` to produce a human-readable
impact summary. The renderer reads `$YCI_ACTIVE_REGIME` to apply regime-aware
formatting (HIPAA, PCI, SOX, etc.). When regime is `none` or `commercial`, the
environment variable is exported as empty. Output goes to stdout or `--output`.

### Format: `both`

Two artifact files are written to disk:

- `<data-root>/artifacts/<customer>/blast-radius/<change_id>.json`
- `<data-root>/artifacts/<customer>/blast-radius/<change_id>.md`

Both paths are printed to stdout (one per line, prefixed `blast-radius:`).
When `--output` is provided alongside `--format both`, it is treated as an error
and the skill exits 1 with `br-output-conflict` — a single `--output` path
cannot receive both JSON and markdown outputs. Omit `--output` to use the
default artifacts location.

## Workflow

The skill orchestrates the three backing scripts in sequence. Each step propagates
non-zero exit codes verbatim — the skill does not reformat errors from upstream
scripts.

**Step 1 — Parse flags.**
Validate `--format` against `{json, markdown, both}`. Any other value exits 2
with `br-format-invalid`. Default to `json` if `--format` is absent.

**Step 2 — Resolve data-root.**

```
bash ${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/resolve-data-root.sh [--data-root <path>]
```

Capture the canonicalized path on stdout. Propagate any non-zero exit verbatim.

**Step 3 — Resolve active customer.**

```
bash ${CLAUDE_PLUGIN_ROOT}/skills/customer-profile/scripts/resolve-customer.sh --data-root <data-root>
```

Capture the customer ID on stdout. Propagate any non-zero exit verbatim. The skill
refuses to run without an active customer — there is no fallback.

**Step 4 — Load profile.**

```
bash ${CLAUDE_PLUGIN_ROOT}/skills/customer-profile/scripts/load-profile.sh <data-root> <customer>
```

Capture the normalized profile JSON on stdout. Propagate exit codes verbatim
(exit 1 for missing profile, exit 2 for schema violations, exit 3 for runtime
errors including missing pyyaml).

**Step 5 — Pick adapter.**
If `--adapter` was supplied, use that value. Otherwise read `profile.inventory.adapter`
from the loaded profile JSON.

- If the adapter is `file` → proceed to Step 6.
- If the adapter is `netbox`, `nautobot`, `servicenow-cmdb`, or `infoblox` → exit 2
  with `br-adapter-not-implemented`, pointing to the stub at
  `${CLAUDE_PLUGIN_ROOT}/skills/_shared/inventory-adapters/<adapter>/ADAPTER.md`.
- If the adapter string is anything else → exit 2 with `br-unknown-adapter`.

**Step 6 — Resolve inventory path.**
Use `profile.inventory.path` if set and non-empty. Otherwise default to
`<data-root>/inventories/<customer>/`. Canonicalize to an absolute path. Pass the
canonical path as the sole positional argument to `adapter-file.sh`:

```
bash ${CLAUDE_PLUGIN_ROOT}/skills/blast-radius/scripts/adapter-file.sh <inventory-root>
```

Capture normalized inventory JSON on stdout. Propagate non-zero exits verbatim.

**Step 7 — Load change file.**
Read the `--change-file <path>` argument. If missing → exit 1 with
`br-missing-change-file`. If path is provided but unreadable → exit 1 with
`br-change-file-missing`. Detect format: if the extension is `.json`, parse as
JSON; otherwise parse as YAML using `python3 -c "import yaml, json, sys; ..."`.
A parse failure exits 2 with `br-change-file-malformed`. Validate required fields
(`change_id`, `change_type`, `summary`, `targets`); a missing field or bad
`change_type` enum exits 2 with `br-change-file-schema`.

**Step 8 — Build payload and run reasoner.**
Construct the payload object `{"inventory": <inventory-json>, "change": <change-json>, "customer": "<customer>"}` and pipe it to `reason.sh`:

```
echo '<payload>' | bash ${CLAUDE_PLUGIN_ROOT}/skills/blast-radius/scripts/reason.sh
```

Capture the label JSON on stdout. Propagate non-zero exits verbatim.

**Step 9 — Emit outputs per `--format`.**

- `json` → write label JSON to stdout, or to `--output` if provided.
- `markdown` → export `YCI_ACTIVE_REGIME=<profile.compliance.regime>` (export as
  empty string if regime is `none` or `commercial`); pipe label JSON into
  `render-markdown.sh`; write rendered output to stdout or `--output`.
- `both` → create `<data-root>/artifacts/<customer>/blast-radius/` if it does not
  exist; write `<change_id>.json` and `<change_id>.md` there; print both paths to
  stdout prefixed `blast-radius:`.

## Error Codes

Exit-code convention (mirrors `references/error-messages.md`):

| Exit | Meaning                                                              |
| ---- | -------------------------------------------------------------------- |
| 0    | success                                                              |
| 1    | user-input error or missing resource (file not found, no customer)   |
| 2    | schema violation (bad format flag, bad change file, unknown adapter) |
| 3    | runtime / environment error (pyyaml missing, permission denied)      |

The full error catalogue with literal message text is in `references/error-messages.md`.
Errors from `adapter-file.sh`, `reason.sh`, `render-markdown.sh`,
`resolve-customer.sh`, `load-profile.sh`, and `resolve-data-root.sh` are surfaced
verbatim — the skill does NOT reformat upstream errors.

## Worked Example

```
/yci:switch widget-corp
/yci:blast-radius --change-file ./change.yaml --format both
# -> blast-radius: /Users/.../widget-corp/blast-radius/WIDGET-CR-2024-A.json
# -> blast-radius: /Users/.../widget-corp/blast-radius/WIDGET-CR-2024-A.md
```

## Cross-References

- `references/label-schema.md` — blast-radius label field definitions
- `references/label-schema.json` — JSON Schema for machine validation
- `references/change-input-schema.md` — change-input file field definitions
- `references/file-adapter-layout.md` — inventory directory layout expected by `adapter-file.sh`
- `references/error-messages.md` — canonical error copy for this skill
- `scripts/adapter-file.sh` — normalizes a file-system inventory root to JSON
- `scripts/reason.sh` — produces the blast-radius label from inventory + change payload
- `scripts/render-markdown.sh` — renders a label JSON to human-readable markdown
- `../customer-profile/scripts/resolve-customer.sh` — 4-tier customer resolver
- `../customer-profile/scripts/load-profile.sh` — profile YAML loader and validator
- `../_shared/scripts/resolve-data-root.sh` — data-root resolution helper

## When NOT to Use This Skill

- **MOP generation** — use `yci:mop`, which consumes a blast-radius label as input
  to produce a method of procedure document.
- **CAB submission preparation** — use `yci:cab-prep`, which formats the label and
  supporting evidence into the CAB package format.
- **Live device interrogation** — this skill performs pure inventory reasoning only;
  it does not connect to devices, call vendor APIs, or use any MCP server. Real-time
  device state is out of scope.
- **Approving or rejecting changes** — the blast-radius label is advisory input to
  the change-window-gate hook and downstream review skills; it does not issue
  approvals.
- **Evidence bundle packaging** — use `yci:evidence-bundle` to collect the label
  alongside audit artifacts.

## Security Reminders

- Inventory data is customer-scoped. The skill refuses to run without an active
  customer resolved via `resolve-customer.sh` — there is no override or fallback.
- `adapter-file.sh` rejects paths that canonicalize outside the resolved inventory
  root, preventing symlink-based path-escape attacks.
- Reading another customer's inventory is structurally impossible — the inventory
  path is derived exclusively from the active customer profile; no cross-customer
  path is ever constructed or accepted.
- Output artifacts land only under `<data-root>/artifacts/<customer>/` — consistent
  with PRD §5.1 customer-scoped data isolation. The `--output` override is validated
  against this boundary and rejected with `br-output-path-refused` if it escapes it.
