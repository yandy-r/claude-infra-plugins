#!/usr/bin/env bash
# yci — build pre-check and post-check catalogs for a network change review.
#
# Reads a resolved compliance adapter directory and a blast-radius label JSON
# file, then emits a JSON object containing pre_check and post_check arrays.
#
# Usage:
#   build-check-catalogs.sh --adapter-dir <path> --blast-radius-label <path> \
#                           [--output <path>]
#
# Flags:
#   --adapter-dir <path>        Resolved compliance adapter directory (required).
#                               Must contain handoff-checklist.md.
#   --blast-radius-label <path> Blast-radius label JSON file (required).
#                               Must match label-schema.json (keys: direct_devices,
#                               services, dependencies, etc.).
#   --output <path>             Write JSON to <path> instead of stdout.
#   -h, --help                  Print this message and exit 0.
#
# Stdout: JSON object — { "pre_check": [...], "post_check": [...] }
# Stderr: errors only, format: [ncr-<id>] <message>
#
# Error IDs (see references/error-messages.md):
#   ncr-adapter-unresolvable  — adapter dir missing or unreadable   (exit 2)
#   ncr-blast-radius-failed   — label file missing or unreadable    (exit 5)
#
# See also: references/composition-contract.md (step 12)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export NCR_CATALOG_SCRIPT_DIR="$SCRIPT_DIR"

# ---------------------------------------------------------------------------
# err <id> <message> <exit-code>
# Write a structured error to stderr then exit.
# ---------------------------------------------------------------------------
err() {
    local id="$1" msg="$2" code="$3"
    printf '[ncr-%s] %s\n' "$id" "$msg" >&2
    exit "$code"
}

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
    printf 'Usage: build-check-catalogs.sh --adapter-dir <path> --blast-radius-label <path> [--output <path>]\n' >&2
    printf '\n' >&2
    printf 'Options:\n' >&2
    printf '  --adapter-dir <path>        Resolved compliance adapter directory (required)\n' >&2
    printf '  --blast-radius-label <path> Blast-radius label JSON file (required)\n' >&2
    printf '  --output <path>             Write output to file instead of stdout\n' >&2
    printf '  -h, --help                  Show this help\n' >&2
}

# ---------------------------------------------------------------------------
# Flag parsing
# ---------------------------------------------------------------------------
adapter_dir=""
label_path=""
output_path=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --adapter-dir)
            [ -z "${2:-}" ] && { usage; err "adapter-unresolvable" "--adapter-dir requires a value" 2; }
            adapter_dir="$2"; shift 2 ;;
        --adapter-dir=*)
            adapter_dir="${1#*=}"; shift ;;
        --blast-radius-label)
            [ -z "${2:-}" ] && { usage; err "blast-radius-failed" "--blast-radius-label requires a value" 5; }
            label_path="$2"; shift 2 ;;
        --blast-radius-label=*)
            label_path="${1#*=}"; shift ;;
        --output)
            [ -z "${2:-}" ] && { usage; err "adapter-unresolvable" "--output requires a value" 2; }
            output_path="$2"; shift 2 ;;
        --output=*)
            output_path="${1#*=}"; shift ;;
        -h|--help)
            usage; exit 0 ;;
        --)
            shift; break ;;
        -*)
            usage
            err "adapter-unresolvable" "Unknown flag: $1" 2 ;;
        *)
            usage
            err "adapter-unresolvable" "Unexpected argument: $1" 2 ;;
    esac
done

# ---------------------------------------------------------------------------
# Validation guards
# ---------------------------------------------------------------------------
[ -z "$adapter_dir" ] && { usage; err "adapter-unresolvable" "Missing required flag: --adapter-dir" 2; }
[ -z "$label_path"  ] && { usage; err "blast-radius-failed"  "Missing required flag: --blast-radius-label" 5; }

[ -d "$adapter_dir" ] \
    || err "adapter-unresolvable" "Adapter dir not found: $adapter_dir" 2

[ -f "$label_path" ] && [ -r "$label_path" ] \
    || err "blast-radius-failed" "Blast-radius label not found: $label_path" 5

# ---------------------------------------------------------------------------
# derive_adapter_checks
# Returns a JSON array of pre-check objects:
#   - adapter-sourced pre-checks from handoff-checklist.md
#   - blast-radius device pre-checks (confirm reachability BEFORE the change)
# The caller (main) assigns this to pre_check.
# ---------------------------------------------------------------------------
derive_adapter_checks() {
    export NCR_ADAPTER_DIR="$adapter_dir"
    export NCR_LABEL_PATH="$label_path"
    python3 - <<'PYEOF'
import json, os, re, sys

sys.path.insert(0, os.environ["NCR_CATALOG_SCRIPT_DIR"])
from catalog_classify import classify

adapter_dir = os.environ["NCR_ADAPTER_DIR"]
label_path = os.environ["NCR_LABEL_PATH"]

pre_checks = []

# --- adapter checklist -------------------------------------------------
checklist_path = os.path.join(adapter_dir, "handoff-checklist.md")
if not os.path.exists(checklist_path):
    sys.stderr.write(
        f"[ncr-adapter-unresolvable] handoff-checklist.md missing (required): {checklist_path}\n"
    )
    sys.exit(1)
with open(checklist_path) as fh:
    text = fh.read()

entries = re.findall(r"^\s*-\s*\[[ xX]\]\s*(.+)", text, flags=re.MULTILINE)

for idx, desc in enumerate(entries):
    desc = desc.strip()
    slug = re.sub(r"[^a-z0-9]+", "-", desc.lower())[:48].strip("-") or f"adapter-{idx}"
    check_id = f"adapter-{slug}"
    if classify(desc) == "pre":
        pre_checks.append({
            "id": check_id,
            "category": "adapter",
            "source": "adapter",
            "description": desc,
            "applies_to": "all",
        })

# --- blast-radius device pre-checks ------------------------------------
try:
    with open(label_path) as fh:
        label = json.load(fh)
except Exception as exc:
    sys.stderr.write(
        f"[ncr-blast-radius-failed] could not parse blast-radius label JSON: {label_path}: {exc}\n"
    )
    sys.exit(1)

for dev in label.get("direct_devices", []):
    dev_id = dev.get("id") or "unknown"
    slug = re.sub(r"[^a-z0-9]+", "-", dev_id.lower())[:40]
    pre_checks.append({
        "id": f"br-pre-reach-{slug}",
        "category": "reachability",
        "source": "blast-radius",
        "description": (
            f"Confirm device {dev_id} is reachable (ping + management plane) "
            "immediately before change."
        ),
        "applies_to": dev_id,
    })

print(json.dumps(pre_checks, indent=2))
PYEOF
}

