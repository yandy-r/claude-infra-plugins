#!/usr/bin/env python3
# yci telemetry-sanitizer — deterministic text redaction CLI.

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# Allow running as script: add script dir for imports
_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from load_adapter_rules import (  # noqa: E402
    discover_redaction_rules,
    load_adapter_rules,
)
from patterns import PatternSpec, apply_pattern_list, build_core_patterns, redact_generic_kv_secrets  # noqa: E402


def _read_profile(path: Path | None) -> dict | None:
    if path is None:
        return None
    data = json.loads(path.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else None


def _adapter_dir(yci_root: Path, regime: str) -> Path:
    return yci_root / "skills" / "_shared" / "compliance-adapters" / regime


def sanitize(
    text: str,
    *,
    mode: str,
    profile: dict | None,
    extra_rule_paths: list[Path],
    regime: str | None,
    yci_root: Path | None,
) -> str:
    patterns: list[PatternSpec] = []
    patterns.extend(build_core_patterns(mode=mode, profile=profile))

    rule_paths = list(extra_rule_paths)
    if regime and yci_root:
        adir = _adapter_dir(yci_root, regime)
        rule_paths.extend(discover_redaction_rules(adir))

    for ar in load_adapter_rules(rule_paths):
        patterns.append(
            PatternSpec(
                name=f"adapter:{ar.name}",
                pattern=ar.pattern,
                replacement=ar.replacement,
            )
        )

    text = redact_generic_kv_secrets(text)
    text = apply_pattern_list(text, patterns)
    return text


def main() -> None:
    ap = argparse.ArgumentParser(description="Redact telemetry text for yci artifacts.")
    ap.add_argument(
        "path",
        nargs="?",
        help="Input file (default: stdin)",
    )
    ap.add_argument(
        "--profile-json",
        type=Path,
        default=None,
        help="Normalized customer profile JSON (from load-profile.sh).",
    )
    ap.add_argument(
        "--regime",
        default=None,
        help="compliance.regime value; loads adapter *-redaction.rules when set.",
    )
    ap.add_argument(
        "--yci-root",
        type=Path,
        default=None,
        help="Path to yci plugin root (directory containing skills/).",
    )
    ap.add_argument(
        "--mode",
        choices=("strict", "internal"),
        default="strict",
        help="internal skips strict cross-customer hostname heuristics.",
    )
    ap.add_argument(
        "--extra-rules",
        type=Path,
        action="append",
        default=[],
        help="Additional rule files (repeatable).",
    )
    args = ap.parse_args()

    yci_root = args.yci_root
    if yci_root is None:
        env = os.environ.get("YCI_ROOT")
        if env:
            yci_root = Path(env)

    profile = _read_profile(args.profile_json)

    if args.path:
        text = Path(args.path).read_text(encoding="utf-8")
    else:
        text = sys.stdin.read()

    out = sanitize(
        text,
        mode=args.mode,
        profile=profile,
        extra_rule_paths=list(args.extra_rules),
        regime=args.regime,
        yci_root=yci_root,
    )
    sys.stdout.write(out)


if __name__ == "__main__":
    main()
