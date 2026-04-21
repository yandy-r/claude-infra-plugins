# PRD — `yci` (Yandy Claude Infra)

**Status**: v2 — decisions locked 2026-04-20, ready for Phase 0
**Author**: Claude (synthesized from `docs/research/ycc-ecosystem-enhancements/`
and owner clarification)
**Date**: 2026-04-20
**Target**: new sibling plugin in the `yandy-r/claude-plugins` marketplace
**Codename / namespace**: `yci:` (parity with `ycc:` shortness)

## 0. Decisions Log (locked 2026-04-20)

All §11 defaults accepted as-is. Residual questions answered:

| #   | Question                | Decision                                                                                                                                                                                                                                                     |
| --- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Q1  | Profile file format     | **YAML**                                                                                                                                                                                                                                                     |
| Q2  | Airgapped mode          | **No** — no customer requires it; do not add an `airgapped` profile flag. Revisit only if a future engagement requires it.                                                                                                                                   |
| Q3  | Deliverable branding    | **Dual-branded** — consultant brand + customer brand on every deliverable. Profile's `deliverable.header_template` is required; consultant-brand fallback is always present.                                                                                 |
| Q4  | Handoff delivery format | **Mixed** — per-profile `deliverable.handoff_format` field. Ship `git-repo` and `zip` adapters first; Confluence export / PDF bundle land later as P1 when a customer requires them.                                                                         |
| Q5  | Homelab / internal use  | **Yes, first-class secondary use case.** Primary is external customer work, but a stock `_internal` profile ships with the bundle with relaxed defaults (no compliance regime = `none`; no change-window; `safety.default_posture: review`; scope-gate off). |
| Q6  | AI-disclosure clause    | **Skip for now.** Not an issue with current customer mix. Add a `disclosure.*` field only when a specific customer requires it.                                                                                                                              |

All other decisions in this PRD are locked by these answers. Phase 0 is
green-lit to begin.

> **Δ from v1**: v1 assumed in-house multi-tenant operator. v2 reframes `yci`
> as a **consulting / systems-integration toolkit** operated across many
> customer engagements (healthcare, financial, commercial). This changes the
> primary abstraction from "tenant" to **"customer profile"**, makes
> cross-customer data isolation load-bearing, and turns compliance into an
> adapter pattern rather than a baked-in choice.

---

## 1. Problem Statement

The owner is a consultant / systems integrator. Work flows through a
sequence of customer engagements — sometimes discovery/assessment, sometimes
design, sometimes implementation, sometimes ongoing ops. Each engagement has
its own:

- **Compliance regime**: HIPAA/HITECH (healthcare), SOX/PCI-DSS/GLBA/FINRA
  (financial), SOC 2 / ISO 27001 / NIST 800-53 (many commercial), or none
  formally named.
- **Change-management posture**: CAB with a ServiceNow calendar; informal
  "email before Saturday"; ticketed iCal freeze periods; vendor-specific
  blackout windows; "do whatever, tell us after".
- **Inventory / CMDB**: NetBox, Nautobot, ServiceNow CMDB, Infoblox, a
  spreadsheet, or literally nothing.
- **Approval workflow**: Jira, Linear, GitHub PRs, email, verbal.
- **Secrets boundary**: absolute. Customer A's output must never appear
  in Customer B's session, artifact, git commit, or evidence bundle.
- **Tooling versions**: their Cisco IOS is 16.x, yours is 17.x; their
  PAN-OS is 10.1, yours is 11.2; their Terraform is 1.5, yours is 1.8.
- **Deliverable form**: some want markdown, some Word, some Confluence,
  some PDF with a cover page and the client's logo.
- **Engagement scope (SOW)**: narrowly defined, and scope creep is a
  billing / legal issue, not just a planning one.

The existing `ycc` bundle is dev-focused and has no concept of
"customer context," compliance, change windows, or cross-customer data
isolation. Folding this vertical in also degrades `ycc`'s dev-user
experience (descriptor pollution, fragility-cliff proximity).

`yci` is a separate plugin that owns **the consulting-engagement workflow**:
load a customer profile → work inside that profile's guardrails → produce
customer-ready deliverables → hand off cleanly → switch profiles without
leakage.

## 2. Audience & Context (non-negotiable framing)

- **Primary user**: the owner, operating as a **consultant / systems
  integrator** across many customer engagements, often touching
  **production large-scale multi-tenant environments inside each
  customer**.
