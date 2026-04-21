# Contributing to yci

`yci` is the consulting/systems-integration sibling of `ycc`. Where `ycc` owns
the dev-focused workflow, `yci` owns the consulting-engagement workflow: load a
customer profile, work inside that profile's guardrails, produce customer-ready
deliverables, hand off cleanly, and switch profiles without leakage. Phase 0 is
mechanical scaffolding only — it proves the plugin pipeline and documents the
invariants. Behavioral artifacts (hooks, compliance adapters, real workflow
skills, evidence bundles, MOP generators) land in later phases. The binding
reference for all design decisions is
[`docs/prps/prds/yci.prd.md`](../docs/prps/prds/yci.prd.md).

---

## Non-Goals

The following are explicit rejects, drawn from PRD §4. They are not open for
P2 reconsideration without a documented justification that overrides the PRD.

- **No hardcoded compliance regime.** HIPAA is not "the default"; PCI is not
  "the default"; commercial is not "the default". Compliance is an adapter —
  every artifact adapts to the regime declared in the loaded customer profile.
  Baking any single regime into skill code is a defect.

- **No assumption of a specific inventory, CMDB, or change-window system.**
  These are all adapter-shaped: `yci` defines the interface, the customer
  profile points at the adapter or at `none`. Skills must not import logic
  specific to NetBox, Nautobot, ServiceNow, iCal, or any other system.

- **No vendor-per-skill matrix.** A `yci:cisco-acl-review` skill is the wrong
  abstraction. Vendor MCPs and the models' native tooling saturate this niche
  and carry a 5-10 year half-life. Workflow skills that happen to parse
  vendor-specific output are acceptable; skills that _are_ a vendor surface
  are not. Explicitly rejected: per-skill trees for Cisco, Fortinet, Juniper,
  Palo Alto.

- **No cloud-provider skills.** Foundation models cover AWS, Azure, and GCP
  fluently; official provider MCPs saturate orchestration. Cloud-specific logic
  belongs inside a workflow skill (e.g., `yci:blast-radius` may parse ARNs) —
  not in a dedicated cloud-provider skill tree.

- **No K8s, container-security, or virtualization domain trees.** Existing
  tooling saturates these areas; safety checks are a hook concern, not a skill
  concern.

