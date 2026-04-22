# yci telemetry-sanitizer — load *-redaction.rules from compliance adapters.

from __future__ import annotations

import re
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from patterns import is_valid_luhn


@dataclass(frozen=True)
class AdapterRule:
    name: str
    pattern: re.Pattern[str]
    replacement: str | Callable[[re.Match[str]], str]


def _pan_replacement(match: re.Match[str]) -> str:
    candidate = match.group(0)
    if is_valid_luhn(candidate):
        return "[REDACTED_ADAPTER]"
    return candidate


def parse_rules_file(path: Path, *, default_name: str) -> list[AdapterRule]:
    """Parse adapter rule file.

    Format:
      - Lines starting with # are comments.
      - Blank lines ignored.
      - RE:<python-regex>  — required prefix for a regex line.
      - Optional NAME:name before following RE lines applies to next rule only.
    """
    text = path.read_text(encoding="utf-8")
    rules: list[AdapterRule] = []
    pending_name: str | None = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.upper().startswith("NAME:"):
            pending_name = line.split(":", 1)[1].strip() or default_name
            continue
        if line.upper().startswith("RE:"):
            expr = line[3:].lstrip()
            if not expr:
                raise ValueError(f"{path}: empty RE: directive (no regex expression after RE:): {line!r}")
            try:
                rx = re.compile(expr)
            except re.error as e:
                raise ValueError(f"{path}: invalid regex: {expr!r}: {e}") from e
            name = pending_name or default_name
            pending_name = None
            rules.append(
                AdapterRule(
                    name=name,
                    pattern=rx,
                    replacement=_pan_replacement if name == "pan_like" else "[REDACTED_ADAPTER]",
                )
            )
            continue
        raise ValueError(f"{path}: unrecognized line (expected RE: or NAME:): {line!r}")
    if pending_name is not None:
        raise ValueError(f"{path}: trailing NAME: with no following RE: (pending name={pending_name!r})")
    return rules


def discover_redaction_rules(adapter_dir: Path) -> list[Path]:
    if not adapter_dir.is_dir():
        return []
    out: list[Path] = []
    for p in sorted(adapter_dir.glob("*-redaction.rules")):
        if p.is_file():
            out.append(p)
    return out


def load_adapter_rules(paths: list[Path]) -> list[AdapterRule]:
    all_rules: list[AdapterRule] = []
    for p in paths:
        all_rules.extend(parse_rules_file(p, default_name=p.stem))
    return all_rules


def adapter_rules_to_specs(
    rules: list[AdapterRule],
) -> list[tuple[str, re.Pattern[str], str | Callable[[re.Match[str]], str]]]:
    return [(r.name, r.pattern, r.replacement) for r in rules]
