# PCI Compliance Adapter

## Regime

`pci`

## Intent

This adapter implements PCI-DSS-shaped evidence bundles for engagements that
touch cardholder data environments. It adds PAN redaction, CDE boundary
attestation fields, and explicit payment-scope handoff checks on top of the
baseline evidence bundle contract.

## Evidence schema

File: `evidence-schema.json`
Schema version: `1`

Required adapter-specific fields:

| Field                      | Type   | Description                                      |
| -------------------------- | ------ | ------------------------------------------------ |
| `cde_boundary_attestation` | string | Statement describing the affected CDE boundary   |
| `pan_redaction_status`     | string | Whether PAN redaction rules were applied         |
| `operator_identity`        | string | Human operator who assembled the evidence bundle |

## Evidence template

File: `evidence-template.md`

Includes CDE boundary attestation, tenant scope, approvals, and artifact lists.

## Redaction rules

File: `pan-redaction.rules`

Pattern classes applied:

- PAN-like 13-19 digit values
- Masked PAN variants
- CVV/CVC markers

## Handoff checklist

File: `handoff-checklist.md`

The reviewer confirms PAN redaction, CDE boundary accuracy, and signature
metadata before the bundle leaves the engagement.
