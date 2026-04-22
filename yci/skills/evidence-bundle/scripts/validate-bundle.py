#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path


def _check_type(name: str, value, expected: str) -> str | None:
    if expected == "string" and not isinstance(value, str):
        return f"{name} must be a string"
    if expected == "array" and not isinstance(value, list):
        return f"{name} must be an array"
    if expected == "object" and not isinstance(value, dict):
        return f"{name} must be an object"
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle-json", required=True, type=Path)
    ap.add_argument("--schema", type=Path, default=None)
    args = ap.parse_args()

    errors: list[str] = []
    bundle: dict = {}

    try:
        bundle = json.loads(args.bundle_json.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"{args.bundle_json}: failed to load bundle JSON: {exc}")

    # Always-required fields for evidence-bundle, independent of adapter schema.
    if isinstance(bundle, dict):
        for field in (
            "change_id",
            "change_summary",
            "rollback_plan",
            "approver",
            "operator_identity",
            "git_commit_range",
            "generated_at",
            "executed_at",
        ):
            value = bundle.get(field)
            if not isinstance(value, str) or not value.strip():
                errors.append(f"{field} must be a non-empty string")

        for field in ("approvals", "pre_check_artifacts", "post_check_artifacts", "tenant_scope"):
            value = bundle.get(field)
            if not isinstance(value, list) or not value:
                errors.append(f"{field} must be a non-empty array")

        for field in ("timestamp_utc", "generated_at", "executed_at"):
            value = bundle.get(field)
            if isinstance(value, str):
                try:
                    datetime.fromisoformat(value.replace("Z", "+00:00"))
                except ValueError:
                    errors.append(f"{field} must be ISO-8601")

    schema: dict = {}
    if args.schema is not None:
        if not args.schema.is_file():
            errors.append(f"{args.schema}: schema path must be an existing file")
        else:
            try:
                schema = json.loads(args.schema.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as exc:
                errors.append(f"{args.schema}: failed to load schema JSON: {exc}")

    if isinstance(bundle, dict) and isinstance(schema, dict) and schema:
        for field in schema.get("required", []):
            if field not in bundle:
                errors.append(f"missing required schema field: {field}")

        properties = schema.get("properties", {})
        for name, spec in properties.items():
            if name not in bundle:
                continue
            err = _check_type(name, bundle[name], spec.get("type", ""))
            if err:
                errors.append(err)
            if spec.get("format") == "date-time" and isinstance(bundle[name], str):
                try:
                    datetime.fromisoformat(bundle[name].replace("Z", "+00:00"))
                except ValueError:
                    errors.append(f"{name} must be date-time")
            if "enum" in spec and bundle[name] not in spec["enum"]:
                errors.append(f"{name} must be one of {spec['enum']}")
            if spec.get("minItems") and isinstance(bundle[name], list) and len(bundle[name]) < spec["minItems"]:
                errors.append(f"{name} must contain at least {spec['minItems']} item(s)")

        if schema.get("additionalProperties") is False:
            allowed_keys = set(properties)
            extra_keys = sorted(set(bundle) - allowed_keys)
            for key in extra_keys:
                errors.append(f"{key} is not allowed by schema")

    if errors:
        for err in errors:
            print(err, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
