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

> **Phase 0 excludes adapter implementation.** The layout and requirements
> described below are a design contract for Phase 1 and later phases, not a
> Phase-0 deliverable. No adapter directories or schemas ship in Phase 0.
> This section exists to lock the pattern early so future contributions conform.

### Directory Layout (future phases)

When adapters ship, they should live under
`yci/skills/_shared/compliance-adapters/`, one directory per supported regime:

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

When implemented in a later phase, each regime directory is expected to contain
at minimum:

- `ADAPTER.md` — declares what the adapter promises: which evidence fields it
  requires, what redaction rules it applies, and any regime-specific invariants.
- `evidence-schema.json` — the required field set for an evidence bundle under
  this regime.
- `evidence-template.md` — the markdown template used to render an evidence
  artifact for this regime.
- Redaction rules as applicable (e.g., `phi-redaction.rules` for HIPAA).
- `handoff-checklist.md` — a reviewer checklist confirming the deliverable
  meets the regime's expectations before it leaves the engagement.

The `none` adapter is expected to be exempt from the evidence schema and
redaction rules — its checklist is minimal by design.

### How Skills Should Use Adapters (design contract)

A skill that emits a compliance-relevant artifact (evidence bundle, MOP,
handoff pack) should read `compliance.regime` from the active customer profile
and load the matching adapter directory. Schema, redaction rules, and templates
are adapter-provided. The skill should not branch on regime names in its own code.

Correct:

```
# skill loads adapter path from profile
adapter_dir="${CLAUDE_PLUGIN_ROOT}/skills/_shared/compliance-adapters/${regime}"
schema="${adapter_dir}/evidence-schema.json"
template="${adapter_dir}/evidence-template.md"
```

Incorrect:

```bash
# never do this — hardcoded regime logic belongs in the adapter, not the skill
if [[ "${regime}" == "hipaa" ]]; then
  ...
fi
```

### Adding a New Regime

Add a new directory under `compliance-adapters/` with the required files. The
core `yci` skill code does not change. The new adapter is available to all
skills as soon as the directory exists and is wired into the active profile's
`compliance.regime` field.

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
