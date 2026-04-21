#!/usr/bin/env bash
# yci — blast-radius pure reasoner. Reads { inventory, change, customer }
# JSON on stdin, emits a blast-radius label JSON on stdout. No filesystem
# access; deterministic given identical inputs and YCI_GENERATED_AT.
#
# Usage: reason.sh < payload.json
# Stdout: JSON object matching references/label-schema.json
# Stderr: error messages only.
# Exit:
#   0 success
#   1 malformed or missing stdin
#   2 reasoner internal error
#   3 runtime error

set -euo pipefail

if [ -t 0 ]; then
    printf 'usage: reason.sh < payload.json\n' >&2
    printf '  reason-missing-stdin: no stdin provided\n' >&2
    exit 1
fi

_YCI_REASON_INPUT="$(cat)"
if [ -z "${_YCI_REASON_INPUT}" ]; then
    printf 'yci: reason.sh stdin empty\n' >&2
    printf '  reason-missing-stdin\n' >&2
    exit 1
fi
export _YCI_REASON_INPUT

python3 - <<'PY'
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone

RTO_ORDER = {"lt-5m": 0, "5m-1h": 1, "1h-4h": 2, "gt-4h": 3}
CRITICALITY = {"tier-1", "tier-2", "tier-3", "tier-4", "unknown"}
RTO_BANDS = {"lt-5m", "5m-1h", "1h-4h", "gt-4h", "unknown"}
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
BFS_MAX_DEPTH = 5


def die(exit_code, msg):
    sys.stderr.write(msg if msg.endswith("\n") else msg + "\n")
    sys.exit(exit_code)


raw = os.environ.get("_YCI_REASON_INPUT", "")
try:
    payload = json.loads(raw)
except json.JSONDecodeError as exc:
    die(1, f"yci: reason.sh stdin is not valid JSON\n  reason-missing-stdin: {exc}")

for key in ("inventory", "change", "customer"):
    if key not in payload:
        die(1, f"yci: reason.sh payload missing required key '{key}'\n  reason-missing-required")

inv = payload["inventory"]
change = payload["change"]
customer = payload["customer"]

if not isinstance(inv, dict) or not isinstance(change, dict) or not isinstance(customer, str):
    die(1, "yci: reason.sh payload shape invalid (inventory/change must be objects, customer must be string)\n  reason-missing-required")

# --- index inventory ---------------------------------------------------------
tenants_by_id = {t["id"]: t for t in inv.get("tenants", [])}
services_by_id = {s["id"]: s for s in inv.get("services", [])}
devices_by_id = {d["id"]: d for d in inv.get("devices", [])}

edges = list(inv.get("dependencies", []))

# outgoing_from[x] = list of (y, type) for edges x --type--> y
# incoming_to[y]   = list of (x, type) for edges x --type--> y
outgoing_from = {}
incoming_to = {}
for edge in edges:
    frm, to, tp = edge["from"], edge["to"], edge["type"]
    outgoing_from.setdefault(frm, []).append((to, tp))
    incoming_to.setdefault(to, []).append((frm, tp))

coverage_gaps = []
gap_seen = set()


def add_gap(kind: str, detail: str) -> None:
    key = (kind, detail)
    if key in gap_seen:
        return
    gap_seen.add(key)
    coverage_gaps.append({"kind": kind, "detail": detail})


# --- seed resolution --------------------------------------------------------
direct_device_ids: list = []
direct_device_seen = set()
direct_service_ids: list = []
direct_service_seen = set()
direct_tenant_ids: list = []
direct_tenant_seen = set()


def add_direct_device(did: str) -> None:
    if did not in direct_device_seen:
        direct_device_seen.add(did)
        direct_device_ids.append(did)


def add_direct_service(sid: str) -> None:
    if sid not in direct_service_seen:
        direct_service_seen.add(sid)
        direct_service_ids.append(sid)


def add_direct_tenant(tid: str) -> None:
    if tid not in direct_tenant_seen:
        direct_tenant_seen.add(tid)
        direct_tenant_ids.append(tid)


