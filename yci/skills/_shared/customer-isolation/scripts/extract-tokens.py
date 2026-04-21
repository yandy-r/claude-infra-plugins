#!/usr/bin/env python3
"""extract-tokens.py — yci customer-isolation fingerprint token extractor.

Reads a PreToolUse JSON payload (argv[1] path or stdin) and prints
`<category>\t<token>` lines for every identifier-shaped string. Category regexes
and whitelist must match yci/skills/_shared/customer-isolation/references/fingerprint-rules.md.
Always exits 0.
"""

import ipaddress
import json
import re
import sys

# ---------------------------------------------------------------------------
# Category regexes — compiled once at module level.
# Must stay byte-identical to inventory-fingerprint.py per fingerprint-rules.md.
# ---------------------------------------------------------------------------

# IPv6 regex — covers full, compressed, and mixed forms. Downstream validation
# via ipaddress.ip_address() always runs, so over-matching is tolerable; the
# point is to not UNDER-match common compressed literals like 2001:db8::1.
# Pattern adapted from the widely cited RegexLib IPv6 expression.
_IPV6_PATTERN = (
    r"(?<![A-Fa-f0-9:])"
    r"(?:"
    r"(?:[A-Fa-f0-9]{1,4}:){7}[A-Fa-f0-9]{1,4}"  # 1:2:3:4:5:6:7:8
    r"|(?:[A-Fa-f0-9]{1,4}:){1,7}:"  # 1:: … 1:2:3:4:5:6:7::
    r"|(?:[A-Fa-f0-9]{1,4}:){1,6}:[A-Fa-f0-9]{1,4}"  # 1::8 … 1:2:3:4:5:6::8
    r"|(?:[A-Fa-f0-9]{1,4}:){1,5}(?::[A-Fa-f0-9]{1,4}){1,2}"
    r"|(?:[A-Fa-f0-9]{1,4}:){1,4}(?::[A-Fa-f0-9]{1,4}){1,3}"
    r"|(?:[A-Fa-f0-9]{1,4}:){1,3}(?::[A-Fa-f0-9]{1,4}){1,4}"
    r"|(?:[A-Fa-f0-9]{1,4}:){1,2}(?::[A-Fa-f0-9]{1,4}){1,5}"
    r"|[A-Fa-f0-9]{1,4}:(?::[A-Fa-f0-9]{1,4}){1,6}"
    r"|:(?:(?::[A-Fa-f0-9]{1,4}){1,7}|:)"  # ::8 … ::
    r")"
    r"(?![A-Fa-f0-9:])"
)

CATEGORY_REGEXES = {
    "ipv4": re.compile(r"\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b"),
    "ipv6": re.compile(_IPV6_PATTERN),
    "hostname": re.compile(
        r"\b[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+\b",
        re.IGNORECASE,
    ),
    "asn": re.compile(r"\bAS\d+\b", re.IGNORECASE),
    "sow-ref": re.compile(r"\bSOW[-/ ]\d+\b", re.IGNORECASE),
    "credential-ref": re.compile(r"\b(?:vault|secret|kms):[\w./-]+\b"),
    "customer-id": re.compile(r"\b[a-z0-9][a-z0-9-]{2,63}\b"),
}

# ---------------------------------------------------------------------------
# Whitelists
# ---------------------------------------------------------------------------

WHITELISTED_IPV4 = [
    ipaddress.ip_network("127.0.0.0/8"),
    ipaddress.ip_network("0.0.0.0/32"),
    ipaddress.ip_network("192.0.2.0/24"),  # RFC 5737 TEST-NET-1
    ipaddress.ip_network("198.51.100.0/24"),  # RFC 5737 TEST-NET-2
    ipaddress.ip_network("203.0.113.0/24"),  # RFC 5737 TEST-NET-3
]

WHITELISTED_IPV6 = [
    ipaddress.ip_network("::1/128"),
    ipaddress.ip_network("2001:db8::/32"),
]

