# SOC 2 Compliance Adapter

## Regime

`soc2`

## Intent

This adapter implements SOC-2-oriented evidence bundles for cloud-native
commercial customers. It adds CC-series control mapping metadata while keeping
the baseline bundle shape compatible with the shared evidence pipeline.

## Evidence schema

File: `evidence-schema.json`
Schema version: `1`

Required adapter-specific fields:

| Field               | Type          | Description                                  |
| ------------------- | ------------- | -------------------------------------------- |
| `control_mappings`  | array[string] | CC-series controls satisfied by the evidence |
| `operator_identity` | string        | Human operator who assembled the evidence    |

## Evidence template

File: `evidence-template.md`

Includes CC-series control mappings, tenant scope, approvals, and artifact
lists.

## Redaction rules

File: `soc2-redaction.rules`

Applies lightweight internal-hostname and ticket-token redaction specific to
SOC 2 evidence handoff.

## Handoff checklist

File: `handoff-checklist.md`

The reviewer confirms CC-series mapping completeness and signature metadata
before the bundle leaves the engagement.
