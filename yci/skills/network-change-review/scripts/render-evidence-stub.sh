#!/usr/bin/env bash
# render-evidence-stub.sh — yci:network-change-review evidence stub emitter.
#
# Produces a YAML frontmatter block (per evidence-stub-schema.md) that satisfies
# PRD §6.1 P0.4 and is forward-compatible with commercial/evidence-schema.json v1.
#
# Usage:
#   render-evidence-stub.sh \
#     --profile <path>                 \  # profile JSON (load-profile.sh output)
#     --change <path>                  \  # normalized change JSON (parse-change.sh output)
#     --blast-radius-label <path>      \  # blast-radius label JSON
#     --rollback-confidence <level>    \  # high|medium|low
#     --rollback-plan-path <rel-path>  \  # relative path within artifact dir
#     [--output <path>]                   # write to file (default: stdout)
#
# Stdout or --output: YAML frontmatter block (--- ... ---).
# Stderr: errors only, in [ncr-<id>] format.
# Exit codes:
#   0  success
#   1  usage / missing flag
#   2  profile load failed / customer mismatch
#   3  invalid input shape

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
    cat >&2 <<'EOF'
Usage: render-evidence-stub.sh [OPTIONS]

Options:
  --profile <path>                Profile JSON (load-profile.sh output)       [required]
  --change <path>                 Normalized change JSON (parse-change.sh)    [required]
  --blast-radius-label <path>     Blast-radius label JSON                     [required]
  --rollback-confidence <level>   high|medium|low                             [required]
  --rollback-plan-path <rel-path> Relative path within artifact directory     [required]
  --output <path>                 Write to file instead of stdout             [optional]
  -h, --help                      Show this help message
EOF
    exit 1
}

err() {
    local id="$1"
    local msg="$2"
    local code="${3:-1}"
    printf '[%s] %s\n' "${id}" "${msg}" >&2
    exit "${code}"
}

# ---------------------------------------------------------------------------
# Flag parsing
# ---------------------------------------------------------------------------

profile_path=""
change_path=""
label_path=""
rollback_confidence=""
rollback_plan_path=""
output_path=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)              profile_path="$2";        shift 2 ;;
        --change)               change_path="$2";         shift 2 ;;
        --blast-radius-label)   label_path="$2";          shift 2 ;;
        --rollback-confidence)  rollback_confidence="$2"; shift 2 ;;
        --rollback-plan-path)   rollback_plan_path="$2";  shift 2 ;;
        --output)               output_path="$2";         shift 2 ;;
        -h|--help)              usage ;;
        *) printf 'Unknown flag: %s\n' "$1" >&2; usage ;;
    esac
done

# ---------------------------------------------------------------------------
# Validation guards
# ---------------------------------------------------------------------------

[[ -n "${profile_path}"        ]] || err "ncr-profile-load-failed"      "Missing required flag: --profile"              1
[[ -n "${change_path}"         ]] || err "ncr-diff-unsupported-shape"   "Missing required flag: --change"               1
[[ -n "${label_path}"          ]] || err "ncr-blast-radius-failed"      "Missing required flag: --blast-radius-label"   1
[[ -n "${rollback_confidence}" ]] || err "ncr-rollback-ambiguous"       "Missing required flag: --rollback-confidence"  1
[[ -n "${rollback_plan_path}"  ]] || err "ncr-rollback-missing-reverse" "Missing required flag: --rollback-plan-path"   1

[[ -f "${profile_path}"        ]] || err "ncr-profile-load-failed"      "Profile not found: ${profile_path}"            2
[[ -f "${change_path}"         ]] || err "ncr-diff-unsupported-shape"   "Change file not found: ${change_path}"         3
[[ -f "${label_path}"          ]] || err "ncr-blast-radius-failed"      "Blast-radius label not found: ${label_path}"   5

case "${rollback_confidence}" in
    high|medium|low) ;;
    *) err "ncr-rollback-ambiguous" "Invalid --rollback-confidence: ${rollback_confidence} (must be high|medium|low)" 1 ;;