- **Secondary use case**: homelab / consultant-internal work. First-
  class, supported via a stock `_internal` profile with relaxed
  defaults (compliance = `none`; no change-window; `safety.default_posture:
review`; scope-gate off).
- **Working rhythm**: profile-swap is daily or multi-times-daily.
  Monday morning at Customer A, Tuesday afternoon at Customer B, evening
  at the homelab.
- **Threat model**:
  1. **Cross-customer data leakage** — including in LLM context. This
     is the #1 security concern. Career-ending if it happens.
  2. **Out-of-scope work** — changes outside the SOW create billing
     disputes and scope creep.
  3. **Inadequate handoff** — artifacts that are internal-quality-only
     leave the customer unable to operate what you built.
  4. **Compliance drift** — using a HIPAA-flavored workflow on a
     non-healthcare customer (over-engineered) or vice versa (under-
     engineered and non-compliant).
- **Secondary users**: none planned, but `yci` should be **generic
  enough** that another consultant could adopt it by filling in
  their own customer profiles without `yci` source edits.

**Consequence**: every artifact must pass three questions:

1. _"Which customer is this for?"_ — answerable unambiguously from the
   artifact itself.
2. _"Is this deliverable handoff-ready?"_ — customer-facing formatting,
   no consultant-internal shortcuts, no cross-customer references.
3. _"Does this fit the engagement scope?"_ — or at least flagged if
   it doesn't.

## 3. Success Criteria

A `yci` release is successful when:

1. **Zero cross-customer leaks**: every artifact ever produced is
   unambiguously scoped to one customer, and the sanitizer/guard
   layer has never allowed cross-customer content into an artifact.
2. **Profile switching is frictionless**: `/yci:switch <customer>` (or
   equivalent) loads the full context in one command. Everything
   downstream honors it.
3. **Compliance adapts, not hardcodes**: the same `yci:evidence-bundle`
   skill produces HIPAA-shaped evidence for one customer, PCI-shaped
   for another, commercial-shaped for a third — driven by the loaded
   profile.
4. **Deliverables are handoff-ready**: MOPs, as-builts, runbooks,
   evidence bundles all look like something the customer would be
   comfortable showing to their auditors or operators — no consultant-
   internal jargon, no cross-customer references, client branding
   where declared.
5. **Composition with `ycc`**: `yci` invokes `ycc:plan`, `ycc:code-review`,
   `ycc:write-docs` freely. Zero duplication.
6. **Small**: ≤ 14 skills + ≤ 10 hooks + ≤ 6 agents + ≤ 12 commands at
   12 months. A sunset review runs before count creeps past these.

## 4. Non-Goals (explicit rejects)

- **No hardcoded compliance regime.** HIPAA is not "the default"; PCI is
  not "the default"; commercial is not "the default". Every artifact
  adapts to the loaded profile.
- **No assumption of a specific inventory / CMDB / change-window system.**
  All of these are **adapter-shaped**: `yci` defines the interface, the
  customer profile points at the adapter (or at "none").
- **No vendor-per-skill matrix.** Same logic as v1: vendor MCPs + native
  tooling saturate this niche; a per-vendor skill inherits a 5-10y
  half-life.
- **No cloud-provider skills.** Foundation models cover these fluently;
  official MCPs saturate orchestration. Anything cloud-specific lives
  inside a workflow skill (e.g., `yci:blast-radius` knows how to parse
  AWS ARNs).
- **No K8s / container-security / virtualization domain trees.** Existing
  tooling saturates; safety is a hook.
- **No LLM knowledge dumps.** Adverse-to-model pitfalls skills are fine;
  "how to write Cisco ACLs" skills are not.
