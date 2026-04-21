# Artifact Template

## Contract

This file documents the slot contract for the `yci:network-change-review` output
artifact, followed by the template itself. `render-artifact.sh` reads the template
and performs literal `{{slot_name}}` → value replacement for every slot listed below.
There is no Jinja2, no Handlebars `{{#each}}`, no helper functions — replacement is a
single-pass `sed`-compatible substitution where each `{{name}}` token is replaced with
the precomputed string value for that slot. A slot present in the template but absent
from the replacement map is a fatal error — `render-artifact.sh` exits with
`ncr-branding-template-missing` or `ncr-adapter-template-missing` depending on which
slot source failed, and discards the partially-rendered artifact.

### Slot Map

| Slot name                         | Filled from                                                                                      | Failure if missing                 |
| --------------------------------- | ------------------------------------------------------------------------------------------------ | ---------------------------------- |
| `{{customer_brand_block}}`        | `profile.deliverable.header_template` — path to a markdown file OR inline markdown string        | `ncr-branding-template-missing`    |
| `{{consultant_brand_block}}`      | `./consultant-brand.md` verbatim contents (with its own `{{yci_commit}}` resolved first)         | `ncr-adapter-template-missing`     |
| `{{change_id}}`                   | `evidence_stub.change_id` — the sha256-derived identifier from `render-evidence-stub.sh`         | fatal (hard stop)                  |
| `{{timestamp_utc}}`               | `evidence_stub.timestamp_utc` — ISO8601 UTC string                                               | fatal (hard stop)                  |
| `{{customer_id}}`                 | `evidence_stub.customer_id` — stable slug from active profile                                    | fatal (hard stop)                  |
| `{{compliance_regime}}`           | `evidence_stub.compliance_regime` — e.g. `commercial`, `none`                                    | fatal (hard stop)                  |
| `{{change_summary}}`              | `parse-change.sh` normalized JSON `summary` field                                                | fatal (hard stop)                  |
| `{{change_plan}}`                 | `ycc:plan` subagent output (markdown)                                                            | fatal (hard stop)                  |
| `{{diff_review}}`                 | `yci:change-reviewer` subagent output (markdown)                                                 | fatal (hard stop)                  |
| `{{blast_radius}}`                | `yci:blast-radius` rendered markdown output                                                      | fatal (hard stop)                  |
| `{{rollback_plan}}`               | `derive-rollback.sh` rendered rollback steps (markdown)                                          | fatal (hard stop)                  |
| `{{rollback_confidence_callout}}` | Empty string when `rollback_confidence` is `high`; visible warning block when `low` or `medium`  | n/a (always computed)              |
| `{{pre_check_catalog}}`           | `build-check-catalogs.sh` pre-check section (markdown checklist)                                 | fatal (hard stop)                  |
| `{{post_check_catalog}}`          | `build-check-catalogs.sh` post-check section (markdown checklist)                                | fatal (hard stop)                  |
| `{{evidence_stub}}`               | Full YAML frontmatter from `render-evidence-stub.sh` (code-fenced, collapsible)                  | fatal (hard stop)                  |
| `{{yci_commit}}`                  | `git -C <plugin-repo-root> rev-parse HEAD` — used inside `{{consultant_brand_block}}` and footer | resolved before brand block render |
| `{{profile_commit}}`              | `evidence_stub.profile_commit` — git commit hash of the profile snapshot                         | fatal (hard stop)                  |

### Slot-Replacement Algorithm

1. Resolve `{{yci_commit}}` first (needed by `consultant-brand.md` before it can be
   embedded as `{{consultant_brand_block}}`).
2. Load `./consultant-brand.md`, replace `{{yci_commit}}`, capture as
   `consultant_brand_block` value.
3. Load the path from `profile.deliverable.header_template`; if it is a file path,
   read it; if it is an inline string, use it directly. Capture as
   `customer_brand_block`. If path is set but file not found, exit
   `ncr-branding-template-missing`.
