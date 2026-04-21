<!-- Template note: this file is the evidence artifact template for the
     commercial compliance adapter. The authoritative contract — including
     field definitions, schema version, redaction rules, and versioning
     policy — is ADAPTER.md in this directory. Schema version: 1. -->

---

schema: commercial/1
change_id: {{change_id}}
timestamp_utc: {{timestamp_utc}}
approver: {{approver}}
profile_commit: {{profile_commit}}

---

# Evidence: {{change_id}}

## Summary

{{change_summary}}

## Pre-Check Artifacts

{{#each pre_check_artifacts}}- {{this}}
{{/each}}

## Post-Check Artifacts

{{#each post_check_artifacts}}- {{this}}
{{/each}}

## Rollback Plan

{{rollback_plan}}

---

<!-- Metadata note: the frontmatter above is machine-readable. Skills that
     consume this artifact should parse it as YAML. All eight required fields
     from evidence-schema.json version 1 must be present before the artifact
     is signed and handed off. See handoff-checklist.md for the reviewer gate. -->
