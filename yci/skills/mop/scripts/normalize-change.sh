#!/usr/bin/env bash
# normalize-change.sh — normalize supported yci:mop inputs to canonical JSON.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: normalize-change.sh --input <path> [--output <path>]
EOF
}

err() {
  local id="$1"
  local msg="$2"
  local code="${3:-3}"
  printf '[%s] %s\n' "$id" "$msg" >&2
  exit "$code"
}

input_path=""
output_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)  input_path="${2:?--input requires a path}"; shift 2 ;;
    --output) output_path="${2:?--output requires a path}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; err "mop-change-unsupported" "Unknown flag: $1" 3 ;;
  esac
done

[[ -n "$input_path" ]] || err "mop-change-missing" "--input is required" 3
[[ -f "$input_path" ]] || err "mop-change-missing" "Input file not found: ${input_path}" 3
[[ -r "$input_path" ]] || err "mop-change-missing" "Input file not readable: ${input_path}" 3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd -P)}"

python3 - "$input_path" "$PLUGIN_ROOT" <<'PYEOF' > "${output_path:-/dev/stdout}"
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

path = Path(sys.argv[1]).resolve()
plugin_root = Path(sys.argv[2])
raw = path.read_text(encoding="utf-8")
ext = path.suffix.lower()

def stable_change_id(text: str) -> str:
    return f"mop-{hashlib.sha256(text.encode('utf-8')).hexdigest()[:10]}"

def render_shell_block(lines):
    body = "\n".join(lines).rstrip()
    return f"```sh\n{body}\n```"

def render_text_block(text):
    body = text.rstrip("\n")
    return f"```text\n{body}\n```"

def normalize_targets(items):
    out = []
    for item in items or []:
        if not isinstance(item, dict):
            continue
        kind = str(item.get("kind", "")).strip()
        ident = str(item.get("id", "")).strip()
        if kind and ident:
            out.append({"kind": kind, "id": ident})
    return out

def build_from_parse_change():
    cmd = [
        "bash",
        str(plugin_root / "skills/network-change-review/scripts/parse-change.sh"),
        "--input",
        str(path),
    ]
    parsed = json.loads(subprocess.check_output(cmd, text=True))
    parsed["change_id"] = parsed.get("change_id") or stable_change_id(raw)
    return parsed

def detect_vendor_cli(text: str):
    vendor = ""
    summary = ""
    change_id = ""
    targets = []
    body = []
    body_started = False
    for line in text.splitlines():
        if not body_started and line.startswith("#"):
            header = line[1:].strip()
            if header.startswith("vendor:"):
                vendor = header.split(":", 1)[1].strip().lower()
            elif header.startswith("summary:"):
                summary = header.split(":", 1)[1].strip()
            elif header.startswith("change_id:"):
                change_id = header.split(":", 1)[1].strip()
            elif header.startswith("target:"):
                target = header.split(":", 1)[1].strip()
                if "=" in target:
                    kind, ident = target.split("=", 1)
                    targets.append({"kind": kind.strip(), "id": ident.strip()})
            continue
        body_started = True
        body.append(line)
    if not vendor:
        return None
    if vendor not in {"iosxe", "panos"}:
        raise ValueError(f"[mop-vendor-unsupported] Unsupported vendor CLI type: {vendor}")
    commands = "\n".join(body).strip()
    if not commands:
        raise ValueError("[mop-change-malformed] Vendor CLI body is empty.")
    return {
        "diff_kind": "vendor-cli",
        "raw": commands,
        "summary": summary or f"Vendor CLI change for {vendor}",
        "targets": targets,
        "change_id": change_id or stable_change_id(commands),
        "metadata": {"vendor": vendor, "artifact_input_filename": f"reviewed-input-{vendor}-cli"},
        "apply_markdown": render_text_block(commands),
        "pre_change_markdown": render_shell_block([
            "# Capture the current device state before applying the reviewed CLI.",
            "show running-config",
            "show configuration diff",
        ]) if vendor == "iosxe" else render_shell_block([
            "# Capture the current running config before applying the reviewed CLI.",
            "show config running",
            "show jobs all",
        ]),
        "post_change_markdown": render_shell_block([
            "# Re-run the validated post-change checks after commit.",
            "show running-config",
            "show interface status",
        ]) if vendor == "iosxe" else render_shell_block([
            "# Re-run the validated post-change checks after commit.",
            "show config running",
            "show jobs all",
        ]),
    }