targets = change.get("targets") or []
for tgt in targets:
    kind = tgt.get("kind")
    tid = str(tgt.get("id", ""))
    if kind == "device":
        if tid in devices_by_id:
            add_direct_device(tid)
        else:
            add_gap("unknown-device", f"device '{tid}' referenced by change but not in inventory")
    elif kind == "service":
        if tid in services_by_id:
            add_direct_service(tid)
        else:
            add_gap("unknown-service", f"service '{tid}' referenced by change but not in inventory")
    elif kind == "tenant":
        if tid in tenants_by_id:
            add_direct_tenant(tid)
            for svc in inv.get("services", []):
                if svc.get("owner_tenant") == tid:
                    add_direct_service(svc["id"])
        else:
            add_gap("missing-tenant", f"tenant '{tid}' referenced by change but not in inventory")
    elif kind == "interface":
        parent = tid.split(":", 1)[0]
        if parent in devices_by_id:
            add_direct_device(parent)
        else:
            add_gap("unknown-device", f"interface '{tid}' parent device '{parent}' not in inventory")
    elif kind == "vlan":
        matched = False
        for dev in inv.get("devices", []):
            vlans = dev.get("vlans") or []
            if tid in [str(v) for v in vlans]:
                add_direct_device(dev["id"])
                matched = True
        # vlans legitimately may match nothing — no gap
        _ = matched
    elif kind == "arn":
        matched = False
        for svc in inv.get("services", []):
            arns = svc.get("arns") or []
            if tid in arns:
                add_direct_service(svc["id"])
                matched = True
        if not matched:
            add_gap("unknown-service", f"ARN '{tid}' referenced by change but no inventory service has this ARN")

# --- BFS --------------------------------------------------------------------
# distance map: id -> (kind, distance). kind in {"device","service","tenant"}.
distance = {}
for d in direct_device_ids:
    distance[d] = ("device", 0)
for s in direct_service_ids:
    distance[s] = ("service", 0)
for t in direct_tenant_ids:
    distance[t] = ("tenant", 0)

# dependencies-traversed holds the edges BFS walked, preserving order.
edges_walked: list = []
edges_walked_seen = set()


def record_edge(frm: str, to: str, tp: str) -> None:
    key = (frm, to, tp)
    if key in edges_walked_seen:
        return
    edges_walked_seen.add(key)
    edges_walked.append({"from": frm, "to": to, "type": tp})


frontier = list(distance.keys())
depth = 0
depth_cap_hit = False

while frontier and depth < BFS_MAX_DEPTH:
    depth += 1
    next_frontier = []
    for node in frontier:
        node_kind, node_dist = distance[node]
        # Forward edges: device hosts/routes-via services (services upstream from devices)
        # When a device is touched, services that route-via or are hosted on it are impacted.
        # Those services' incoming `routes-via`/`hosts` edges point TO the device.
        if node_kind == "device":
            for (src, tp) in incoming_to.get(node, []):
                if tp in ("routes-via", "hosts"):
                    if src not in distance:
                        distance[src] = ("service" if src in services_by_id else "device", depth)
                        next_frontier.append(src)
                    record_edge(src, node, tp)
        # Services: things that depends-on this service are downstream consumers
        if node_kind == "service":
            for (src, tp) in incoming_to.get(node, []):
                if tp == "depends-on":
                    if src not in distance:
                        kd = "service" if src in services_by_id else ("tenant" if src in tenants_by_id else "service")
                        distance[src] = (kd, depth)
                        next_frontier.append(src)
                    record_edge(src, node, tp)
            # Roll up tenant
            svc = services_by_id.get(node)
            if svc and svc.get("owner_tenant"):
                owner = svc["owner_tenant"]
                if owner not in distance:
                    if owner in tenants_by_id:
                        distance[owner] = ("tenant", depth)
                        next_frontier.append(owner)
                    else:
                        add_gap("missing-tenant", f"service '{node}' owner_tenant '{owner}' not in inventory")
    frontier = next_frontier

if depth >= BFS_MAX_DEPTH and frontier:
    depth_cap_hit = True
    add_gap("orphan-edge", "BFS depth cap (5) reached — graph may have cycles or exceed 5 hops")
_ = depth_cap_hit

# --- orphan-edge detection (endpoints absent from inventory) ----------------
known_ids = set(services_by_id) | set(devices_by_id) | set(tenants_by_id)
for edge in edges:
    if edge["from"] not in known_ids:
        add_gap("orphan-edge", f"edge references unknown id '{edge['from']}'")
    if edge["to"] not in known_ids:
        add_gap("orphan-edge", f"edge references unknown id '{edge['to']}'")

# --- assemble services[] ----------------------------------------------------
label_services = []
impacted_service_ids = [node for node, (kind, _) in distance.items() if kind == "service"]

# Deterministic order: by distance asc, then id asc
impacted_service_ids.sort(key=lambda sid: (distance[sid][1], sid))

