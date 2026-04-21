# yci telemetry-sanitizer — canonical redaction pattern catalog.
# Pure data + compiled regex builders; no I/O.

from __future__ import annotations

import re
from collections.abc import Iterable
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class PatternSpec:
    """Single redaction rule; earlier entries run first."""

    name: str
    pattern: re.Pattern[str]
    replacement: str


def _c(pat: str, flags: int = 0) -> re.Pattern[str]:
    return re.compile(pat, flags)


def patterns_secrets_and_pem() -> list[PatternSpec]:
    return [
        PatternSpec(
            "aws_access_key",
            _c(r"\bAKIA[0-9A-Z]{16}\b"),
            "[REDACTED_AWS_ACCESS_KEY_ID]",
        ),
        PatternSpec(
            "pem_block",
            _c(
                r"-----BEGIN [A-Z0-9 -]+-----[\s\S]*?-----END [A-Z0-9 -]+-----",
                re.MULTILINE,
            ),
            "[REDACTED_PEM_BLOCK]",
        ),
    ]


def patterns_network_ids() -> list[PatternSpec]:
    ipv4 = r"(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)"
    # Simplified IPv6 (covers common shapes; corpus tests use non-compressed)
    # Full and compressed IPv6 (common operational shapes)
    ipv6 = (
        r"(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|"
        r"(?:[0-9a-fA-F]{1,4}:){1,7}:(?:[0-9a-fA-F]{1,4}:?){0,6}[0-9a-fA-F]{0,4}|"
        r"::(?:[0-9a-fA-F]{1,4}:?){0,6}[0-9a-fA-F]{0,4}"
    )
    mac = r"(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}"
    return [
        PatternSpec("ipv4", _c(r"\b" + ipv4 + r"\b"), "[REDACTED_IPV4]"),
        PatternSpec("ipv6", _c(r"(?<![0-9A-Fa-f:])" + ipv6 + r"(?![0-9A-Fa-f:])"), "[REDACTED_IPV6]"),
        PatternSpec("mac", _c(r"\b" + mac + r"\b"), "[REDACTED_MAC]"),
        PatternSpec(
            "asn",
            _c(r"\b(?:AS|ASN)\s*(\d{1,6})\b", re.I),
            r"[REDACTED_ASN_\1]",
        ),
    ]


def patterns_cloud_accounts() -> list[PatternSpec]:
    return [
        PatternSpec(
            "aws_account_id",
            _c(r"(?<![0-9])(\d{12})(?![0-9])"),
            "[REDACTED_AWS_ACCOUNT]",
        ),
        PatternSpec(
            "azure_subscription_guid",
            _c(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-" r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"),
            "[REDACTED_AZURE_GUID]",
        ),
    ]


def pattern_generic_kv_secret() -> re.Pattern[str]:
    return _c(
        r"(?i)\b(?:api[_-]?key|access[_-]?token|auth[_-]?token|bearer|"
        r"client[_-]?secret|password|secret|token)\s*[=:]\s*"
        r"['\"]?([^\s'\"]{12,})['\"]?",
    )


def pattern_fqdn_strict() -> re.Pattern[str]:
    return _c(r"\b(?=.{4,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+" r"[a-zA-Z]{2,63}\b")


def pattern_customer_slug_hostnames(customer_id: str) -> list[PatternSpec]:
    if not customer_id or not re.match(r"^[a-z0-9][a-z0-9-]*$", customer_id):
        return []
    safe = re.escape(customer_id)
    return [
        PatternSpec(
            f"hostname_customer_slug_{customer_id}",
            _c(
                rf"\b(?:[a-z0-9-]+\.)+{safe}\.(?:[a-z]{{2,63}}\.)*[a-z]{{2,63}}\b",
                re.I,
            ),
            "[REDACTED_CUSTOMER_HOST]",
        ),
    ]


def build_core_patterns(
    *,
    mode: str,
    profile: dict[str, Any] | None,
) -> list[PatternSpec]:
    """Core patterns. mode: 'strict' | 'internal'."""
    out: list[PatternSpec] = []
    out.extend(patterns_secrets_and_pem())
    out.extend(patterns_network_ids())
    out.extend(patterns_cloud_accounts())

    customer_id = ""
    if profile:
        cust = profile.get("customer")
        if isinstance(cust, dict):
            cid = cust.get("id")
            if isinstance(cid, str):
                customer_id = cid.strip()

    if mode != "internal":
        out.extend(pattern_customer_slug_hostnames(customer_id))
        out.append(PatternSpec("fqdn_generic", pattern_fqdn_strict(), "[REDACTED_HOSTNAME]"))

    return out


def apply_pattern_list(text: str, patterns: Iterable[PatternSpec]) -> str:
    for spec in patterns:
        text = spec.pattern.sub(spec.replacement, text)
    return text


def redact_generic_kv_secrets(text: str) -> str:
    rx = pattern_generic_kv_secret()

    def _sub(m: re.Match[str]) -> str:
        full = m.group(0)
        secret = m.group(1)
        return full.replace(secret, "[REDACTED_SECRET]")

    return rx.sub(_sub, text)
