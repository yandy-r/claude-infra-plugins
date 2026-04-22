---
schema: soc2/1
change_id: { { change_id } }
timestamp_utc: { { timestamp_utc } }
approver: { { approver } }
profile_commit: { { profile_commit } }
operator_identity: { { operator_identity } }
---

# SOC 2 Evidence: {{change_id}}

## Summary

{{change_summary}}

## Scope

- Customer: {{customer_id}}
- Engagement: {{engagement_id}}
- Tenant scope: {{tenant_scope_summary}}
- Operator: {{operator_identity}}

## CC-Series Control Mapping

{{#each control_mappings}}- {{this}}
{{/each}}

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
