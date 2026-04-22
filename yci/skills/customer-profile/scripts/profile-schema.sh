#!/usr/bin/env bash
# yci — profile schema declaration (source this file; do not execute directly).
#
# Single source of truth for required/optional keys and enum allowed values.
# Consumed by load-profile.sh, init-profile.sh, and the test harness.
#
# Keep in sync with:
#   - yci/skills/customer-profile/references/schema.md
#   - docs/prps/prds/yci.prd.md §5.2

# shellcheck disable=SC2034
# All YCI_* arrays below are sourced by downstream scripts (load-profile.sh,
# init-profile.sh, tests/) which read them via `${YCI_*[@]}` or export them
# to the environment. shellcheck can't see cross-file usage, so suppress
# SC2034 for the whole file.

# Top-level keys --------------------------------------------------------------

# Must appear in every valid profile.
YCI_PROFILE_REQUIRED_TOP_LEVEL=(customer engagement compliance inventory approval deliverable safety)

# May appear; loader warns if absent and does NOT error.
YCI_PROFILE_OPTIONAL_TOP_LEVEL=(change_window vaults vendor_tooling)

# Nested required fields ------------------------------------------------------
#
# Convention: YCI_<UPPERCASE_SECTION>_REQUIRED=(...) for each top-level section
# with nested requirements. Loader iterates these arrays.

YCI_CUSTOMER_REQUIRED=(id display_name)
YCI_ENGAGEMENT_REQUIRED=(id type sow_ref scope_tags start_date end_date)
YCI_COMPLIANCE_REQUIRED=(regime evidence_schema_version)
YCI_INVENTORY_REQUIRED=(adapter)
YCI_APPROVAL_REQUIRED=(adapter)
YCI_DELIVERABLE_REQUIRED=(format header_template handoff_format)
YCI_SAFETY_REQUIRED=(default_posture change_window_required scope_enforcement)

# Enum allowed values ---------------------------------------------------------
#
# IMPORTANT: these MUST match schema.md's enum sections verbatim. The loader
# rejects any value not in the array for the corresponding field.

# Values for compliance.regime (schema.md "Compliance regimes" / PRD §11.2).
YCI_COMPLIANCE_REGIMES=(hipaa pci sox soc2 iso27001 nist commercial none)

# Values for compliance.signing.method (PRD §11.6).
YCI_SIGNING_METHODS=(minisign ssh-keygen-y-sign)

# Values for safety.default_posture (schema.md "Safety postures" / PRD §11.7).
YCI_SAFETY_POSTURES=(dry-run review apply)

# Values for engagement.type (schema.md "Engagement types" / PRD §5.2).
YCI_ENGAGEMENT_TYPES=(discovery design implementation ongoing)

# Values for safety.scope_enforcement (schema.md "Scope enforcement values").
YCI_SCOPE_ENFORCEMENT=(warn block off)

# Values for deliverable.handoff_format (schema.md "deliverable" table).
YCI_DELIVERABLE_HANDOFF_FORMATS=(git-repo zip confluence pdf-bundle)

# Values for change_window.adapter (schema.md "change_window" table).
# Only validated when change_window is present (the whole block is optional).
YCI_CHANGE_WINDOW_ADAPTERS=(ical servicenow-cab json-schedule always-open none)

# Inventory/approval adapter types: schema.md lists common adapters but the
# loader validates the field as a non-empty string, not a closed enum — new
# adapters are added without schema changes. See schema.md "Adapter note"
# under inventory and approval.