esac

# ---------------------------------------------------------------------------
# Build the stub via inline Python
# ---------------------------------------------------------------------------

# Export profile path so the Python block can resolve profile_commit.
export NCR_PROFILE_PATH="${profile_path}"

stub="$(python3 <<PYEOF
import json, sys, os, subprocess, hashlib
from datetime import datetime, timezone

try:
    profile = json.load(open("${profile_path}"))
except Exception as e:
    sys.stderr.write("[ncr-profile-load-failed] Could not parse profile: {}\n".format(e))
    sys.exit(2)

try:
    change = json.load(open("${change_path}"))
except Exception as e:
    sys.stderr.write("[ncr-diff-unsupported-shape] Could not parse change JSON: {}\n".format(e))
    sys.exit(3)

try:
    label = json.load(open("${label_path}"))
except Exception as e:
    sys.stderr.write("[ncr-blast-radius-failed] Could not parse blast-radius label: {}\n".format(e))
    sys.exit(5)

# Derive change_id: sha256(raw)[:8] + '-' + utc yyyymmdd-hhmm
raw = change.get("raw", "")
cid = hashlib.sha256(raw.encode()).hexdigest()[:8]
ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M")
change_id = "{}-{}".format(cid, ts)
timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# yci_commit: run git rev-parse inside CLAUDE_PLUGIN_ROOT
try:
    yci_commit = subprocess.run(
        ["git", "-C", os.environ.get("CLAUDE_PLUGIN_ROOT", "."), "rev-parse", "HEAD"],
        capture_output=True, text=True, check=True
    ).stdout.strip()
except Exception:
    yci_commit = "unknown"

# profile_commit: best-effort from the directory containing the profile file.
# Profiles often live outside the plugin repo (e.g. ~/.yci/profiles/); git
# versioning is optional, so failure here is silent.
profile_commit = "unknown"
try:
    profile_path = os.environ.get("NCR_PROFILE_PATH", "")
    if profile_path:
        profile_dir = os.path.dirname(os.path.abspath(profile_path))
        result = subprocess.run(
            ["git", "-C", profile_dir, "rev-parse", "HEAD"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0 and result.stdout.strip():
            profile_commit = result.stdout.strip()
except Exception:
    pass  # fall back to "unknown" silently

# Resolve compliance regime and schema_version.
compliance_regime = profile.get("compliance", {}).get("regime", "")
if compliance_regime == "commercial":
    schema_version = "commercial/1"
elif compliance_regime == "none":
    schema_version = "none"
else:
    schema_version = "commercial/1"

# Normalize blast_radius_label — fail-safe to "high" for unknown values.
blast_radius_raw = label.get("label", label.get("impact_level", ""))
allowed_labels = {"low", "medium", "high"}
blast_radius_label = blast_radius_raw if blast_radius_raw in allowed_labels else "high"

out = {
    "schema_version": schema_version,
    "change_id": change_id,
    "change_summary": change.get("summary", ""),
    "customer_id": profile.get("customer", {}).get("id", ""),
    "profile_commit": profile_commit,
    "yci_commit": yci_commit,
    "timestamp_utc": timestamp,
    "approver": "_pending_",
    "compliance_regime": compliance_regime,
    "rollback_plan_path": "${rollback_plan_path}",
    "pre_check_artifacts": [],
    "post_check_artifacts": [],
    "blast_radius_label": blast_radius_label,
    "rollback_confidence": "${rollback_confidence}",
}

import yaml
print("---")
print(yaml.safe_dump(out, sort_keys=False).rstrip())
print("---")
PYEOF
)"

# ---------------------------------------------------------------------------
# Write to --output or stdout
# ---------------------------------------------------------------------------

if [[ -n "${output_path}" ]]; then
    mkdir -p "$(dirname "${output_path}")"
    printf '%s\n' "${stub}" > "${output_path}"
else
    printf '%s\n' "${stub}"
fi
