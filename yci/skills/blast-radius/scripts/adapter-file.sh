#!/usr/bin/env bash
# yci — file inventory adapter. Reads a directory tree of YAML inventory files
# and emits normalized JSON on stdout for the blast-radius reasoner.
#
# Usage: adapter-file.sh <inventory-root>
# Stdout: JSON object { adapter, root, tenants, services, devices, sites, dependencies }
# Stderr: error messages and warnings.
# Exit:
#   0 success
#   1 path missing, unreadable, or escapes root
#   2 YAML parse error or schema violation
#   3 runtime error (pyyaml missing)

set -euo pipefail

if [ "$#" -ne 1 ]; then
    printf 'usage: adapter-file.sh <inventory-root>\n' >&2
    exit 2
fi

INVENTORY_ROOT="$1"

python3 - "$INVENTORY_ROOT" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:
    sys.stderr.write(
        "yci: pyyaml not found — cannot parse inventory YAML files\n"
        "  adapter-pyyaml-missing: install pyyaml via 'pip install pyyaml' or your distro's python3-yaml package\n"
    )
    sys.exit(3)

ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")

CRITICALITY = {"tier-1", "tier-2", "tier-3", "tier-4", "unknown"}
RTO_BANDS = {"lt-5m", "5m-1h", "1h-4h", "gt-4h", "unknown"}
EDGE_TYPES = {"depends-on", "routes-via", "auth-via", "stores-in", "hosts", "peers-with"}

KIND_DIRS = ("tenants", "services", "devices", "sites")


def die(exit_code: int, msg: str) -> None:
    sys.stderr.write(msg if msg.endswith("\n") else msg + "\n")
    sys.exit(exit_code)


raw_root = sys.argv[1]

if not os.path.exists(raw_root):
    die(1, f"yci: inventory root not found: {raw_root}\n  adapter-path-missing")

try:
    root = os.path.realpath(raw_root, strict=True)
except OSError as exc:
    die(1, f"yci: inventory root unreadable: {raw_root}\n  adapter-path-missing: {exc}")

if not os.path.isdir(root):
    die(1, f"yci: inventory root is not a directory: {root}\n  adapter-path-missing")


def resolve_inside_root(path: str) -> str:
    """Resolve a file path under root and refuse escapes (symlinks / ..)."""
    resolved = os.path.realpath(path)
    try:
        common = os.path.commonpath([resolved, root])
    except ValueError:
        common = ""
    if common != root:
        die(1, f"yci: path escapes inventory root: {resolved}\n  adapter-path-escape")
    return resolved


def load_yaml_record(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as fh:
            data = yaml.safe_load(fh)
    except yaml.YAMLError as exc:
        first = str(exc).splitlines()[0] if str(exc) else "parse error"
        die(2, f"yci: malformed YAML in {path}\n  adapter-yaml-malformed: {first}")
    if not isinstance(data, dict):
        die(2, f"yci: record must be a YAML mapping: {path}\n  adapter-yaml-malformed")
    return data


def require(record: dict, field: str, path: str) -> None:
    if field not in record:
        die(2, f"yci: missing required field '{field}' in {path}\n  adapter-schema-required")


def check_id(record_id: str, filename_id: str, path: str) -> None:
    if not ID_RE.match(record_id):
        die(2, f"yci: invalid id '{record_id}' in {path} (must match [a-z0-9][a-z0-9-]*)\n  adapter-schema-required")
    if record_id != filename_id:
        die(2, f"yci: id '{record_id}' does not match filename basename '{filename_id}' in {path}\n  adapter-id-mismatch")


# --- warn about unknown top-level entries ------------------------------------
ALLOWED_TOP = set(KIND_DIRS) | {"dependencies.yaml"}
for entry in sorted(os.listdir(root)):
    full = os.path.join(root, entry)
    if os.path.isdir(full):
        if entry not in KIND_DIRS:
            sys.stderr.write(f"yci: warning — unknown top-level directory '{entry}' ignored\n")
    elif os.path.isfile(full):
        if entry != "dependencies.yaml":
            sys.stderr.write(f"yci: warning — unknown top-level file '{entry}' ignored\n")


def load_kind_dir(kind: str) -> list:
    out = []
    dir_path = os.path.join(root, kind)
    if not os.path.isdir(dir_path):
        return out
    for name in sorted(os.listdir(dir_path)):
        if not name.endswith(".yaml"):
            continue
        basename = name[:-5]
        full = resolve_inside_root(os.path.join(dir_path, name))
        if not os.path.isfile(full):
            continue  # nested subdirs silently ignored
        record = load_yaml_record(full)
        require(record, "id", full)
        check_id(str(record["id"]), basename, full)

        if kind == "tenants":
            require(record, "display_name", full)
        elif kind == "services":
            require(record, "criticality", full)
            require(record, "rto_band", full)
            if record["criticality"] not in CRITICALITY:
                die(2, f"yci: invalid criticality '{record['criticality']}' in {full}\n  adapter-schema-enum")
            if record["rto_band"] not in RTO_BANDS:
                die(2, f"yci: invalid rto_band '{record['rto_band']}' in {full}\n  adapter-schema-enum")
        elif kind == "devices":
            require(record, "role", full)
        elif kind == "sites":
            # only id required; display_name encouraged
            pass

        out.append(record)
    return out


tenants = load_kind_dir("tenants")
services = load_kind_dir("services")
devices = load_kind_dir("devices")
sites = load_kind_dir("sites")

# --- dependencies.yaml (optional) -------------------------------------------
dependencies = []
dep_path = os.path.join(root, "dependencies.yaml")
if os.path.isfile(dep_path):
    dep_path = resolve_inside_root(dep_path)
    dep_doc = load_yaml_record(dep_path)
    edges = dep_doc.get("edges", [])
    if edges is None:
        edges = []
    if not isinstance(edges, list):
        die(2, f"yci: 'edges' must be a list in {dep_path}\n  adapter-schema-required")
    for idx, edge in enumerate(edges):
        if not isinstance(edge, dict):
            die(2, f"yci: edge {idx} must be a mapping in {dep_path}\n  adapter-schema-required")
        for field in ("from", "to", "type"):
            if field not in edge:
                die(2, f"yci: edge {idx} missing '{field}' in {dep_path}\n  adapter-schema-required")
        if edge["type"] not in EDGE_TYPES:
            die(2, f"yci: edge {idx} has invalid type '{edge['type']}' in {dep_path}\n  adapter-schema-enum")
        dependencies.append({"from": edge["from"], "to": edge["to"], "type": edge["type"]})

# --- derive hosts edges from devices[].services_hosted ----------------------
seen = {(e["from"], e["to"], e["type"]) for e in dependencies}
for dev in devices:
    for svc in dev.get("services_hosted", []) or []:
        edge = (dev["id"], svc, "hosts")
        if edge not in seen:
            dependencies.append({"from": edge[0], "to": edge[1], "type": edge[2]})
            seen.add(edge)

output = {
    "adapter": "file",
    "root": root,
    "tenants": tenants,
    "services": services,
    "devices": devices,
    "sites": sites,
    "dependencies": dependencies,
}

json.dump(output, sys.stdout, indent=2, sort_keys=False, default=str)
sys.stdout.write("\n")
PY