def detect_terraform_plan(text: str):
    try:
        doc = json.loads(text)
    except Exception:
        return None
    if not isinstance(doc, dict):
        return None
    if "format_version" not in doc or "resource_changes" not in doc:
        return None
    resource_changes = doc.get("resource_changes") or []
    addresses = [rc.get("address", "unknown") for rc in resource_changes if isinstance(rc, dict)]
    first = addresses[0] if addresses else "no-addresses"
    extra = f", +{len(addresses)-1} more" if len(addresses) > 1 else ""
    summary = f"Terraform plan touching {len(addresses)} resource(s): {first}{extra}"
    return {
        "diff_kind": "terraform-plan",
        "raw": text,
        "summary": summary,
        "targets": [],
        "change_id": stable_change_id(text),
        "metadata": {"addresses": addresses, "artifact_input_filename": "reviewed-input-plan-json"},
        "apply_markdown": render_shell_block([
            "# Recreate the reviewed plan from the same workspace before apply.",
            "terraform plan -out tfplan",
            "terraform show -json tfplan > regenerated-plan-json",
            "cmp -s reviewed-input-plan-json regenerated-plan-json",
            "terraform apply tfplan",
        ]),
        "pre_change_markdown": render_shell_block([
            "terraform state pull > pre-change-tfstate",
            "terraform state list",
        ]),
        "post_change_markdown": render_shell_block([
            "terraform state list",
            "terraform plan -detailed-exitcode",
        ]),
    }

def detect_structured_yaml(text: str):
    if ext not in {".yaml", ".yml"}:
        return None
    try:
        import yaml
        data = yaml.safe_load(text)
    except Exception:
        return None
    if not isinstance(data, dict) or "forward" not in data:
        return None
    parsed = build_from_parse_change()
    parsed["change_id"] = str(data.get("change_id") or parsed.get("change_id") or stable_change_id(text))
    parsed["summary"] = str(data.get("summary") or parsed.get("summary") or "Structured YAML change")
    targets = normalize_targets(data.get("targets"))
    if targets:
        parsed["targets"] = targets
    parsed["metadata"] = {"artifact_input_filename": "reviewed-input-structured-yaml"}

    apply_chunks = []
    for step in data.get("forward") or []:
        if not isinstance(step, dict):
            continue
        label = step.get("device") or step.get("service") or step.get("tenant") or "target"
        cli = str(step.get("cli") or step.get("command") or "").rstrip()
        if cli:
            apply_chunks.append(f"### {label}\n\n```text\n{cli}\n```")
    parsed["apply_markdown"] = "\n\n".join(apply_chunks) if apply_chunks else render_text_block(parsed["raw"])
    parsed["pre_change_markdown"] = render_shell_block([
        "# Capture the current state for every listed target before apply.",
        "show running-config",
        "show interface status",
    ])
    parsed["post_change_markdown"] = render_shell_block([
        "# Re-run the validated post-change checks for every listed target.",
        "show running-config",
        "show interface status",
    ])
    return parsed

def detect_unified_diff(text: str):
    if not re.search(r"^--- a/", text, re.MULTILINE) or not re.search(r"^\+\+\+ b/", text, re.MULTILINE):
        return None
    parsed = build_from_parse_change()
    parsed["change_id"] = stable_change_id(text)
    parsed["metadata"] = {"artifact_input_filename": "reviewed-input-patch"}
    parsed["apply_markdown"] = render_shell_block([
        "git apply --check 'reviewed-input-patch'",
        "git apply 'reviewed-input-patch'",
    ])
    parsed["pre_change_markdown"] = render_shell_block([
        "git status --short",
        "git apply --check 'reviewed-input-patch'",
    ])
    parsed["post_change_markdown"] = render_shell_block([
        "git status --short",
        "git diff --stat",
    ])
    return parsed

vendor_doc = detect_vendor_cli(raw)
terraform_doc = detect_terraform_plan(raw)
structured_doc = detect_structured_yaml(raw)
unified_doc = detect_unified_diff(raw)

if vendor_doc is not None:
    out = vendor_doc
elif terraform_doc is not None:
    out = terraform_doc
elif structured_doc is not None:
    out = structured_doc
elif unified_doc is not None:
    out = unified_doc
else:
    raise SystemExit("[mop-change-unsupported] Unsupported change shape. Supported: unified-diff, structured-yaml, terraform-plan JSON, vendor CLI.")

print(json.dumps(out, indent=2))
PYEOF