4. Run `render-evidence-stub.sh` to produce the YAML stub; code-fence it inside a
   `<details>` block for the `{{evidence_stub}}` slot.
5. For every remaining `{{slot_name}}` in the template, perform a global literal
   string replacement using the precomputed value.
6. After rendering, run `customer-isolation/detect.sh` on the artifact. If it exits
   non-zero, discard the artifact and exit `ncr-cross-customer-leak-detected`.

---

## Template

> Copy everything below the horizontal rule verbatim. Do not add or remove slots.

---

{{customer_brand_block}}

{{consultant_brand_block}}

---

## Network Change Review

**Change ID:** `{{change_id}}`
**Customer:** `{{customer_id}}`
**Compliance regime:** `{{compliance_regime}}`
**Timestamp (UTC):** `{{timestamp_utc}}`

---

## Change Summary

{{change_summary}}

---

## Change Plan

{{change_plan}}

---

## Diff Review

{{diff_review}}

---

## Blast Radius

{{blast_radius}}

---

## Rollback Plan

{{rollback_plan}}

{{rollback_confidence_callout}}

---

## Pre-Change Check Catalog

{{pre_check_catalog}}

---

## Post-Change Check Catalog

{{post_check_catalog}}

---

## Evidence Stub

{{evidence_stub}}

---

_Generated by `yci:network-change-review`. Profile commit: `{{profile_commit}}`. yci commit: `{{yci_commit}}`._

---

## Rendered Example (Abbreviated)

The following shows what a filled artifact looks like after slot replacement. Content
is abbreviated for illustration; real artifacts contain full subagent output.

```markdown
---
## Customer Branding

**WIDGET CORP** — Internal IT Change Management
Engagement: SOW-2026-007

---

## Prepared by

**Consulting:** Yandy Consulting Infrastructure (yci)
**Contact:** consultant@example.invalid
**Skill:** `yci:network-change-review`
**Version:** 78e907b3

> This deliverable was prepared under an active engagement. Redistribution is
> restricted per SOW.

---

# Network Change Review

**Change ID:** `a3f1b2c4-20260421-1430`
**Customer:** `widget-corp`
**Compliance regime:** `commercial`
**Timestamp (UTC):** `2026-04-21T14:30:00Z`

---

## Change Summary

Adjust MTU on primary edge router dc1-edge-01 from 1500 to 9000 bytes to support
jumbo frames on the orders-api path.

---

## Change Plan

1. Confirm maintenance window open.
2. Apply MTU change to dc1-edge-01 GigabitEthernet0/0.
3. Verify reachability via ping from upstream peer.

---

## Diff Review

**Risk:** Low. Single-line config change; no service removal.
**Concerns:** Jumbo frames must be supported end-to-end. Verify peer interface MTU.

---

## Blast Radius

**Impact level:** medium
Affected: dc1-edge-01 (primary edge path for orders-api). Downstream services:
orders-api, inventory-service. Indirect: payment-gateway (shares edge path).

---

## Rollback Plan

1. Set mtu 1500 on GigabitEthernet0/0 of dc1-edge-01.
2. Verify reachability restored.
3. Document rollback in change ticket.

---

## Pre-Change Check Catalog

- [ ] Ping dc1-edge-01 from upstream peer; expect <1ms RTT.
- [ ] Verify current MTU: `show interface GigabitEthernet0/0 | include MTU`.

---

## Post-Change Check Catalog

- [ ] Ping dc1-edge-01 from upstream peer; expect <1ms RTT.
- [ ] Verify new MTU: `show interface GigabitEthernet0/0 | include MTU`.
- [ ] Confirm orders-api health endpoint returns HTTP 200.

---

## Evidence Stub

<details>
<summary>Evidence YAML (expand to view)</summary>

\`\`\`yaml
schema_version: "commercial/1"
change_id: "a3f1b2c4-20260421-1430"
...
\`\`\`

</details>

---

_Generated by `yci:network-change-review`. Profile commit: `d4e5f6a7`. yci commit: `78e907b3`._
```
