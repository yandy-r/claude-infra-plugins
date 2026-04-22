---
schema: pci/1
change_id: { { change_id } }
timestamp_utc: { { timestamp_utc } }
approver: { { approver } }
profile_commit: { { profile_commit } }
cde_boundary_attestation: { { cde_boundary_attestation } }
pan_redaction_status: { { pan_redaction_status } }
operator_identity: { { operator_identity } }
---

# PCI Evidence: {{change_id}}

## Summary

{{change_summary}}

## Scope

- Customer: {{customer_id}}
- Engagement: {{engagement_id}}
- Tenant scope: {{tenant_scope_summary}}

## PCI Metadata

- CDE boundary attestation: {{cde_boundary_attestation}}
- PAN redaction: {{pan_redaction_status}}
- Operator: {{operator_identity}}

## Approvals

{{#each approvals}}- {{this}}
{{/each}}

## Pre-Check Artifacts

{{#each pre_check_artifacts}}- {{this}}
{{/each}}

## Post-Check Artifacts

{{#each post_check_artifacts}}- {{this}}
{{/each}}

## Rollback Plan

{{rollback_plan}}