- **No auto-apply for destructive operations.** `yci` reads, diffs,
  plans, produces artifacts. The operator applies via their (or the
  customer's) pipeline.
- **No in-repo customer data.** No customer names, credentials, IPs,
  configs ever committed to `yandy-r/claude-plugins`. Customer profiles
  live **outside** the repo — in `$YCI_DATA_ROOT` (default
  `~/.config/yci/`) — and are loaded at runtime.
- **No hardcoded data-root path.** `~/.config/yci/` is the _default_; the
  actual root is configurable per operator. Per-customer paths (for
  customers who require artifacts in their own Dropbox / OneDrive /
  GDrive / shared drive) are profile-field overrides — see §5.1.

## 5. Architecture

### 5.1 Repo layout

```
claude-plugins/
├── .claude-plugin/
│   └── marketplace.json         # 2 entries: ycc + yci
├── ycc/                         # unchanged
├── yci/                         # NEW
│   ├── .claude-plugin/
│   │   └── plugin.json          # name: "yci"
│   ├── hooks/
│   │   ├── customer-guard/      # cross-customer isolation (THE hook)
│   │   ├── context-guard/       # wrong env within a customer
│   │   ├── change-window-gate/
│   │   ├── scope-gate/          # SOW-boundary check
│   │   ├── secret-scan/
│   │   └── _shared/
│   ├── skills/
│   │   ├── _shared/
│   │   │   ├── customer-profile/     # profile load/save/switch
│   │   │   ├── telemetry-sanitizer/  # cross-customer redaction
│   │   │   ├── compliance-adapters/  # HIPAA, PCI, SOC2, commercial, none
│   │   │   └── changewindow-adapters/ # iCal, SNow, JSON, "none"
│   │   └── {skill-name}/SKILL.md
│   ├── agents/
│   ├── commands/
│   └── docs/
├── .cursor-plugin/
│   ├── ycc/
│   └── yci/                     # generated
├── .codex-plugin/
│   ├── ycc/
│   └── yci/                     # generated
└── .opencode-plugin/
    └── {yci artifacts}
```

**Customer data lives OUTSIDE the repo. The root is configurable.**

**Data-root resolution** (precedence, first match wins):

1. `--data-root <path>` CLI flag (session-scoped, explicit).
2. `$YCI_DATA_ROOT` env var (session-scoped).
3. Default: `~/.config/yci/`.

The resolved root contains the stock layout below. Every subtree is
**also** overridable per-customer via the profile (see §5.2) for the
common consulting case where a customer mandates "artifacts must land in
this Dropbox folder" or "vault lives in 1Password, not on disk."

```
$YCI_DATA_ROOT/               # default ~/.config/yci/
├── profiles/
│   ├── acme-healthcare.yaml  # profile config (non-secret)
│   ├── bigbank-cdc.yaml
│   ├── widgetco.yaml
│   ├── _internal.yaml        # stock homelab/internal profile
│   └── _template.yaml
├── state.json                # active profile + MRU history
├── vaults/
│   └── {customer}/...        # default secrets store (mode 0700)
├── inventories/
│   └── {customer}/...        # default CMDB/device cache
├── calendars/
│   └── {customer}/...        # default change-window sources
└── artifacts/
    └── {customer}/{engagement}/{timestamp}-{type}/   # default deliverables
```

**Per-customer overrides** (profile fields — see §5.2): each of
`vaults`, `inventories`, `calendars`, `deliverable` may specify a `path`
pointing anywhere — including a mounted cloud folder
(`~/Dropbox-Acme/`, `~/OneDrive-Bank/`, `~/gdrive/`, an rclone mount),
a shared network drive, or a separate encrypted volume. The paths are
**resolved at skill runtime, not at scaffold time**, so profile-swap
transparently relocates where output lands.

**Upload adapters** (`dropbox://`, `gdrive://`, `onedrive://`, `s3://`)
for direct-to-cloud upload are **deferred** to Phase 3 or later. For
Phase 0-2, the pragmatic pattern is "write to a local path; let the OS
sync it" via the desktop client each cloud provider ships.

### 5.2 Customer Profile (the load-bearing primitive)

A profile is a YAML document describing one customer engagement:

```yaml
# ~/.config/yci/profiles/acme-healthcare.yaml
customer:
  id: acme-healthcare # stable identifier, used as scope label
  display_name: 'Acme Health'
  branding: # dual-branding: customer brand is required,
    # consultant brand always composited alongside
    logo_path: ~/.config/yci/branding/acme.png
    color: '#003366'

engagement:
  id: acme-2026-network-refresh
  type: implementation # discovery|design|implementation|ongoing
  sow_ref: 'SOW-2026-0117'
  scope_tags: [network, firewall, ipsec]
  start_date: 2026-03-01
  end_date: 2026-09-30

compliance:
  regime: hipaa # hipaa|pci|sox|soc2|iso27001|nist|commercial|none
  baa_reference: 'Acme-BAA-2026-001'
  evidence_schema_version: 1

change_window:
  adapter: ical
  source: ~/.config/yci/calendars/acme-healthcare/changewindow.ics
  timezone: America/Chicago

inventory:
  adapter: netbox
  endpoint: https://netbox.example-internal.acme/api
  credential_ref: acme-healthcare/netbox-token
  path: ~/Dropbox-Acme/inventories/ # optional override (default: $YCI_DATA_ROOT/inventories/acme-healthcare/)

approval:
  adapter: servicenow
  endpoint: https://acme.service-now.com/api
  credential_ref: acme-healthcare/snow

vaults:
  path: onepassword://acme-vault # optional override (default: $YCI_DATA_ROOT/vaults/acme-healthcare/)

deliverable:
  format: [markdown, pdf]
  header_template: ~/.config/yci/branding/acme-header.md # required
  handoff_format: git-repo # git-repo|zip|confluence|pdf-bundle
  path: ~/Dropbox-Acme/deliverables/ # OPTIONAL override (default: $YCI_DATA_ROOT/artifacts/acme-healthcare/)
  # Common consulting patterns for `path`:
  #   ~/Dropbox-Acme/deliverables/        # Dropbox desktop-synced
  #   ~/OneDrive-Acme/deliverables/       # OneDrive desktop-synced
  #   ~/gdrive/Acme/deliverables/         # rclone or Google Drive for Desktop
  #   /Volumes/Acme-NAS/deliverables/     # shared network drive
  #   ~/Encrypted-Customers/acme/         # separate encrypted volume

vendor_tooling:
  - { vendor: cisco, product: ios-xe, version: '17.9' }
  - { vendor: palo-alto, product: pan-os, version: '11.2' }
  - { vendor: vmware, product: vsphere, version: '8.0' }

safety:
  default_posture: dry-run # dry-run|review|apply
  change_window_required: true
  scope_enforcement: warn # warn|block|off
```

Profiles are loaded by `/yci:switch acme-healthcare` (or env-var, or
`.yci-customer` dotfile in the current directory). Every `yci` skill,
hook, and script reads the active profile and refuses to produce
output not tagged to that customer.

### 5.3 Compliance adapter pattern

`yci/skills/_shared/compliance-adapters/` contains one directory per
supported regime:

```
compliance-adapters/
├── hipaa/
│   ├── ADAPTER.md              # what this adapter promises
│   ├── evidence-schema.json    # required fields for HIPAA evidence
│   ├── evidence-template.md    # markdown template
│   ├── phi-redaction.rules     # telemetry-sanitizer rules
│   └── handoff-checklist.md
├── pci/
│   ├── ADAPTER.md
│   ├── evidence-schema.json    # PCI-DSS-shaped
│   ├── cde-boundary-attest.md
│   └── ...
├── sox/
├── soc2/
├── iso27001/
├── commercial/                 # generic best-practice, no specific regime
└── none/                       # literally no compliance framing
```

Every skill that produces a compliance-relevant artifact (evidence,
MOP, handoff pack) **reads `compliance.regime` from the active profile
and loads the matching adapter**. Schema, redaction rules, and template
are adapter-provided.

Add a new regime by adding a new directory. `yci` core code does not
change.

### 5.4 Change-window adapter pattern

Same structure:

```
changewindow-adapters/
├── ical/              # read .ics; check time/date
├── servicenow/        # query ServiceNow CAB via credential
├── json-schedule/     # simple JSON blackout calendar
├── always-open/       # no change window enforced
└── none/              # refuse to check; require explicit --override
```

Profile's `change_window.adapter` selects which is loaded.

### 5.5 Generator reuse

`scripts/sync.sh` + `scripts/validate.sh` must learn to iterate over a
plugin list. Both plugins build with the same generators; only their
inventories differ.

### 5.6 Composition with `ycc`

`yci` invokes `ycc` skills freely. Example flow:

```
/yci:switch bigbank-cdc
/yci:review proposed-change.diff
  ├─ yci:customer-guard (hook)         [verifies active customer]
  ├─ yci:scope-gate (hook)             [checks SOW scope tags]
  ├─ yci:network-change-review (skill) [main workflow]
  │   ├─ invokes ycc:plan              [planning scaffold]
  │   ├─ invokes ycc:code-review       [diff semantic review]
  │   ├─ yci:blast-radius              [cross-device impact]
  │   ├─ yci:compliance-adapter        [PCI-shaped evidence stub]
  │   └─ yci:telemetry-sanitizer       [redact before write]
  └─ writes to ~/.config/yci/artifacts/bigbank-cdc/...
```

## 6. Initial Artifact Set (revised for consulting/SI framing)

### 6.1 P0 — Ship first

**P0.1 — `yci/hooks/customer-guard` (THE load-bearing hook)**

- **Form**: PreToolUse hook (4-target matrix)
- **Prevents**: any tool call, artifact write, or output that references
  a customer different from the active profile. Blocks file reads from
  one customer's artifact dir while a different profile is active.
  Blocks pastes of config-looking text whose fingerprints match a
  different customer's known inventory.
- **Ships with**: `yci/skills/_shared/customer-profile/` (load,
  switch, detect active customer).
- **Effort**: L (the hook is the easy part; the detection library is
  where the work is).
- **Non-negotiable**: if P0.1 isn't reliable, `yci` cannot ship.

**P0.2 — `yci:customer-profile` skill (profile lifecycle)**

- **Form**: skill (+ scripts)
- **Commands**: `/yci:switch <id>`, `/yci:whoami` (print active),
  `/yci:init <id>` (scaffold a profile from template).
- **Effort**: M.

**P0.3 — `yci/skills/_shared/telemetry-sanitizer` (cross-customer redaction)**

- **Form**: shared library
- **Purpose**: redact secrets, PII (including PHI if HIPAA adapter
  loaded), IPs, MACs, and any token that matches a different customer's
  known identifiers. Runs before any output reaches an artifact.
- **Effort**: M (pattern library + per-adapter rules + tests).

**P0.4 — `yci:evidence-bundle` (compliance-adaptive)**

- **Form**: skill + scripts + reads compliance adapter
- **Output**: evidence pack in the active profile's compliance shape.
  Signed (per profile's signing discipline).
- **Effort**: M-L.

**P0.5 — `yci:network-change-review` (keystone workflow)**

- **Form**: skill (composes ycc:plan, ycc:code-review, yci:blast-radius,
  yci:compliance-adapter, yci:telemetry-sanitizer)
- **Output**: review report with blast radius, rollback, pre/post
  check catalogs, customer-branded header.
- **Effort**: M-L.

**P0.6 — `yci:mop` (MOP generator)**

- **Form**: skill — pre-check / apply / post-check / rollback /
  abort-criteria document in customer-deliverable format.
- **Effort**: M.

**P0.7 — `yci:blast-radius` reasoner**

- **Form**: skill + scripts + optional inventory-adapter integration
- **Output**: structured blast-radius label.
- **Effort**: M.

**P0.8 — `yci:hooks/change-window-gate` (adapter-backed)**

- **Form**: PreToolUse hook, reads active profile's changewindow
  adapter.
- **Effort**: S (once P0.1 hook scaffolding exists) + adapter work.

**P0.9 — `yci:hooks/scope-gate` (SOW-boundary check)**

- **Form**: PreToolUse hook — checks proposed change against
  `engagement.scope_tags` in active profile.
- **Behavior**: `warn` or `block` per `safety.scope_enforcement`.
- **Purpose**: flags scope creep in real time. Consultants under-bill
  because scope expands invisibly; this hook surfaces it.
- **Effort**: S-M.

### 6.2 P1 — Ship after P0 proves out

**P1.10 — `yci:cab-prep` (CAB submission generator)**

- Composes `yci:mop` + `yci:blast-radius` + `yci:evidence-bundle`
  into a customer-formatted CAB submission.
- Adapter-aware (different customers, different CAB formats).

**P1.11 — `yci:handoff-pack` (end-of-engagement deliverable)**

- Collects as-builts, runbooks, evidence, sign-off sheet, operator
  training notes into a single dual-branded deliverable directory.
- **Adapters**: `git-repo` and `zip` ship in Phase 3. `confluence`
  and `pdf-bundle` adapters add in Phase 4 when a customer requires.
- **Why important**: a clean handoff is the single biggest signal of
  consulting quality.

**P1.12 — `yci:as-built` (live → documentation)**

- Reads live state (via vendor MCP, CLI, or inventory adapter),
  produces as-built network/cluster/system documentation in the
  customer's deliverable format.

**P1.13 — `yci:discovery` (read-only assessment)**

- For discovery-phase engagements: inventory capture, configuration
  review, compliance-gap narrative. No write operations.

**P1.14 — `yci:hooks/secret-scan`**

- Prevents secrets in diffs, configs, evidence bundles, artifacts.
- Known-identifier list from profile (to detect cross-customer
  accidental exposure in addition to generic secret patterns).

**P1.15 — `yci:skill-telemetry` + `yci:sunset-review` (anti-sprawl)**

- Same purpose as in `ycc` — instrument invocation counts, nominate
  unused skills for archive. Essential because `yci` will accumulate
  adapter sub-skills over time.

**P1.16 — `yci:llm-infra-pitfalls`**

- Adverse-to-model checklist. Shares structure with the `ycc`
  equivalent discussed in the research.

### 6.3 P2 — Conditional

- `yci:incident-narrate` — post-change / post-incident write-up.
- `yci:config-drift` — RANCID-archetype on MCP transport, adapter-
  backed for vendor fan-out.
- `yci:tenant-inventory` — cache per-customer resource inventory
  (subsumed by inventory-adapter plumbing if well-designed).
- `yci:runbook-exec` — interactive runbook executor with evidence
  capture.

## 7. Agents

Keep minimal.

- **P0**: `yci:change-reviewer` — delegated-context reviewer paired
  with `yci:network-change-review`.
- **P1**: `yci:compliance-auditor` — reviews evidence bundles against
  the active profile's schema for completeness.
- **P1**: `yci:engagement-analyst` — helps scope a new engagement
  (generates a profile skeleton, asks for the missing inputs).
- **P2**: `yci:incident-responder`.

No per-vendor agents. No per-cloud agents. No per-compliance-regime
agents (compliance is an adapter, not an agent).

## 8. Commands

- `/yci:switch <customer>` — load profile
- `/yci:whoami` — print active customer / engagement / compliance regime
- `/yci:init <customer>` — scaffold new profile
- `/yci:review <change>` → `yci:network-change-review`
- `/yci:mop <change>` → `yci:mop`
- `/yci:evidence <change>` → `yci:evidence-bundle`
- `/yci:cab <change>` → `yci:cab-prep`
- `/yci:handoff` → `yci:handoff-pack`
- `/yci:as-built` → `yci:as-built`
- `/yci:discovery` → `yci:discovery`
- `/yci:scope-check <change>` → invokes scope-gate in report mode
- `/yci:sunset` → `yci:sunset-review`

## 9. Phased Rollout

### Phase 0 — Scaffolding (1 PR)

1. `yci/` directory with `plugin.json`.
2. Second entry in `marketplace.json`.
3. Empty `yci/hooks/`, `yci/skills/`, `yci/agents/`, `yci/commands/`.
4. `yci/CONTRIBUTING.md` with non-goals + compliance-adapter pattern
   documented.
5. Refactor `scripts/sync.sh` + `scripts/validate.sh` to iterate over a
   plugin list.
6. Add one trivial skill (`yci:hello` or similar) to prove the
   pipeline end-to-end.
7. Document the `~/.config/yci/` layout in `yci/docs/profiles.md`.
8. CI builds + validates both plugins.

### Phase 1 — P0 customer-profile foundation (highest leverage)

Ship in dependency order:

1. `yci:customer-profile` skill (P0.2) — nothing else works without it.
2. `yci/hooks/customer-guard` (P0.1) — the load-bearing safety hook.
3. `yci/skills/_shared/telemetry-sanitizer` (P0.3).
4. Compliance adapters for `commercial` and `none` (minimum viable).
5. `yci:blast-radius` (P0.7).
6. `yci:network-change-review` (P0.5).

Smoke test against a hypothetical customer before shipping P0.4+.

### Phase 2 — P0 workflow skills + remaining compliance adapters

7. `yci:evidence-bundle` (P0.4) + HIPAA, PCI, SOC 2 adapters.
8. `yci:mop` (P0.6).
9. `yci:hooks/change-window-gate` (P0.8) + iCal + JSON-schedule
   adapters minimum.
10. `yci:hooks/scope-gate` (P0.9).

### Phase 3 — P1, conditional on real-engagement usage

Only after the P0 set has been used in at least 2 different customer
engagements with different compliance regimes.

### Phase 4 — P2, only if specifically needed

## 10. Customer-Engagement Non-Negotiables

Every `yci` artifact MUST:

1. **Be tagged to exactly one customer** (or, if deliberately
   cross-customer like a company-internal template, explicitly
   labeled `customer: _internal`).
2. **Never contain another customer's identifiers** — names, IPs,
   hostnames, AS numbers, account IDs, project codes, SOW numbers.
   Sanitizer enforces.
3. **Declare its compliance regime** in metadata, matching the
   active profile at time of creation.
4. **Declare its engagement scope** — which SOW this change is
   billable against.
5. **Respect change-window status** if the customer's profile
   requires it.
6. **Be handoff-ready**: formatted for the customer's preferred
   deliverable format; no consultant-internal language; branding
   applied where configured.
7. **Be reproducible**: embed the profile ID + git commit of `yci` at
   generation time so the same artifact can be regenerated months
   later.
8. **Never auto-apply**. `yci` produces plans, diffs, rollback
   commands, evidence. The operator (or customer operator) applies.

## 11. Defaults (locked — all accepted 2026-04-20)

See §0 Decisions Log for the summary. Detailed defaults preserved below
as the implementation reference.

### 11.1 Authoritative customer-scope source

**Default**: precedence order —

1. `$YCI_CUSTOMER` env var (session-scoped, explicit).
2. `.yci-customer` dotfile in CWD or any ancestor dir (project-scoped).
3. Most recently used profile (state in `~/.config/yci/state.json`).
4. Refuse to run with a clear error if none resolves.

**Override if**: you use tmux per-customer with a different convention.

### 11.2 Compliance regimes to implement first

**Default ship order**:

1. `commercial` (generic best-practice, no specific regime) — covers
   most non-regulated customers.
2. `none` — literally no compliance framing, for internal / lab /
   non-production work.
3. `hipaa` — healthcare customers.
4. `pci` — financial customers with card data.
5. `soc2` — most cloud-native commercial customers.
6. `iso27001` — international / EU customers.
7. `sox` — publicly-traded financial customers (narrower scope than PCI).
8. `nist` — only if a federal customer enters the pipeline.

**Override if**: current customer mix weights differently.

### 11.3 Inventory / CMDB adapter ship order

**Default**:

1. `file` (manual YAML / JSON inventory file per customer — works
   when the customer has nothing).
2. `netbox` (open-source, common in mid-market).
3. `nautobot` (NetworkToCode successor, growing share).
4. `servicenow-cmdb` (enterprise / regulated customers).
5. `infoblox` (common in healthcare / financial for DNS/IPAM).

**Override if**: a specific customer CMDB needs priority.

### 11.4 Change-window adapter ship order

**Default**:

1. `always-open` (no enforced window — ship first for testing).
2. `ical` (simple, many customers maintain .ics).
3. `json-schedule` (trivial custom format when no calendar exists).
4. `servicenow-cab` (regulated / enterprise).
5. `none` (explicitly require --override every time — paranoid mode
   for unknown customers).

### 11.5 Approval workflow adapter ship order

**Default**:

1. `github-pr` (you already use GitHub; zero-friction for dev-adjacent
   customers).
2. `email-signoff` (attach a signed evidence bundle, email the
   customer-approver).
3. `jira` (many enterprise customers).
4. `servicenow-request` (regulated / enterprise CAB).
5. `none` (log only, no external system).

### 11.6 Signing discipline for evidence bundles

**Default**: `minisign` or `ssh-keygen -Y sign` (both are lightweight,
require no CA, produce verifiable signatures from standard keys).
**Upgrade to**: `sigstore` / `cosign` when a customer requires
transparency-log-backed signing (HIPAA orgs increasingly do).

**Override if**: a customer mandates a specific PKI / HSM.

### 11.7 Default posture

**Default**: `dry-run`. Every `yci` workflow produces a plan / diff /
review artifact by default. To move from plan to apply, operator must
pass `--apply` or equivalent flag AND the active profile's
`safety.default_posture` must not be `dry-run`.

**Override if**: a specific customer engagement is read-only (set
profile's `engagement.type: discovery` to force-ban writes).

### 11.8 Vendor MCP availability assumption

**Default**: assume **no** vendor MCP by default. Build CLI/SDK
fallback first, layer MCP integrations as they mature per-vendor.
Palo Alto Cortex is the likely first MCP to add (official beta in
2025).

**Override if**: the owner's customer base heavily uses one vendor
whose MCP is already production-ready.

### 11.9 Customer-data-at-rest location

**Default root**: `~/.config/yci/` — per-user, outside any git repo,
mode 0700. Profiles are YAML (non-secret); vaults are encrypted at rest
(recommend `age` or `sops`).

**Data-root resolution** (§5.1 precedence): `--data-root <path>` CLI
flag > `$YCI_DATA_ROOT` env var > default `~/.config/yci/`.

**Per-customer overrides** (profile YAML): `vaults.path`,
`inventories.path`, `calendars.path`, `deliverable.path` each override
the corresponding default subtree. Lets customers mandate
"secrets in 1Password, not on disk" or "artifacts in this Dropbox
folder" without changing the global root.

### 11.10 Deliverable output location

**Default**:
`$YCI_DATA_ROOT/artifacts/{customer}/{engagement}/{timestamp}-{type}/`
(where `$YCI_DATA_ROOT` is the resolved data root per §11.9).

**Per-customer override**: set `deliverable.path` in the profile to
_any_ path — common consulting patterns:

- `~/Dropbox-Acme/deliverables/` (Dropbox desktop-synced)
- `~/OneDrive-Bank/deliverables/` (OneDrive desktop-synced)
- `~/gdrive/Acme/deliverables/` (Google Drive for Desktop / rclone)
- `/Volumes/Acme-NAS/deliverables/` (shared network drive)
- `~/Encrypted-Customers/acme/` (separate encrypted volume)

**Upload adapters (`dropbox://`, `gdrive://`, `onedrive://`, `s3://`)**
are deferred to Phase 3+. For Phase 0-2, rely on the OS-level cloud
sync client each provider ships — `yci` writes to the local path; the
OS syncs. This keeps `yci` out of credential-management for cloud
storage and avoids provider-API breakage.

## 12. Residual Questions — Resolved

All answered in §0 Decisions Log. Summary:

- **Profile format**: YAML.
- **Airgapped mode**: No. No flag. Revisit if a future engagement requires it.
- **Branding**: Dual-branded. `deliverable.header_template` is required
  per-customer; consultant brand is always composited.
- **Handoff format**: Mixed per-profile. Ship `git-repo` + `zip` adapters
  first; Confluence + PDF-bundle as Phase-4 when a customer requires.
- **Homelab / internal**: First-class secondary use case. Stock
  `_internal` profile ships with relaxed defaults.
- **AI-disclosure**: Skip. Add `disclosure.*` fields only on demand.

## 13. Success Metrics (review after 90 days)

- Active profiles: ≥ 3 (indicates real cross-customer use).
- Zero cross-customer leak incidents.
- ≥ 5 real customer deliverables generated via `yci` workflows.
- ≥ 2 compliance adapters exercised (e.g., `commercial` + `hipaa`).
- `yci` skill count ≤ 14.
- ≥ 1 recorded prevention moment per hook class.

## 14. Next Step

**Status**: decisions locked. Phase 0 is green-lit pending owner "go"
on the scaffolding PR. Once Phase 0 is merged, Phase 1 begins with
`yci:customer-profile` + `customer-guard` hook + `telemetry-sanitizer`
(the foundation the rest depends on).

---

## Appendix A — Explicit Rejects (for the record)

- Per-vendor skill trees (Cisco, Fortinet, Juniper, Palo Alto).
- Per-cloud skill trees (AWS, Azure, GCP).
- Domain-size K8s / virtualization / container-security skill trees.
- LLM knowledge dumps restating vendor documentation.
- Auto-apply for destructive operations.
- Hardcoding of any single compliance regime.
- Committing customer data to the `claude-plugins` repo.

These are not open for P2 reconsideration without a documented
justification overriding this PRD.

## Appendix B — Δ from PRD v1

| v1 assumption                              | v2 reframe                                                     |
| ------------------------------------------ | -------------------------------------------------------------- |
| In-house multi-tenant operator             | Consultant / SI across many customers                          |
| "Tenant" is primary abstraction            | **Customer profile** is primary abstraction                    |
| Compliance is one-size-fits-all (pick one) | Compliance is **adapter-driven per profile**                   |
| Change-window is one-size-fits-all         | Change-window is **adapter-driven per profile**                |
| Evidence schema is fixed                   | Evidence schema is **compliance-adapter-provided**             |
| Tenant-isolation nice-to-have              | **Cross-customer isolation is load-bearing**                   |
| MOP for in-house ops                       | MOP as **customer-deliverable**                                |
| No engagement concept                      | **Engagement + SOW scope** are first-class                     |
| No handoff concept                         | **Handoff pack** is a P1 artifact                              |
| 12-skill 12-month cap                      | 14-skill 12-month cap (adapters + engagement types push it up) |
