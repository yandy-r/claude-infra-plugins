# yci Customer Profiles and Data-Root Layout

`yci` never commits customer data to this repository. Customer state — profiles,
vaults, inventories, change calendars, and deliverable artifacts — lives under
`$YCI_DATA_ROOT` (default `~/.config/yci/`, mode 0700). This document explains
where that data lives, how the root is resolved, and how per-customer overrides
work. For the outside-repo policy and commit rules, see
[`yci/CONTRIBUTING.md`](../CONTRIBUTING.md). For the authoritative profile YAML
schema and all design decisions, see
[`docs/prps/prds/yci.prd.md`](../../docs/prps/prds/yci.prd.md) §5.2.

---

## Data-Root Resolution

The data root is resolved at runtime. The first match in the following chain wins:

1. `--data-root <path>` — explicit CLI flag, session-scoped.
2. `$YCI_DATA_ROOT` — environment variable, session-scoped.
3. Default: `~/.config/yci/` — per-user, outside any git repo, created with
   mode 0700 on first use.

Every skill and script that references the data root must implement this resolution
chain. Hard-coding `~/.config/yci/` is a defect — it breaks the moment an operator
sets `$YCI_DATA_ROOT` or passes `--data-root`.

See PRD §5.1 and §11.9 for the authoritative specification.

---

## Default Layout

Under the resolved root, `yci` expects the following directory tree:

```text
$YCI_DATA_ROOT/              # default ~/.config/yci/
├── profiles/
│   ├── <customer>.yaml      # per-customer profile config (non-secret)
│   ├── _internal.yaml       # stock homelab / internal profile
│   └── _template.yaml
├── state.json               # active profile + MRU history
├── vaults/
│   └── <customer>/...       # default secrets store (mode 0700)
├── inventories/
│   └── <customer>/...       # default CMDB / device cache
├── calendars/
│   └── <customer>/...       # default change-window sources
└── artifacts/
    └── <customer>/<engagement>/<timestamp>-<type>/
```

The `profiles/` directory holds non-secret YAML documents — one per customer
engagement. Vault contents (credentials, tokens, keys) are never stored in a
`.yaml` profile file; they live under `vaults/` and should be encrypted at rest
(`age` or `sops` are recommended).

`state.json` is written by `/yci:switch` to record the currently active profile
and the most-recently-used history. It is machine-managed; do not edit by hand.

---

## Per-Customer Path Overrides

The four profile fields `vaults.path`, `inventory.path`, `calendars.path`, and
`deliverable.path` each override the corresponding default subtree. This lets a
customer mandate where data lands without changing the global root.

Common consulting patterns (drawn from PRD §11.10):

- `~/Dropbox-Acme/deliverables/` — Dropbox desktop-synced
- `~/OneDrive-Acme/deliverables/` — OneDrive desktop-synced
- `~/gdrive/Acme/deliverables/` — Google Drive for Desktop or rclone mount
- `/Volumes/Acme-NAS/deliverables/` — shared network drive
- `~/Encrypted-Customers/acme/` — separate encrypted volume
- `onepassword://acme-vault` — direct 1Password reference (secrets only)

These paths are resolved at skill runtime, not at scaffold time. Profile-swap
transparently relocates where output lands — no script edits required.

---

## Profile Schema Overview

A customer profile is a YAML document with the following top-level keys:

- `customer` — stable identifier (`id`), display name, and optional branding.
- `engagement` — engagement identifier, type (`discovery|design|implementation|ongoing`),
  SOW reference, scope tags, and date range.
- `compliance` — regime (`hipaa|pci|sox|soc2|iso27001|nist|commercial|none`) and
  evidence schema version.
- `change_window` — optional adapter, source, and timezone for maintenance windows.
- `inventory` — adapter selection and endpoint or path for the CMDB/device cache.
- `approval` — adapter selection and endpoint for the change-approval system.
- `vaults` — path override for the secrets store (default: data root subtree).
- `deliverable` — output format list, header template, handoff format, and path
  override for artifacts.
- `vendor_tooling` — list of `{vendor, product, version}` records relevant to this
  engagement.
- `safety` — `default_posture` (`dry-run|review|apply`), `change_window_required`,
  and `scope_enforcement` (`warn|block|off`).

This is a summary only. Do not rely on it as a specification. The canonical schema
with all fields, allowed values, and validation rules is in PRD §5.2.

---

## Example: \_internal Profile

The file [`yci/docs/profiles/_internal.yaml.example`](profiles/_internal.yaml.example)
in this repository is a ready-to-copy template for homelab and consultant-internal
use. Copy it to `$YCI_DATA_ROOT/profiles/_internal.yaml` to activate it, or use it
as a starting point when scaffolding a new low-friction profile.

The `_internal` template uses relaxed defaults throughout:

- `compliance.regime: none` — no formal compliance framing; no evidence schema
  enforced.
- No `change_window` block — homelab work has no maintenance windows.
- `safety.default_posture: review` — neither dry-run nor auto-apply; every change
  goes to a human for review before action.
- `scope_enforcement: off` — no SOW boundary to enforce for internal work.

These defaults match the decision recorded in PRD §11 Q5.

---

## Never-Commit Rule

Operational profiles, vault contents, inventories, change calendars, and
deliverable artifacts are **never** committed to this repository. The rule applies
without exception to every file under `$YCI_DATA_ROOT` that carries real customer
data.

The file `yci/docs/profiles/_internal.yaml.example` is explicitly safe to commit
because:

1. It is a **template**, not an operational profile.
2. `_internal` is not a real customer — it identifies internal/homelab work with
   no customer data in scope.
3. The `.yaml.example` suffix prevents tooling and operators from treating it as
   an active profile.

No other `.yaml` or `.yaml.example` profile from `$YCI_DATA_ROOT` should appear in
a commit, pull request, or code review. If you find one, treat it as a security
incident and remove it from git history immediately.

For the full policy, see the
[Customer-Data-Outside-Repo Rule](../CONTRIBUTING.md#customer-data-outside-repo-rule)
section in `yci/CONTRIBUTING.md`.
