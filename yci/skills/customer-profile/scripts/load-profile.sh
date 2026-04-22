#!/usr/bin/env bash
# yci — load and validate a customer profile YAML, emitting normalized JSON.
#
# Usage: load-profile.sh <data-root> <customer>
# Stdout: indented JSON of the parsed profile on success.
# Stderr: error messages only.
# Exit 0: success.
# Exit 1: profile file not found (loader-missing-file).
# Exit 2: schema violation — malformed YAML, missing required key, invalid enum.
# Exit 3: runtime error — pyyaml not installed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/profile-schema.sh"

data_root="${1:?usage: load-profile.sh <data-root> <customer>}"
customer="${2:?usage: load-profile.sh <data-root> <customer>}"
profile_path="${data_root}/profiles/${customer}.yaml"

# --- loader-missing-file (exit 1) -------------------------------------------
if [ ! -f "$profile_path" ]; then
    printf 'yci: profile not found: %s\n' "$profile_path" >&2
    printf '  create a new profile with `/yci:init %s` or copy _template.yaml\n' "$customer" >&2
    exit 1
fi

# --- Export schema arrays as space-separated env vars for Python -------------
export YCI_REQUIRED_TOP_LEVEL="${YCI_PROFILE_REQUIRED_TOP_LEVEL[*]}"
export YCI_OPTIONAL_TOP_LEVEL="${YCI_PROFILE_OPTIONAL_TOP_LEVEL[*]}"
export YCI_CUSTOMER_REQ="${YCI_CUSTOMER_REQUIRED[*]}"
export YCI_ENGAGEMENT_REQ="${YCI_ENGAGEMENT_REQUIRED[*]}"
export YCI_COMPLIANCE_REQ="${YCI_COMPLIANCE_REQUIRED[*]}"
export YCI_INVENTORY_REQ="${YCI_INVENTORY_REQUIRED[*]}"
export YCI_APPROVAL_REQ="${YCI_APPROVAL_REQUIRED[*]}"
export YCI_DELIVERABLE_REQ="${YCI_DELIVERABLE_REQUIRED[*]}"
export YCI_SAFETY_REQ="${YCI_SAFETY_REQUIRED[*]}"
export YCI_COMPLIANCE_REGIMES_ENV="${YCI_COMPLIANCE_REGIMES[*]}"
export YCI_SAFETY_POSTURES_ENV="${YCI_SAFETY_POSTURES[*]}"
export YCI_ENGAGEMENT_TYPES_ENV="${YCI_ENGAGEMENT_TYPES[*]}"
export YCI_SCOPE_ENFORCEMENT_ENV="${YCI_SCOPE_ENFORCEMENT[*]}"
export YCI_HANDOFF_FORMATS_ENV="${YCI_DELIVERABLE_HANDOFF_FORMATS[*]}"
export YCI_CHANGE_WINDOW_ADAPTERS_ENV="${YCI_CHANGE_WINDOW_ADAPTERS[*]}"
export YCI_SIGNING_METHODS_ENV="${YCI_SIGNING_METHODS[*]}"

python3 - "$profile_path" <<'PY'
import json, os, sys

# --- pyyaml check (loader-pyyaml-missing, exit 3) ---------------------------
try:
    import yaml
except ModuleNotFoundError:
    sys.stderr.write(
        "yci: pyyaml not found — cannot parse YAML profiles\n"
        "  pyyaml required — install via 'pip install pyyaml' or your distro's python3-yaml package\n"
    )
    sys.exit(3)

path = sys.argv[1]

# --- parse (loader-malformed-yaml, exit 2) ----------------------------------
try:
    with open(path) as fh:
        data = yaml.safe_load(fh)
except yaml.YAMLError as exc:
    first_line = str(exc).splitlines()[0] if str(exc) else str(exc)
    sys.stderr.write(f"yci: malformed YAML in profile: {path}\n  {first_line}\nFix the YAML syntax and retry.\n")
    sys.exit(2)

if not isinstance(data, dict):
    sys.stderr.write(
        f"yci: malformed YAML in profile: {path}\n"
        f"  profile must be a YAML mapping at top level\n"
        "Fix the YAML syntax and retry.\n"
    )
    sys.exit(2)

# --- required top-level keys (loader-missing-required-key, exit 2) ----------
req_top = os.environ["YCI_REQUIRED_TOP_LEVEL"].split()
opt_top = os.environ["YCI_OPTIONAL_TOP_LEVEL"].split()

for key in req_top:
    if key not in data:
        sys.stderr.write(
            f"yci: missing required field '{key}' in profile: {path}\n"
            "  see yci/skills/customer-profile/references/schema.md for required fields\n"
        )
        sys.exit(2)