WHITELISTED_HOSTNAMES = {
    "localhost",
    "example.com",
    "example.net",
    "example.org",
    "www.example.com",
    "www.example.net",
    "www.example.org",
}

# customer-id tokens whose values are generic keywords — filtered before emission.
_KEYWORD_SKIP = {"file", "path", "test", "true", "false", "null", "none"}


# Build an extended skip set from whitelisted hostname labels so that constituent
# parts of whitelisted FQDNs (e.g. "example", "com", "localhost") are also
# suppressed from customer-id emission.
def _build_hostname_label_skip() -> frozenset:
    labels: set = set()
    for fqdn in WHITELISTED_HOSTNAMES:
        for part in fqdn.split("."):
            labels.add(part.lower())
    return frozenset(labels)


_HOSTNAME_LABEL_SKIP = _build_hostname_label_skip()

# Content-size cap: 1 MiB total scanned string content.
_SIZE_CAP = 1_048_576


# ---------------------------------------------------------------------------
# Whitelist / validation helpers
# ---------------------------------------------------------------------------


def _is_whitelisted_ipv4(tok: str) -> bool:
    """Return True if tok parses as an IPv4 address in any whitelisted network."""
    try:
        addr = ipaddress.ip_address(tok)
    except ValueError:
        return False
    if not isinstance(addr, ipaddress.IPv4Address):
        return False
    return any(addr in net for net in WHITELISTED_IPV4)


def _is_whitelisted_ipv6(tok: str) -> bool:
    """Return True if tok parses as an IPv6 address in any whitelisted network."""
    try:
        addr = ipaddress.ip_address(tok)
    except ValueError:
        return False
    if not isinstance(addr, ipaddress.IPv6Address):
        return False
    return any(addr in net for net in WHITELISTED_IPV6)


def _is_valid_ipv4(tok: str) -> bool:
    """Return True if tok is a valid IPv4 address (passes ipaddress parsing)."""
    try:
        addr = ipaddress.ip_address(tok)
        return isinstance(addr, ipaddress.IPv4Address)
    except ValueError:
        return False


def _is_valid_ipv6(tok: str) -> bool:
    """Return True if tok is a valid IPv6 address (passes ipaddress parsing)."""
    try:
        addr = ipaddress.ip_address(tok)
        return isinstance(addr, ipaddress.IPv6Address)
    except ValueError:
        return False


def _is_valid_hostname(tok: str) -> bool:
    """Return True if tok passes hostname minimum matching criteria.

    Requirements (per fingerprint-rules.md):
    - At least 4 characters long.
    - Must contain at least one dot.
    - The last label must contain at least one letter (rejects pure-IP strings).
    - Must not be whitelisted.
    """
    if len(tok) < 4:
        return False
    if "." not in tok:
        return False
    last_label = tok.rsplit(".", 1)[-1]
    if not any(c.isalpha() for c in last_label):
        # Last label is all digits → looks like an IPv4 address; skip.
        return False
    if tok.lower() in WHITELISTED_HOSTNAMES:
        return False
    return True


# ---------------------------------------------------------------------------
# Scan helpers
# ---------------------------------------------------------------------------


def _scan_string(s: str, results: dict) -> None:
    """Scan a single string value and add (category, token) hits to results dict."""
    for category, pattern in CATEGORY_REGEXES.items():
        for match in pattern.finditer(s):
            tok = match.group(0)

            if category == "ipv4":
                if not _is_valid_ipv4(tok):
                    continue
                if _is_whitelisted_ipv4(tok):
                    continue

            elif category == "ipv6":
                if not _is_valid_ipv6(tok):
                    continue
                if _is_whitelisted_ipv6(tok):
                    continue

            elif category == "hostname":
                if not _is_valid_hostname(tok):
                    continue

            elif category == "customer-id":
                tok_lower = tok.lower()
                if tok_lower in _KEYWORD_SKIP:
                    continue
                # Filter whitelisted hostname labels (e.g. "localhost", "example", "com").
                if tok_lower in _HOSTNAME_LABEL_SKIP:
                    continue
                # Filter purely-numeric tokens (e.g. "127" from "127.0.0.1").
                if tok_lower.isdigit():
                    continue

            key = (category, tok)
            if key not in results:
                results[key] = None  # insertion-order dedup via dict


