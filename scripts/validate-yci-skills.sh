#!/usr/bin/env bash
# validate-yci-skills.sh — Phase-0 validator for the yci plugin surface.
#
# Checks:
#   1. yci/.claude-plugin/plugin.json exists and parses as valid JSON.
#   2. yci/skills/hello/SKILL.md exists.
#   3. yci/skills/hello/SKILL.md has valid YAML frontmatter with:
#      - Opening and closing "---" delimiters.
#      - name: hello
#      - description: <non-empty string>
#
# Scope: Phase-0 only — intentionally narrow (two files).
# Frontmatter parsing falls back to regex when pyyaml is unavailable,
# mirroring the approach in scripts/validate-ycc-commands.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PLUGIN_JSON="${REPO_ROOT}/yci/.claude-plugin/plugin.json"
SKILL_MD="${REPO_ROOT}/yci/skills/hello/SKILL.md"
SCRIPT_NAME="validate-yci-skills.sh"

# 1. Check plugin.json exists and parses as valid JSON.
if [[ ! -f "${PLUGIN_JSON}" ]]; then
    echo "${SCRIPT_NAME}: missing ${PLUGIN_JSON}" >&2
    exit 1
fi
if ! python3 -m json.tool "${PLUGIN_JSON}" > /dev/null 2>&1; then
    echo "${SCRIPT_NAME}: ${PLUGIN_JSON} is not valid JSON" >&2
    exit 1
fi

# 2. Check SKILL.md exists.
if [[ ! -f "${SKILL_MD}" ]]; then
    echo "${SCRIPT_NAME}: missing ${SKILL_MD}" >&2
    exit 1
fi

# 3. Parse and validate frontmatter via Python (pyyaml or regex fallback).
python3 - "${SKILL_MD}" <<'PY'
import re
import sys
from pathlib import Path

try:
    import yaml
    def load_frontmatter(text: str) -> dict:
        m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
        return (yaml.safe_load(m.group(1)) or {}) if m else {}
except ImportError:
    def load_frontmatter(text: str) -> dict:
        m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
        if not m:
            return {}
        out: dict = {}
        for line in m.group(1).splitlines():
            km = re.match(r"^([a-zA-Z_][a-zA-Z0-9_-]*):\s*(.*)$", line)
            if not km:
                continue
            key, val = km.group(1), km.group(2).strip()
            if val.startswith(('"', "'")):
                val = val.strip("\"'")
            if val.lower() in {"true", "false"}:
                out[key] = (val.lower() == "true")
            else:
                out[key] = val
        return out

skill_md = Path(sys.argv[1])
text = skill_md.read_text(encoding="utf-8")

script_name = "validate-yci-skills.sh"
errors: list[str] = []

# Verify frontmatter delimiters are present.
if not re.match(r"^---\n.*?\n---\n", text, re.DOTALL):
    errors.append(
        f"{skill_md}: frontmatter delimiters missing or malformed "
        f"(expected opening and closing '---' lines)"
    )
    for err in errors:
        print(f"{script_name}: {err}", file=sys.stderr)
    sys.exit(1)

fm = load_frontmatter(text)

# Verify name: hello
name_val = fm.get("name", "")
if name_val != "hello":
    errors.append(
        f"{skill_md}: frontmatter 'name' must be 'hello', got {name_val!r}"
    )

# Verify description: non-empty string
desc_val = fm.get("description", "")
if not isinstance(desc_val, str) or not desc_val.strip():
    errors.append(
        f"{skill_md}: frontmatter 'description' must be a non-empty string"
    )

if errors:
    for err in errors:
        print(f"{script_name}: {err}", file=sys.stderr)
    sys.exit(1)
PY

echo "[validate-yci-skills] OK: yci/.claude-plugin/plugin.json and yci/skills/hello/SKILL.md valid."
