#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def _lookup(data: dict, key: str):
    if key == "this":
        return data.get("this", "")
    value = data
    for part in key.split("."):
        if isinstance(value, dict):
            value = value.get(part, "")
        else:
            return ""
    return value


def render_template(template: str, bundle: dict) -> str:
    def each_repl(match: re.Match[str]) -> str:
        field = match.group(1).strip()
        body = match.group(2)
        items = _lookup(bundle, field)
        if not isinstance(items, list):
            return ""
        rendered: list[str] = []
        for item in items:
            scope = dict(bundle)
            if isinstance(item, dict):
                scope.update(item)
                scope["this"] = item
            else:
                scope["this"] = item
            rendered.append(
                re.sub(
                    r"{{\s*([^{}]+?)\s*}}",
                    lambda m, current_scope=scope: str(_lookup(current_scope, m.group(1).strip())),
                    body,
                )
            )
        return "".join(rendered)

    rendered = re.sub(r"{{#each\s+([^}]+)}}(.*?){{/each}}", each_repl, template, flags=re.DOTALL)
    rendered = re.sub(r"{{\s*([^{}]+?)\s*}}", lambda m: str(_lookup(bundle, m.group(1).strip())), rendered)
    return rendered


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle-json", required=True, type=Path)
    ap.add_argument("--template", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()

    bundle = json.loads(args.bundle_json.read_text(encoding="utf-8"))
    template = args.template.read_text(encoding="utf-8")
    args.output.write_text(render_template(template, bundle), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