for sid in impacted_service_ids:
    svc = services_by_id.get(sid)
    if svc is None:
        continue  # referenced via edge but no record — already counted as orphan-edge
    entry = {
        "id": sid,
        "criticality": svc.get("criticality", "unknown"),
        "rto_band": svc.get("rto_band", "unknown"),
    }
    if "criticality" not in svc:
        add_gap("missing-criticality", f"service '{sid}' has no criticality in inventory")
    elif svc["criticality"] not in CRITICALITY:
        entry["criticality"] = "unknown"
        add_gap("missing-criticality", f"service '{sid}' has invalid criticality '{svc['criticality']}'")

    if "rto_band" not in svc:
        # per-service RTO-downgrade rule
        outs = outgoing_from.get(sid, [])
        inherit = None
        if len(outs) == 1:
            target_id, _tp = outs[0]
            target_svc = services_by_id.get(target_id)
            if target_svc and target_svc.get("rto_band") in RTO_BANDS and target_svc["rto_band"] != "unknown":
                inherit = target_svc["rto_band"]
        if inherit:
            entry["rto_band"] = inherit
        else:
            entry["rto_band"] = "unknown"
            add_gap("missing-rto", f"service '{sid}' has no rto_band in inventory")
    elif svc["rto_band"] not in RTO_BANDS:
        entry["rto_band"] = "unknown"
        add_gap("missing-rto", f"service '{sid}' has invalid rto_band '{svc['rto_band']}'")

    if svc.get("owner_tenant"):
        entry["owner_tenant"] = svc["owner_tenant"]
    label_services.append(entry)

# --- assemble direct_devices[] ----------------------------------------------
label_direct_devices = []
for did in direct_device_ids:
    dev = devices_by_id.get(did)
    if dev is None:
        continue
    entry = {"id": did, "role": dev.get("role", "")}
    if dev.get("site"):
        entry["site"] = dev["site"]
    label_direct_devices.append(entry)

# --- assemble tenants[] -----------------------------------------------------
tenants_seen = []
tenants_seen_set = set()
for node, (kind, _) in distance.items():
    if kind == "tenant" and node in tenants_by_id and node not in tenants_seen_set:
        tenants_seen_set.add(node)
        tenants_seen.append(node)
# rollup by service owner
for svc_entry in label_services:
    owner = svc_entry.get("owner_tenant")
    if owner and owner in tenants_by_id and owner not in tenants_seen_set:
        tenants_seen_set.add(owner)
        tenants_seen.append(owner)
tenants_seen.sort()

# --- assemble downstream_consumers[] (distance ≥ 1, services + tenants) -----
label_downstream = []
for node, (kind, d) in distance.items():
    if d < 1:
        continue
    if kind == "service" and node in services_by_id:
        label_downstream.append({"id": node, "kind": "service", "distance": d})
    elif kind == "tenant" and node in tenants_by_id:
        label_downstream.append({"id": node, "kind": "tenant", "distance": d})
label_downstream.sort(key=lambda x: (x["distance"], x["kind"], x["id"]))

# --- aggregate rto_band -----------------------------------------------------
known_bands = [s["rto_band"] for s in label_services if s["rto_band"] != "unknown"]
if known_bands:
    strictest = min(known_bands, key=lambda b: RTO_ORDER[b])
    label_rto_band = strictest
else:
    label_rto_band = "unknown"

# --- confidence -------------------------------------------------------------
STRUCTURAL = {"unknown-device", "unknown-service", "orphan-edge", "missing-tenant"}
if not coverage_gaps:
    confidence = "high"
elif any(g["kind"] in STRUCTURAL for g in coverage_gaps):
    confidence = "low"
else:
    confidence = "medium"

# --- fingerprint ------------------------------------------------------------
fingerprint_subset = {
    "tenants": inv.get("tenants", []),
    "services": inv.get("services", []),
    "devices": inv.get("devices", []),
    "dependencies": inv.get("dependencies", []),
    "sites": inv.get("sites", []),
}
canonical = json.dumps(fingerprint_subset, sort_keys=True, separators=(",", ":"), default=str)
digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
fingerprint = f"sha256:{digest}"

# --- generated_at -----------------------------------------------------------
gen_override = os.environ.get("YCI_GENERATED_AT")
if gen_override:
    generated_at = gen_override
else:
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# --- change_id --------------------------------------------------------------
change_id = str(change.get("change_id", ""))
if not ID_RE.match(customer):
    die(1, f"yci: invalid customer id '{customer}'\n  reason-missing-required")

label = {
    "schema_version": 1,
    "change_id": change_id,
    "customer": customer,
    "inventory_adapter": inv.get("adapter", "file"),
    "inventory_source_fingerprint": fingerprint,
    "generated_at": generated_at,
    "tenants": tenants_seen,
    "services": label_services,
    "direct_devices": label_direct_devices,
    "dependencies": edges_walked,
    "downstream_consumers": label_downstream,
    "rto_band": label_rto_band,
    "confidence": confidence,
    "coverage_gaps": coverage_gaps,
}

json.dump(label, sys.stdout, indent=2, sort_keys=False, default=str)
sys.stdout.write("\n")
PY