# ---------------------------------------------------------------------------
# JSON walker
# ---------------------------------------------------------------------------


def _collect_strings(obj: object, strings: list, size_ref: list) -> bool:
    """Recursively walk obj and append leaf string values to strings.

    size_ref is a one-element list holding the running byte count (mutable int).
    Returns True if the size cap was reached (caller should stop walking).
    """
    if isinstance(obj, str):
        encoded_len = len(obj.encode("utf-8"))
        if size_ref[0] + encoded_len > _SIZE_CAP:
            if not size_ref[1]:  # emit truncation marker only once
                print("truncated:tokens:1", file=sys.stderr)
                size_ref[1] = True
            return True
        size_ref[0] += encoded_len
        strings.append(obj)
        return False

    if isinstance(obj, dict):
        for v in obj.values():
            if _collect_strings(v, strings, size_ref):
                return True

    elif isinstance(obj, list):
        for item in obj:
            if _collect_strings(item, strings, size_ref):
                return True

    return False


def _collect_high_signal(payload: dict, strings: list, size_ref: list) -> bool:
    """Explicitly extract high-signal fields (redundant with recursive walk, but
    makes Bash heredoc and multi-edit GOTCHA cases obvious).

    Returns True if the size cap was hit.
    """
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return False

    high_signal_values: list[object] = [
        tool_input.get("command"),  # Bash
        tool_input.get("prompt"),  # Task
        tool_input.get("old_string"),  # Edit
        tool_input.get("new_string"),  # Edit
        tool_input.get("content"),  # Write
    ]

    # MultiEdit: tool_input.edits[*].old_string / new_string
    edits = tool_input.get("edits")
    if isinstance(edits, list):
        for edit in edits:
            if isinstance(edit, dict):
                high_signal_values.append(edit.get("old_string"))
                high_signal_values.append(edit.get("new_string"))

    for val in high_signal_values:
        if val is None:
            continue
        s = val if isinstance(val, str) else str(val)
        encoded_len = len(s.encode("utf-8"))
        if size_ref[0] + encoded_len > _SIZE_CAP:
            if not size_ref[1]:
                print("truncated:tokens:1", file=sys.stderr)
                size_ref[1] = True
            return True
        # Only add if not already present from recursive walk — keep list simple,
        # dedup happens at scan level via the results dict.
        strings.append(s)
        size_ref[0] += encoded_len

    return False


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> None:
    # Read input: argv[1] as path OR stdin.
    if len(sys.argv) > 1:
        path = sys.argv[1]
        try:
            with open(path, encoding="utf-8") as fh:
                raw = fh.read()
        except OSError:
            print("truncated:tokens:invalid-json", file=sys.stderr)
            return
    else:
        raw = sys.stdin.read()

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        print("truncated:tokens:invalid-json", file=sys.stderr)
        return

    # size_ref: [running_byte_count, truncation_emitted_flag]
    size_ref: list = [0, False]
    strings: list[str] = []

    # Walk the full JSON tree first.
    _collect_strings(payload, strings, size_ref)

    # Explicitly scan high-signal fields (may duplicate, that's fine — dedup in scan).
    if not size_ref[1] and isinstance(payload, dict):
        _collect_high_signal(payload, strings, size_ref)

    # Scan all collected strings and build ordered dedup dict.
    results: dict = {}
    for s in strings:
        _scan_string(s, results)

    # Emit results.
    for category, token in results.keys():
        print(f"{category}\t{token}")


if __name__ == "__main__":
    main()