# ---------------------------------------------------------------------------
# derive_blast_radius_checks
# Returns a JSON array of post-check objects:
#   - blast-radius device post-checks (reachability after change)
#   - service SLO post-checks
#   - dependency link-health post-checks
#   - adapter-sourced post-checks from handoff-checklist.md
# The caller (main) assigns this to post_check.
# ---------------------------------------------------------------------------
derive_blast_radius_checks() {
    export NCR_ADAPTER_DIR="$adapter_dir"
    export NCR_LABEL_PATH="$label_path"
    python3 - <<'PYEOF'
import json, os, re, sys

sys.path.insert(0, os.environ["NCR_CATALOG_SCRIPT_DIR"])
from catalog_classify import classify

adapter_dir = os.environ["NCR_ADAPTER_DIR"]
label_path = os.environ["NCR_LABEL_PATH"]

post_checks = []

checklist_path = os.path.join(adapter_dir, "handoff-checklist.md")
if not os.path.exists(checklist_path):
    sys.stderr.write(
        f"[ncr-adapter-unresolvable] handoff-checklist.md missing (required): {checklist_path}\n"
    )
    sys.exit(1)

# --- blast-radius label checks -----------------------------------------
try:
    with open(label_path) as fh:
        label = json.load(fh)
except Exception as exc:
    sys.stderr.write(
        f"[ncr-blast-radius-failed] could not parse blast-radius label JSON: {label_path}: {exc}\n"
    )
    sys.exit(1)

for dev in label.get("direct_devices", []):
    dev_id = dev.get("id") or "unknown"
    slug = re.sub(r"[^a-z0-9]+", "-", dev_id.lower())[:40]
    post_checks.append({
        "id": f"br-post-reach-{slug}",
        "category": "reachability",
        "source": "blast-radius",
        "description": f"Confirm device {dev_id} is reachable after change.",
        "applies_to": dev_id,
    })

for svc in label.get("services", []):
    svc_id = svc.get("id") or "unknown"
    rto = svc.get("rto_band", "n/a")
    slug = re.sub(r"[^a-z0-9]+", "-", svc_id.lower())[:40]
    post_checks.append({
        "id": f"br-post-slo-{slug}",
        "category": "slo",
        "source": "blast-radius",
        "description": (
            f"Confirm service {svc_id} SLO (rto_band={rto}) holds "
            "for 10 minutes post-change."
        ),
        "applies_to": svc_id,
    })

for dep in label.get("dependencies", []):
    dep_from = dep.get("from", "?")
    dep_to   = dep.get("to",   "?")
    dep_desc = f"{dep_from} -> {dep_to}"
    dep_id   = re.sub(r"[^a-z0-9]+", "-", dep_desc.lower())[:40]
    dep_type = dep.get("type", "?")
    post_checks.append({
        "id": f"br-post-link-{dep_id}",
        "category": "link-health",
        "source": "blast-radius",
        "description": f"Confirm dependency edge {dep_desc} (type={dep_type}) is healthy post-change.",
        "applies_to": dep_desc,
    })

# --- adapter post-checks -----------------------------------------------
with open(checklist_path) as fh:
    text = fh.read()

entries = re.findall(r"^\s*-\s*\[[ xX]\]\s*(.+)", text, flags=re.MULTILINE)

for idx, desc in enumerate(entries):
    desc = desc.strip()
    slug = re.sub(r"[^a-z0-9]+", "-", desc.lower())[:48].strip("-") or f"adapter-{idx}"
    check_id = f"adapter-{slug}"
    if classify(desc) == "post":
        post_checks.append({
            "id": check_id,
            "category": "adapter",
            "source": "adapter",
            "description": desc,
            "applies_to": "all",
        })

print(json.dumps(post_checks, indent=2))
PYEOF
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    local pre_checks_json post_checks_json

    pre_checks_json="$(derive_adapter_checks)"
    post_checks_json="$(derive_blast_radius_checks)"

    local result
    result="$(python3 -c '
import json, sys
out = {"pre_check": '"$pre_checks_json"', "post_check": '"$post_checks_json"'}
print(json.dumps(out, indent=2))
')"

    if [ -n "$output_path" ]; then
        printf '%s\n' "$result" > "$output_path"
    else
        printf '%s\n' "$result"
    fi
}

main
