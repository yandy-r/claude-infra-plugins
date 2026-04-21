#!/usr/bin/env bash
# yci — blast-radius markdown renderer. Reads a blast-radius label JSON on
# stdin and emits a human-readable markdown narrative on stdout.
# Regime-aware addendum is gated by the YCI_ACTIVE_REGIME env var; when unset
# or empty, the addendum is omitted.
#
# Usage: render-markdown.sh < label.json
# Stdout: markdown narrative.
# Stderr: error messages only.
# Exit:
#   0 success
#   1 malformed stdin
#   2 unsupported schema_version
#   3 runtime error

set -euo pipefail

if [ -t 0 ]; then
    printf 'usage: render-markdown.sh < label.json\n' >&2
    printf '  render-missing-stdin\n' >&2
    exit 1
fi

_YCI_RENDER_INPUT="$(cat)"
if [ -z "${_YCI_RENDER_INPUT}" ]; then
    printf 'yci: render-markdown.sh stdin empty\n' >&2
    printf '  render-missing-stdin\n' >&2
    exit 1
fi
export _YCI_RENDER_INPUT

python3 - <<'PY'
import json
import os
import sys

EM_DASH = "—"


def die(code, msg):
    sys.stderr.write(msg if msg.endswith("\n") else msg + "\n")
    sys.exit(code)


raw = os.environ.get("_YCI_RENDER_INPUT", "")
try:
    label = json.loads(raw)
except json.JSONDecodeError as exc:
    die(1, f"yci: render-markdown.sh stdin is not valid JSON\n  render-missing-stdin: {exc}")

ver = label.get("schema_version")
if ver != 1:
    die(2, f"yci: unsupported label schema version: {ver} (expected 1)\n  render-unsupported-version")


def cell(value):
    if value is None or value == "":
        return EM_DASH
    return str(value)


def render_table(headers, rows):
    if not rows:
        return "_None._\n"
    col_widths = [len(h) for h in headers]
    rendered_rows = []
    for row in rows:
        cells = [cell(c) for c in row]
        for i, c in enumerate(cells):
            if len(c) > col_widths[i]:
                col_widths[i] = len(c)
        rendered_rows.append(cells)
    head = "| " + " | ".join(h.ljust(col_widths[i]) for i, h in enumerate(headers)) + " |"
    sep = "| " + " | ".join("-" * col_widths[i] for i in range(len(headers))) + " |"
    body = "\n".join(
        "| " + " | ".join(c.ljust(col_widths[i]) for i, c in enumerate(row)) + " |"
        for row in rendered_rows
    )
    return head + "\n" + sep + "\n" + body + "\n"


out = []

# 1. Header
out.append(f"# Blast radius {EM_DASH} {label['customer']} {EM_DASH} {label['change_id']}")
out.append("")

# 2. Meta block
out.append(f"- Generated: {label['generated_at']}")
out.append(f"- Inventory adapter: {label['inventory_adapter']} ({label['inventory_source_fingerprint']})")
out.append("")

# 3. TL;DR
n_tenants = len(label.get("tenants") or [])
n_services = len(label.get("services") or [])
n_devices = len(label.get("direct_devices") or [])
out.append("## TL;DR")
out.append("")
out.append(
    f"**{n_tenants} tenant(s), {n_services} service(s), {n_devices} direct device(s). "
    f"RTO band: {label['rto_band']}. Confidence: {label['confidence']}.**"
)
out.append("")

# 4. Direct devices
out.append("## Direct devices")
out.append("")
dev_rows = [[d.get("id"), d.get("role"), d.get("site")] for d in (label.get("direct_devices") or [])]
out.append(render_table(["ID", "Role", "Site"], dev_rows).rstrip())
out.append("")

# 5. Services affected
out.append("## Services affected")
out.append("")
svc_rows = [[s.get("id"), s.get("criticality"), s.get("rto_band"), s.get("owner_tenant")] for s in (label.get("services") or [])]
out.append(render_table(["ID", "Criticality", "RTO band", "Owner tenant"], svc_rows).rstrip())
out.append("")

# 6. Downstream consumers
out.append("## Downstream consumers")
out.append("")
dc_rows = [[d.get("id"), d.get("kind"), d.get("distance")] for d in (label.get("downstream_consumers") or [])]
out.append(render_table(["ID", "Kind", "Distance"], dc_rows).rstrip())
out.append("")

# 7. Coverage gaps (omitted entirely if empty)
gaps = label.get("coverage_gaps") or []
if gaps:
    out.append("## Coverage gaps")
    out.append("")
    out.append(f"> **Warning** {EM_DASH} the reasoner encountered incomplete inventory data.")
    out.append(">")
    for g in gaps:
        out.append(f"> - **{g.get('kind')}**: {g.get('detail')}")
    out.append("")

# 8. Regime addendum
regime = (os.environ.get("YCI_ACTIVE_REGIME") or "").strip().lower()
KNOWN = {"hipaa", "pci", "sox", "soc2", "iso27001", "nist", "commercial", "none"}
if regime in ("", "commercial", "none"):
    pass
elif regime == "hipaa":
    out.append("## HIPAA — PHI exposure surface")
    out.append("")
    out.append("Review each impacted service against the active BAA scope to identify PHI processors.")
    out.append("")
    for svc in label.get("services") or []:
        out.append(f"- `{svc['id']}` — confirm PHI boundary status against the BAA")
    out.append("")
elif regime == "pci":
    out.append("## PCI — CDE boundary review")
    out.append("")
    out.append("Review each impacted service against the active CDE boundary definition.")
    out.append("")
    for svc in label.get("services") or []:
        out.append(f"- `{svc['id']}` — confirm CDE boundary status")
    out.append("")
elif regime in ("sox", "soc2", "iso27001", "nist"):
    out.append(f"## {regime.upper()} — control mapping")
    out.append("")
    out.append("Map each impacted service to the control(s) that apply under this regime before approval.")
    out.append("")
elif regime not in KNOWN:
    out.append(f"> **Note** {EM_DASH} unrecognised compliance regime '{regime}'; skipping regime-specific addendum.")
    out.append("")

sys.stdout.write("\n".join(out).rstrip() + "\n")
PY
