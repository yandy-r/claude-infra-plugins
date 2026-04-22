---
schema: hipaa/1
change_id: { { change_id } }
timestamp_utc: { { timestamp_utc } }
approver: { { approver } }
profile_commit: { { profile_commit } }
baa_reference: { { baa_reference } }
phi_redaction_status: { { phi_redaction_status } }
operator_identity: { { operator_identity } }
---

# HIPAA Evidence: {{change_id}}

## Summary

{{change_summary}}

## Scope

- Customer: {{customer_id}}
- Engagement: {{engagement_id}}
- Tenant scope: {{tenant_scope_summary}}

## Compliance Metadata

- BAA reference: {{baa_reference}}
- PHI redaction: {{phi_redaction_status}}
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