- **No LLM knowledge dumps.** Skills that restate vendor documentation ("here
  is how to write a PAN-OS security policy") are not worth the maintenance
  cost. Adverse-to-model pitfall skills are fine; knowledge-dump skills are not.

- **No auto-apply for destructive operations.** `yci` reads, diffs, plans, and
  produces artifacts. The operator applies via their (or the customer's)
  pipeline. A skill that writes a change to a live device without an explicit
  operator action is a defect.

- **No in-repo customer data.** Customer names, credentials, IP addresses,
  hostnames, device configs, evidence artifacts — none of these ever touch the
  `yandy-r/claude-plugins` git repository. Customer profiles live outside the
  repo in `$YCI_DATA_ROOT`. See [Customer-Data-Outside-Repo Rule](#customer-data-outside-repo-rule) below.

- **No hardcoded data-root path.** `~/.config/yci/` is the default, not a
  constant. Every script and skill that needs the data root must resolve it at
  runtime via the precedence chain: `--data-root <path>` flag, then
  `$YCI_DATA_ROOT`, then the default. Hard-coding the path in source is a defect.

---

## Compliance-Adapter Pattern

Compliance in `yci` is an adapter, not a mode. This is the design contract
described in PRD §5.3, and it is intended to be load-bearing: it is what will
allow the same skill to produce HIPAA-shaped evidence for one customer and
PCI-shaped evidence for another without any changes to the skill itself.

> **Phase 1 baseline (issue #30) ships two adapters**: `commercial` and `none`.
> Both live under `yci/skills/_shared/compliance-adapters/` in the tree
> introduced by issue #30. Additional regimes (`hipaa`, `pci`, `sox`, `soc2`,
> `iso27001`, `nist`) are declared valid in `YCI_COMPLIANCE_REGIMES` (see
> `yci/skills/customer-profile/scripts/profile-schema.sh`) but do not yet ship
> adapter directories. A customer profile that pins one of those regimes will
> receive exit code 3 from the loader until the corresponding adapter directory
> lands.

### Directory Layout

Adapters live under `yci/skills/_shared/compliance-adapters/`, one directory
per supported regime:

```
yci/skills/_shared/compliance-adapters/
├── hipaa/
│   ├── ADAPTER.md              # what this adapter promises
│   ├── evidence-schema.json    # required fields for a HIPAA evidence bundle
│   ├── evidence-template.md    # markdown template for HIPAA evidence
│   ├── phi-redaction.rules     # telemetry-sanitizer rules for PHI
│   └── handoff-checklist.md
├── pci/
│   ├── ADAPTER.md
│   ├── evidence-schema.json    # PCI-DSS-shaped
│   ├── cde-boundary-attest.md
│   └── handoff-checklist.md
├── sox/
│   ├── ADAPTER.md
│   ├── evidence-schema.json
│   └── handoff-checklist.md
├── soc2/
│   ├── ADAPTER.md
│   ├── evidence-schema.json
│   └── handoff-checklist.md
├── iso27001/
│   ├── ADAPTER.md
│   ├── evidence-schema.json
│   └── handoff-checklist.md
├── commercial/                 # generic best-practice, no specific regime
│   ├── ADAPTER.md
│   ├── evidence-schema.json
│   └── handoff-checklist.md
└── none/                       # no compliance framing (homelab, internal)
    ├── ADAPTER.md
    └── handoff-checklist.md
```

### What Every Adapter Should Ship (design contract)

Adapters live at two shapes — **Phase-1 baseline** (the target for new
adapters) and **pre-Phase-1 minimal** (the shape `hipaa` ships today pending
retrofit).

**Every adapter ships** — the single hard requirement:

- `ADAPTER.md` — declares what the adapter promises: which evidence fields it
  requires, what redaction rules it applies, and any regime-specific invariants.

**Non-exempt adapters also ship a redaction rules file**:

- One or more files matching the glob `*-redaction.rules` (filename prefix
  describes the rule class — e.g. `phi-redaction.rules` for HIPAA,
  `generic-redaction.rules` for commercial).
- Format: the `NAME:<rule-name>` / `RE:<python-regex>` paragraph layout
  consumed by `yci/skills/_shared/telemetry-sanitizer/scripts/load_adapter_rules.py`.
- Discovery is glob-based, so a regime may ship multiple rule files if it
  wants to group patterns by class.

**Phase-1 baseline adapters** additionally ship:

- `evidence-schema.json` — required-field set for an evidence bundle under this
  regime (JSON Schema draft-07). Omitted only by schema-exempt regimes.
- `evidence-template.md` — the markdown template used to render an evidence
  artifact for this regime.
- `handoff-checklist.md` — a reviewer checklist confirming the deliverable
  meets the regime's expectations before it leaves the engagement.

The `none` adapter is schema-exempt and redaction-exempt by design — it ships
no `*-redaction.rules` and no `evidence-schema.json`. Its `evidence-template.md`
and `handoff-checklist.md` are deliberately minimal.

The `hipaa` adapter is pre-Phase-1: it ships `ADAPTER.md` + `phi-redaction.rules`
only, and will be retrofitted to the Phase-1 shape in a later issue.

#### Machine-readable contract

The filesystem contract is mirrored in
`yci/skills/_shared/scripts/adapter-schema.sh`:

- `YCI_ADAPTER_REQUIRED_FILES=(ADAPTER.md)` — the single hard requirement.
- `YCI_ADAPTER_PHASE1_FILES=(evidence-template.md handoff-checklist.md)` —
  additional files required for regimes on the Phase-1 list.
- `YCI_ADAPTER_PHASE1_REGIMES=(commercial none)` — the regimes that ship the
  Phase-1 baseline shape. `hipaa` is deliberately absent until retrofit.
- `YCI_ADAPTER_SCHEMA_EXEMPT=(none)` — exempt from `evidence-schema.json`.
  Exempt regimes are also allowed to ship no `*-redaction.rules` file.

### How Skills Should Use Adapters

A skill that emits a compliance-relevant artifact (evidence bundle, MOP,
handoff pack) should read `compliance.regime` from the active customer profile
and load the matching adapter directory. Schema, redaction rules, and templates
are adapter-provided. The skill should not branch on regime names in its own code.

```bash
# Resolve the adapter directory for the active customer profile.
# Requires load-profile.sh's JSON output piped on stdin, or pass --regime
# directly for tests and smoke checks.

# (A) one-shot: capture the adapter dir
adapter_dir="$(
  bash "${CLAUDE_PLUGIN_ROOT}/skills/customer-profile/scripts/load-profile.sh" \
       "${YCI_DATA_ROOT}" "${customer_slug}" \
    | bash "${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/load-compliance-adapter.sh"
)"

# (B) sourceable shape: populate YCI_ADAPTER_DIR / _REGIME / _HAS_SCHEMA
eval "$(bash "${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/load-compliance-adapter.sh" \
          --export --regime "${active_regime}")"
```

The loader exits 2 on an unknown or empty regime, 3 when the adapter directory
does not exist on disk, and 4 when the adapter directory is present but
incomplete (missing required files per the contract in `adapter-schema.sh`).
Skills must not branch on `${YCI_ADAPTER_REGIME}` or any other regime name —
consume `${YCI_ADAPTER_DIR}` and let the adapter's files drive behaviour. If
the loader returns a non-zero exit, the skill must halt and surface the stderr
message to the operator; substituting a default regime silently is a defect.

### Baseline adapters shipped in Phase 1

- **`commercial`** — the generic best-practice default for non-regulated
  customer engagements; applies standard change-management hygiene without any
  regulator-specific framing. See
  `yci/skills/_shared/compliance-adapters/commercial/ADAPTER.md` for the full
  contract.
- **`none`** — the schema- and redaction-exempt regime intended for internal,
  homelab, and non-production work; the `_internal` stock profile defaults here.
  See `yci/skills/_shared/compliance-adapters/none/ADAPTER.md`.

Both adapters land together as a single change (issue #30) so the baseline is
non-ambiguous: either both are present or neither is.

### Adding a New Regime

1. **Add the regime to `YCI_COMPLIANCE_REGIMES`** in
   `yci/skills/customer-profile/scripts/profile-schema.sh`. Use lowercase;
   avoid hyphens if a single word fits. Confirm no existing profile uses the
   same slug under a different name before committing.

2. **Create the adapter directory** at
   `yci/skills/_shared/compliance-adapters/<regime>/`. At minimum populate
   `ADAPTER.md` (from `YCI_ADAPTER_REQUIRED_FILES`). If the regime is NOT
   listed in `YCI_ADAPTER_SCHEMA_EXEMPT`, add at least one
   `<prefix>-redaction.rules` file in the `NAME:/RE:` format (see
   `hipaa/phi-redaction.rules` or `commercial/generic-redaction.rules` for
   reference).

3. **For new adapters, default to the Phase-1 baseline shape** by adding the
   regime to `YCI_ADAPTER_PHASE1_REGIMES` and populating
   `evidence-template.md`, `handoff-checklist.md`, and — if non-exempt —
   `evidence-schema.json`. Pre-Phase-1 minimal adapters (like `hipaa`) are
   permitted only as a legacy shape pending retrofit; do not add new adapters
   in that shape.

4. **Write `ADAPTER.md`** covering: regime name, intent, evidence schema
   reference (and version), redaction-rules reference, handoff-checklist
   reference, any regime-specific invariants, and the promises the adapter
   makes to callers. Use `commercial/ADAPTER.md` as the template — its
   structure is the canonical Phase-1 model.

5. **If the regime needs a schema exemption**, add it to
   `YCI_ADAPTER_SCHEMA_EXEMPT` in
   `yci/skills/_shared/scripts/adapter-schema.sh`, then document the exemption
   in the adapter's `ADAPTER.md` — explain why it is exempt and what the
   operator loses by not having a schema or redaction rules.

6. **Extend the validator** in
   `scripts/validate-yci-skills.sh :: validate_compliance_adapters` if the new
   regime requires a regime-specific structural check beyond the contract
   already enforced for all adapters. Most new regimes will not need this step.

7. **Update the "Baseline adapters shipped in Phase 1" section** above to
   include the new regime and a one-sentence description so the list stays
   current.

---

## Inventory-Adapter Pattern

Inventories are adapter-shaped for the same reasons as compliance regimes
(PRD §4). The skill code never assumes NetBox, Nautobot, ServiceNow CMDB, or
any other source of truth; the active profile's `inventory.adapter` field
names the adapter, and the adapter translates the source's native shape into
the normalized inventory JSON that downstream workflow skills consume.

### Directory Layout

Inventory adapter implementations live under
`yci/skills/_shared/inventory-adapters/<name>/`. Phase 0 ships the `file`
adapter inline (at `yci/skills/blast-radius/scripts/adapter-file.sh`) and a
`netbox/ADAPTER.md` interface-only stub. When a second adapter ships, the
`file` adapter moves to `_shared/inventory-adapters/file/` and the skill-local
invocation is replaced by a generic dispatcher.

### Interface Contract

Any inventory adapter MUST:

1. Emit a single JSON object to stdout matching
   [`yci/skills/blast-radius/references/file-adapter-layout.md`](skills/blast-radius/references/file-adapter-layout.md)
   §"Normalization output" — keys: `adapter, root, tenants, services, devices,
sites, dependencies`.
2. Honour the catalogued exit codes (0 success, 1 source/path problem,
   2 schema violation, 3 runtime error / missing dependency).
3. Read its configuration from the loaded customer profile fields
   (`inventory.endpoint`, `inventory.credential_ref`, `inventory.path`) only
   via arguments passed by the calling skill. Adapters MUST NOT re-read the
   profile themselves.
4. Fail closed if any required profile field is missing. Never silently
   return an empty inventory.

Skills that compose blast-radius (for example `yci:network-change-review`
P0.5, `yci:mop` P0.6) depend on the normalized JSON shape being stable across
adapters. Any adapter-specific schema drift is a defect.

---

## Telemetry sanitizer (cross-customer redaction)

Skills and hooks that write customer-scoped artifacts should run text through
the shared helper under
`yci/skills/_shared/telemetry-sanitizer/` before the bytes hit disk (or before
content is pasted into repo-tracked files).

- **`scripts/sanitize-output.sh`** — resolves the active customer profile,
  loads `compliance.regime`, merges adapter `*-redaction.rules` (for example
  `yci/skills/_shared/compliance-adapters/hipaa/phi-redaction.rules`), reads
  **stdin**, writes redacted text to **stdout**. Override mode with
  `YCI_SANITIZER_MODE=internal` only for vetted internal flows (same semantics
  as the Python `--mode internal`: skips strict cross-customer FQDN heuristics).
- **`scripts/pre-write-artifact.sh`** — same resolution path; reads **stdin**
  as the artifact body and writes the sanitized result to the path given by
  **`--output`**. Optional **`--meta-file`** supplies YAML frontmatter for
  gating: cross-customer relaxed redaction (`--mode internal` in the Python
  core) is allowed **only** when **`YCI_INTERNAL_CROSS_CUSTOMER_OK=1`** and the
  meta file contains a line exactly: `customer: _internal`.

Do not bypass the sanitizer for customer deliverables. For deliberate
multi-customer internal runbooks, use the `_internal` label and env flag
above — never relax redaction for normal customer engagements.

---

## Keystone workflow: network-change-review

`yci:network-change-review` is the P0.5 keystone skill (PRD §6.1). It composes
`yci:customer-profile`, `yci:customer-guard` (via the automatic PreToolUse hook),
`yci:telemetry-sanitizer`, the compliance adapter, `yci:blast-radius`, and — via
the Agent tool — `ycc:plan` and `ycc:code-review` into a single dual-branded
deliverable. It is "keystone" because every downstream P0/P1 skill (`yci:mop`,
`yci:evidence-bundle`, `yci:cab-prep`) either consumes its outputs or follows its
composition pattern (PRD §5.6, PRD §6.1). Shipping a reliable
`yci:network-change-review` is the prerequisite for every subsequent workflow skill
being worth shipping.

### Composition order

The orchestrator (`review.sh`) runs these stages in order:

1. **Profile** — resolve data root, resolve active customer, load profile JSON.
2. **Guard** (automatic hook) — `yci:customer-guard` intercepts at PreToolUse;
   `review.sh` does NOT invoke it directly.
3. **Preflight identifier scan** — walk every other customer's profile under
   `<data-root>/profiles/`, extract `customer_id`, `hostname_suffix`,
   `ipv4_ranges`, and grep the raw input for any match. Any hit exits
   `ncr-cross-customer-leak-detected` immediately — before any parsing.
4. **Parse** — `parse-change.sh` validates the raw change file (preserving raw
   identifiers) against `change-input-schema.md` and produces normalized change JSON.
5. **Rollback** — `derive-rollback.sh` derives the rollback plan; low confidence
   inserts a `> **WARNING**` callout rather than failing.
6. **Blast-radius** — `blast-radius/scripts/reason.sh` + `render-markdown.sh`.
7. **Catalogs** — `build-check-catalogs.sh` produces pre/post-check catalog JSON
   from the adapter's `evidence-template.md` and `evidence-schema.json`.
8. **Plan + review** (SKILL layer, before `review.sh`) — run the same cross-customer
   preflight as `review.sh` (`preflight-cross-customer.sh`), then dispatch
   `ycc:planner` and `ycc:code-reviewer` in parallel via the Agent tool; pass their
   outputs with `--change-plan` and `--diff-review` into `review.sh`.
9. **Render** — `render-evidence-stub.sh` then `render-artifact.sh` assemble the
   full review markdown in memory.
10. **Sanitize** — `pre-write-artifact.sh` (strict mode, sanitizer pass 2) runs
    on the rendered artifact before any byte hits disk.
11. **Isolation detect** — `customer-isolation/detect.sh` belt-and-suspenders
    check on the sanitized artifact; `deny` → delete temp file, exit hard.
12. **Write** — move sanitized artifact to
    `<data-root>/artifacts/<customer>/network-change-review/<change_id>-<timestamp>/review.md`.

### Cross-plugin boundary rule

From the project `CLAUDE.md`:

> Cross-plugin helper sharing is NOT supported — if `ycc` and `yci` both need
> the same helper, duplicate it (the duplication cost is low, the coupling cost
> is high).

`ycc:plan` and `ycc:code-review` are invoked via the Agent tool with
`subagent_type: "ycc:planner"` / `"ycc:code-reviewer"` — structured prompt in,
text out. `review.sh` is a `yci` artifact; it cannot and must not `source` or
`bash` any file from the `ycc/` source tree. The only supported cross-plugin
channel is the Agent tool, which treats the other plugin's skill as a black box.
No `ycc` filesystem path is ever embedded in any `yci` script. This boundary
discipline mirrors the adapter-boundary precedent documented in the
[Compliance-Adapter Pattern](#compliance-adapter-pattern) section above: `yci`
defines its own interface and calls `ycc` only through documented,
runtime-stable channels.

### Dual-branding contract

Every artifact produced by this skill contains a `{{customer_brand_block}}` slot
populated from the active profile's `deliverable.header_template` AND a
`{{consultant_brand_block}}` slot populated from
`yci/skills/network-change-review/references/consultant-brand.md`. Both slots are
required; a missing customer brand template causes the orchestrator to exit with
`ncr-branding-template-missing` (exit 6) before any artifact bytes are written.
There is no fallback for the customer slot — failing loud is correct: a deliverable
without customer branding is never handoff-ready (PRD §5.6; PRD §4 threat #3,
inadequate handoff).

### Step 8 / preflight design note

The composition-contract.md originally specified step 6/8 as a sanitizer
**redaction** pass on the raw input diff. That was changed during implementation:
the sanitizer's redaction mode destroys identifiers that `parse-change.sh` needs
(`change_id`, hostnames, IP addresses), rendering the parse step unable to resolve
targets. The preflight scan is therefore **detect-only** — it walks every other
customer's profile and greps the raw input for foreign identifiers, failing hard on
any match. Redaction happens AFTER rendering (step 10, sanitizer pass 2) and the
belt-and-suspenders isolation check runs AFTER that (step 11). If you modify any of
these steps, preserve this invariant: **`parse-change.sh` sees raw identifiers;
output is never written with foreign identifiers.**

### Evidence stub forward-compat

The evidence stub YAML written alongside the artifact
(`evidence-stub.yaml`, step 9) is forward-compatible with the downstream P0.4
`yci:evidence-bundle` skill. Field names are 1:1 with
`_shared/compliance-adapters/commercial/evidence-schema.json` v1. Do NOT rename
existing fields; only add. A schema version field in the stub allows
`evidence-bundle` to detect and reject stubs from older revisions.

See `yci/skills/network-change-review/references/composition-contract.md` for the
authoritative design doc.

---

## Customer-Data-Outside-Repo Rule

Customer data must never enter the `yandy-r/claude-plugins` git repository.
This rule is drawn from PRD §5.1 and §11.9 and is the primary security
invariant for `yci`. A cross-customer data leak — including via a git commit —
is a career-ending event. There are no exceptions.

### What Counts as Customer Data

Customer profiles, vault contents, device inventories, CMDB exports, change
calendars, network configs, credentials, IP addresses, hostnames, AS numbers,
project codes, SOW references, and any deliverable artifact produced for a
specific customer all count as customer data. If it identifies or characterizes
a real customer engagement, it stays outside the repo.

### Data-Root Resolution

All customer data lives under a resolved data root. Resolution follows this
precedence (first match wins):

1. `--data-root <path>` — explicit CLI flag, session-scoped.
2. `$YCI_DATA_ROOT` — environment variable, session-scoped.
3. Default: `~/.config/yci/` — per-user, outside any git repo, mode 0700.

Every script and skill that references the data root must implement this
resolution chain. Hard-coding `~/.config/yci/` is a defect — it breaks the
moment an operator sets `$YCI_DATA_ROOT` or passes `--data-root`.

### Per-Customer Path Overrides

The profile YAML supports per-customer overrides for any subtree under the data
root. The fields `vaults.path`, `inventory.path`, `calendars.path`, and
`deliverable.path` each accept any local path. This accommodates common
consulting patterns:

- A customer mandates "secrets live in 1Password, not on disk" — set
  `vaults.path: onepassword://acme-vault`.
- A customer requires "deliverables go to this Dropbox folder" — set
  `deliverable.path: ~/Dropbox-Acme/deliverables/`.
- A customer has a shared network drive — set
  `deliverable.path: /Volumes/Acme-NAS/deliverables/`.
- A consultant uses a separate encrypted volume — set
  `deliverable.path: ~/Encrypted-Customers/acme/`.

These paths are resolved at skill runtime, not at scaffold time. Profile-swap
transparently relocates where output lands.

### Example Profiles in This Repo

Example profiles that ship inside `yandy-r/claude-plugins` must use the
`.yaml.example` extension, never the `.yaml` extension. They must not contain
real customer names, IPs, credentials, or operational identifiers.

The stock `_internal` profile ships at
`yci/docs/profiles/_internal.yaml.example` as a template only. It demonstrates
the relaxed defaults for homelab / internal work (compliance = `none`, no
change-window, `safety.default_posture: review`, scope-gate off). It is not an
operational profile and must not be treated as one.

For the full data-root layout and per-customer override reference, see
[`yci/docs/profiles.md`](docs/profiles.md).

---

## Phase Discipline

Phase 0 is scaffolding only. The deliverables for Phase 0 are:

- The `yci/` plugin directory and `plugin.json`.
- A second entry in `.claude-plugin/marketplace.json`.
- Empty `yci/hooks/`, `yci/skills/`, `yci/agents/`, `yci/commands/`
  placeholders.
- This `CONTRIBUTING.md`.
- Generator and validator script support for the `yci` plugin alongside `ycc`.
- A trivial `yci:hello` skill to prove the pipeline end-to-end.
- `yci/docs/profiles.md` documenting the `~/.config/yci/` layout.
- CI builds and validates both plugins.

Work that is not on that list — hooks, compliance adapters, real workflow
skills, evidence bundles, MOP generators, agents, change-window adapters — waits
for an explicit phase kickoff per the PRD roadmap. The artifact set for each
phase is defined in PRD §6. The phased rollout plan is in PRD §9.

Adding a hook, adapter, or skill to Phase 0 is a scope defect, not a
contribution. Open an issue and target the appropriate later phase instead.

### Guard-hook discipline

The `yci` customer-guard PreToolUse hook (`yci/hooks/customer-guard/`) is a
load-bearing security control. Operator-facing setup and false-positive triage
are documented in [`yci/hooks/customer-guard/README.md`](hooks/customer-guard/README.md).

Contributors MUST NOT:

1. Add a default-relaxed code path (allow-by-default is non-negotiably out of
   scope per yci PRD §10 #1).
2. Bypass the hook by short-circuiting the detection library in callers; if
   a legitimate cross-reference is needed, it is expressed in the operator's
   per-tenant `<data-root>/profiles/<active>.allowlist.yaml` with a mandatory
   `note:` citing the SOW or ticket authorizing it.
3. Silently swallow guard errors. The load-bearing contract is "clear
   actionable error" — every deny message routes through the catalogued
   error IDs in `yci/hooks/customer-guard/references/error-messages.md`.

---

## Related References

- [`../CLAUDE.md`](../CLAUDE.md) — Repo-level project instructions: naming
  conventions, script standards, testing, generator pipeline, and the full
  MUST/MUST NOT list for this repository.
- [`../CONTRIBUTING.md`](../CONTRIBUTING.md) — Repo-level contributing guide:
  GitHub workflow, issue templates, PR process, commit conventions, and label
  taxonomy.
- [`yci/docs/profiles.md`](docs/profiles.md) — Full documentation of the
  `~/.config/yci/` data-root layout, profile YAML schema, and per-customer
  override fields. (Populated in Phase 0; linked here as a forward reference.)
- [`docs/prps/prds/yci.prd.md`](../docs/prps/prds/yci.prd.md) — The
  authoritative PRD. All design decisions, defaults, non-goals, and the phased
  rollout plan are locked here as of 2026-04-20.