# --- nested required fields (loader-missing-required-key, exit 2) -----------
nested_req = {
    "customer":    os.environ["YCI_CUSTOMER_REQ"].split(),
    "engagement":  os.environ["YCI_ENGAGEMENT_REQ"].split(),
    "compliance":  os.environ["YCI_COMPLIANCE_REQ"].split(),
    "inventory":   os.environ["YCI_INVENTORY_REQ"].split(),
    "approval":    os.environ["YCI_APPROVAL_REQ"].split(),
    "deliverable": os.environ["YCI_DELIVERABLE_REQ"].split(),
    "safety":      os.environ["YCI_SAFETY_REQ"].split(),
}
for section, fields in nested_req.items():
    section_data = data.get(section)
    if not isinstance(section_data, dict):
        sys.stderr.write(
            f"yci: missing required field '{section}' in profile: {path}\n"
            "  see yci/skills/customer-profile/references/schema.md for required fields\n"
        )
        sys.exit(2)
    for field in fields:
        if field not in section_data:
            sys.stderr.write(
                f"yci: missing required field '{section}.{field}' in profile: {path}\n"
                "  see yci/skills/customer-profile/references/schema.md for required fields\n"
            )
            sys.exit(2)

# --- enum validation (loader-invalid-enum-value, exit 2) --------------------
enums = {
    ("compliance", "regime"):           set(os.environ["YCI_COMPLIANCE_REGIMES_ENV"].split()),
    ("safety",     "default_posture"):  set(os.environ["YCI_SAFETY_POSTURES_ENV"].split()),
    ("engagement", "type"):             set(os.environ["YCI_ENGAGEMENT_TYPES_ENV"].split()),
    ("safety",     "scope_enforcement"): set(os.environ["YCI_SCOPE_ENFORCEMENT_ENV"].split()),
    ("deliverable", "handoff_format"):   set(os.environ["YCI_HANDOFF_FORMATS_ENV"].split()),
}
for (sec, field), allowed in enums.items():
    val = data.get(sec, {}).get(field)
    if val is None:
        continue  # nested-required check already caught absent field above
    if str(val) not in allowed:
        sys.stderr.write(
            f"yci: invalid value for '{sec}.{field}': '{val}'\n"
            f"  allowed values: {sorted(allowed)}\n"
            "  see yci/skills/customer-profile/references/schema.md for the canonical enum lists\n"
        )
        sys.exit(2)

# --- optional-section enum validation ---------------------------------------
# change_window is optional at the top level; only validate its adapter when
# the block is present.
cw = data.get("change_window")
if isinstance(cw, dict):
    cw_allowed = set(os.environ["YCI_CHANGE_WINDOW_ADAPTERS_ENV"].split())
    cw_adapter = cw.get("adapter")
    if cw_adapter is not None and str(cw_adapter) not in cw_allowed:
        sys.stderr.write(
            f"yci: invalid value for 'change_window.adapter': '{cw_adapter}'\n"
            f"  allowed values: {sorted(cw_allowed)}\n"
            "  see yci/skills/customer-profile/references/schema.md for the canonical enum lists\n"
        )
        sys.exit(2)

# compliance.signing is optional. When present it must be a mapping with a
# valid signing method and non-empty key_ref. ssh-keygen-y-sign additionally
# requires an identity value to map onto -I.
signing = data.get("compliance", {}).get("signing")
if signing is not None:
    if not isinstance(signing, dict):
        sys.stderr.write(
            "yci: invalid value for 'compliance.signing': expected a mapping\n"
            "  see yci/skills/customer-profile/references/schema.md for the signing schema\n"
        )
        sys.exit(2)

    method = signing.get("method")
    allowed_methods = set(os.environ["YCI_SIGNING_METHODS_ENV"].split())
    if method is None or str(method) not in allowed_methods:
        sys.stderr.write(
            f"yci: invalid value for 'compliance.signing.method': '{method}'\n"
            f"  allowed values: {sorted(allowed_methods)}\n"
            "  see yci/skills/customer-profile/references/schema.md for the canonical enum lists\n"
        )
        sys.exit(2)

    key_ref = signing.get("key_ref")
    if not isinstance(key_ref, str) or not key_ref.strip():
        sys.stderr.write(
            "yci: missing required field 'compliance.signing.key_ref' in profile: "
            f"{path}\n"
            "  see yci/skills/customer-profile/references/schema.md for required fields\n"
        )
        sys.exit(2)

    if method == "ssh-keygen-y-sign":
        identity = signing.get("identity")
        if not isinstance(identity, str) or not identity.strip():
            sys.stderr.write(
                "yci: missing required field 'compliance.signing.identity' in profile: "
                f"{path}\n"
                "  ssh-keygen-y-sign requires an identity value for signature verification\n"
            )
            sys.exit(2)

# --- unknown top-level key warning (stderr, not error) ----------------------
allowed_top = set(req_top) | set(opt_top)
for key in data:
    if key not in allowed_top:
        sys.stderr.write(f"yci: warning — unknown top-level key: {key}\n")

# --- success: emit JSON ------------------------------------------------------
print(json.dumps(data, indent=2, sort_keys=False, default=str))
PY
