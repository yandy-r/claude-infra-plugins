#!/usr/bin/env python3
"""inventory-fingerprint.py — yci customer-isolation bundle builder.

Loads a customer's profile YAML and inventory tree, extracts identifier tokens
per fingerprint-rules.md, and emits a canonical JSON bundle on stdout.
Writes atomic cache at <data-root>/.cache/customer-isolation/<customer>.json.
"""

import argparse
import datetime
import ipaddress
import json
import os
import os.path
import re
import subprocess
import sys

try:
    import yaml
except ImportError:
    print("yci guard: PyYAML missing; inventory-fingerprint requires it.", file=sys.stderr)
    print("  install: pip install pyyaml  (or use the system package manager)", file=sys.stderr)
    sys.exit(2)

# ---------------------------------------------------------------------------
# Category regexes — copied verbatim from fingerprint-rules.md.
# Keep byte-identical with extract-tokens.py.  Compile once at module level.
# ---------------------------------------------------------------------------

# IPv6 regex — covers full, compressed, and mixed forms. Must match
# extract-tokens.py's _IPV6_PATTERN byte-for-byte.
_IPV6_PATTERN = (
    r"(?<![A-Fa-f0-9:])"
    r"(?:"
    r"(?:[A-Fa-f0-9]{1,4}:){7}[A-Fa-f0-9]{1,4}"
    r"|(?:[A-Fa-f0-9]{1,4}:){1,7}:"
    r"|(?:[A-Fa-f0-9]{1,4}:){1,6}:[A-Fa-f0-9]{1,4}"
    r"|(?:[A-Fa-f0-9]{1,4}:){1,5}(?::[A-Fa-f0-9]{1,4}){1,2}"
    r"|(?:[A-Fa-f0-9]{1,4}:){1,4}(?::[A-Fa-f0-9]{1,4}){1,3}"
    r"|(?:[A-Fa-f0-9]{1,4}:){1,3}(?::[A-Fa-f0-9]{1,4}){1,4}"
    r"|(?:[A-Fa-f0-9]{1,4}:){1,2}(?::[A-Fa-f0-9]{1,4}){1,5}"
    r"|[A-Fa-f0-9]{1,4}:(?::[A-Fa-f0-9]{1,4}){1,6}"
    r"|:(?:(?::[A-Fa-f0-9]{1,4}){1,7}|:)"
    r")"
    r"(?![A-Fa-f0-9:])"
)

CATEGORY_REGEXES: dict[str, re.Pattern[str]] = {
    "ipv4": re.compile(r"\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}" r"(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b"),
    "ipv6": re.compile(_IPV6_PATTERN),
    "hostname": re.compile(
        r"\b[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+\b",
        re.IGNORECASE,
    ),
    "asn": re.compile(r"\bAS\d+\b", re.IGNORECASE),
    "sow-ref": re.compile(r"\bSOW[-/ ]\d+\b", re.IGNORECASE),
    # Case-sensitive to match extract-tokens.py — credential schemes are
    # lowercase-by-convention (vault:, secret:, kms:).
    "credential-ref": re.compile(r"\b(?:vault|secret|kms):[\w./-]+\b"),
    "customer-id": re.compile(r"\b[a-z0-9][a-z0-9-]{2,63}\b"),
}

# ---------------------------------------------------------------------------
# Generic-token whitelist — must stay aligned with extract-tokens.py.
# ---------------------------------------------------------------------------

_IPV4_WHITELIST_CIDRS = [
    ipaddress.ip_network("127.0.0.0/8"),
    ipaddress.ip_network("0.0.0.0/32"),
    ipaddress.ip_network("192.0.2.0/24"),  # RFC 5737 TEST-NET-1
    ipaddress.ip_network("198.51.100.0/24"),  # RFC 5737 TEST-NET-2
    ipaddress.ip_network("203.0.113.0/24"),  # RFC 5737 TEST-NET-3
]

_IPV6_WHITELIST_NETWORKS = [
    ipaddress.ip_network("::1/128"),
    ipaddress.ip_network("2001:db8::/32"),  # RFC 3849 documentation prefix
]

_HOSTNAME_WHITELIST = {
    "localhost",
    "example.com",
    "example.net",
    "example.org",
    "www.example.com",
    "www.example.net",
    "www.example.org",
}

MAX_INVENTORY_FILES = 2000


# ---------------------------------------------------------------------------
# Token extraction helpers
# ---------------------------------------------------------------------------


def _is_whitelisted_ipv4(token: str) -> bool:
    try:
        addr = ipaddress.ip_address(token)
    except ValueError:
        return False
    if not isinstance(addr, ipaddress.IPv4Address):
        return False
    return any(addr in net for net in _IPV4_WHITELIST_CIDRS)


def _is_whitelisted_ipv6(token: str) -> bool:
    try:
        addr = ipaddress.ip_address(token)
    except ValueError:
        return False
    if not isinstance(addr, ipaddress.IPv6Address):
        return False
    return any(addr in net for net in _IPV6_WHITELIST_NETWORKS)


def _is_valid_ipv4(token: str) -> bool:
    try:
        addr = ipaddress.ip_address(token)
        return isinstance(addr, ipaddress.IPv4Address)
    except ValueError:
        return False


def _is_valid_ipv6(token: str) -> bool:
    try:
        addr = ipaddress.ip_address(token)
        return isinstance(addr, ipaddress.IPv6Address)
    except ValueError:
        return False


def _extract_from_string(text: str, tokens: dict[str, set[str]]) -> None:
    """Extract all fingerprint tokens from a single string into the tokens sets."""
    for category, pattern in CATEGORY_REGEXES.items():
        for match in pattern.finditer(text):
            token = match.group(0)

            if category == "ipv4":
                if not _is_valid_ipv4(token):
                    continue
                if _is_whitelisted_ipv4(token):
                    continue

            elif category == "ipv6":
                if not _is_valid_ipv6(token):
                    continue
                if _is_whitelisted_ipv6(token):
                    continue

            elif category == "hostname":
                lower = token.lower()
                if lower in _HOSTNAME_WHITELIST:
                    continue
                if len(token) < 4:
                    continue

            tokens[category].add(token)


def _walk_and_extract(obj: object, tokens: dict[str, set[str]]) -> None:
    """Recursively walk a parsed YAML/JSON object and extract tokens from all string leaves."""
    if isinstance(obj, str):
        _extract_from_string(obj, tokens)
    elif isinstance(obj, dict):
        for v in obj.values():
            _walk_and_extract(v, tokens)
    elif isinstance(obj, (list, tuple)):
        for item in obj:
            _walk_and_extract(item, tokens)


def _empty_tokens() -> dict[str, list[str]]:
    return {cat: [] for cat in CATEGORY_REGEXES}


# ---------------------------------------------------------------------------
# Profile loading via load-profile.sh
# ---------------------------------------------------------------------------


def _load_profile(data_root: str, cid: str) -> dict:
    """Invoke load-profile.sh and return the parsed profile dict.

    load-profile.sh takes positional arguments: <data-root> <customer>.
    It emits JSON on stdout on success.
    On non-zero exit, raises SystemExit(2) with a guard-profile-load-failed message.
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))
    load_profile_sh = os.path.realpath(
        os.path.join(
            script_dir,
            "..",
            "..",
            "..",
            "..",
            "skills",
            "customer-profile",
            "scripts",
            "load-profile.sh",
        )
    )

    result = subprocess.run(
        ["bash", load_profile_sh, data_root, cid],
        capture_output=True,
        text=True,
        check=False,
    )

    if result.returncode != 0:
        stderr_excerpt = result.stderr[:200]
        print(
            f"yci guard: failed to load profile YAML for customer '{cid}'.",
            file=sys.stderr,
        )
        print(f"  data root: {data_root}", file=sys.stderr)
        print(f"  returncode: {result.returncode}", file=sys.stderr)
        print(f"  stderr: {stderr_excerpt}", file=sys.stderr)
        print(
            "Check the YAML via `/yci:whoami` or fix syntax.",
            file=sys.stderr,
        )
        sys.exit(2)

    return json.loads(result.stdout)


# ---------------------------------------------------------------------------
# Artifact roots
# ---------------------------------------------------------------------------


def _resolve_artifact_roots(profile: dict, data_root: str) -> list[str]:
    """Return realpath of each configured path that exists."""
    path_keys = [
        ("vaults", "path"),
        ("inventory", "path"),
        ("calendars", "path"),
        ("deliverable", "path"),
    ]
    roots: list[str] = []
    for section, key in path_keys:
        section_data = profile.get(section)
        if not isinstance(section_data, dict):
            continue
        raw_path = section_data.get(key)
        if not raw_path:
            continue
        # Resolve relative paths against data_root.
        if not os.path.isabs(raw_path):
            raw_path = os.path.join(data_root, raw_path)
        resolved = os.path.realpath(raw_path)
        if os.path.isdir(resolved):
            roots.append(resolved)
    return roots


# ---------------------------------------------------------------------------
# Inventory scan
# ---------------------------------------------------------------------------


def _collect_inventory_files(inv_dir: str) -> list[str]:
    """Walk inv_dir, return sorted list of .yaml/.yml/.json files (capped at MAX)."""
    collected: list[str] = []
    for dirpath, _dirnames, filenames in os.walk(inv_dir):
        for fname in filenames:
            lower = fname.lower()
            if lower.endswith((".yaml", ".yml", ".json")):
                collected.append(os.path.join(dirpath, fname))

    collected.sort()
    total = len(collected)
    if total > MAX_INVENTORY_FILES:
        print(
            f"truncated:inventory:{total}",
            file=sys.stderr,
        )
        collected = collected[:MAX_INVENTORY_FILES]
    return collected


def _scan_inventory(inv_dir: str, tokens: dict[str, set[str]]) -> None:
    """Parse every inventory file in inv_dir and extract tokens."""
    if not os.path.isdir(inv_dir):
        return

    files = _collect_inventory_files(inv_dir)
    for fpath in files:
        lower = fpath.lower()
        try:
            with open(fpath) as fh:
                if lower.endswith((".yaml", ".yml")):
                    data = yaml.safe_load(fh)
                else:
                    data = json.load(fh)
        except Exception as exc:
            print(
                f"warn: skipping unparseable inventory file {fpath}: {exc}",
                file=sys.stderr,
            )
            continue

        if data is not None:
            _walk_and_extract(data, tokens)


# ---------------------------------------------------------------------------
# Profile-level fingerprinting
# ---------------------------------------------------------------------------


def _extract_profile_tokens(profile: dict, tokens: dict[str, set[str]]) -> None:
    """Fingerprint well-known profile fields directly."""
    customer = profile.get("customer", {})
    engagement = profile.get("engagement", {})

    cid_val = customer.get("id")
    if cid_val:
        _extract_from_string(str(cid_val), tokens)

    display_name = customer.get("display_name")
    if display_name and display_name != cid_val:
        _extract_from_string(str(display_name), tokens)

    eng_id = engagement.get("id")
    if eng_id:
        _extract_from_string(str(eng_id), tokens)

    sow_ref = engagement.get("sow_ref")
    if sow_ref:
        _extract_from_string(str(sow_ref), tokens)


# ---------------------------------------------------------------------------
# mtime scanning (for cache invalidation only — no parse)
# ---------------------------------------------------------------------------


def _max_mtime_quick(inv_dir: str, profile_path: str) -> float:
    """Return max mtime across profile YAML and all inventory files (stat only)."""
    mtimes: list[float] = []
    try:
        mtimes.append(os.stat(profile_path).st_mtime)
    except OSError:
        pass

    if os.path.isdir(inv_dir):
        for dirpath, _dirnames, filenames in os.walk(inv_dir):
            for fname in filenames:
                lower = fname.lower()
                if lower.endswith((".yaml", ".yml", ".json")):
                    try:
                        mtimes.append(os.stat(os.path.join(dirpath, fname)).st_mtime)
                    except OSError:
                        pass

    return max(mtimes) if mtimes else 0.0


# ---------------------------------------------------------------------------
# Cache helpers
# ---------------------------------------------------------------------------


def _cache_path(data_root: str, cid: str) -> str:
    return os.path.join(data_root, ".cache", "customer-isolation", f"{cid}.json")


def _write_cache(cache_file: str, bundle: dict) -> None:
    """Atomically write bundle JSON to cache_file.  Warn on failure; never raise.

    Uses a unique temporary filename in the same directory (via tempfile.mkstemp)
    so concurrent writers can't clobber each other's in-flight .tmp files.
    """
    import tempfile

    cache_dir = os.path.dirname(cache_file)
    try:
        os.makedirs(cache_dir, exist_ok=True)
    except OSError as exc:
        print(f"warn: cache unwritable at {cache_dir}: {exc}", file=sys.stderr)
        return

    tmp_fd = -1
    tmp_path = ""
    try:
        tmp_fd, tmp_path = tempfile.mkstemp(
            prefix=f".{os.path.basename(cache_file)}.",
            suffix=".tmp",
            dir=cache_dir,
        )
        with os.fdopen(tmp_fd, "w") as fh:
            tmp_fd = -1  # fdopen now owns the fd; don't double-close below
            json.dump(bundle, fh, indent=2)
            fh.write("\n")
            fh.flush()
            try:
                os.fsync(fh.fileno())
            except OSError:
                # fsync is best-effort — e.g. on tmpfs or unsupported FS
                pass
        os.replace(tmp_path, cache_file)
        tmp_path = ""  # replaced, nothing to clean
    except OSError as exc:
        print(f"warn: cache unwritable at {cache_file}: {exc}", file=sys.stderr)
    finally:
        if tmp_fd >= 0:
            try:
                os.close(tmp_fd)
            except OSError:
                pass
        if tmp_path:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass


def _try_load_cache(
    cache_file: str,
    inv_dir: str,
    profile_path: str,
    no_cache: bool,
) -> dict | None:
    """Return cached bundle if valid and up to date, else None."""
    if no_cache:
        return None
    if not os.path.isfile(cache_file):
        return None
    try:
        with open(cache_file) as fh:
            cached = json.load(fh)
    except (OSError, json.JSONDecodeError):
        return None

    cached_mtime = cached.get("source_mtime_max")
    if not isinstance(cached_mtime, (int, float)):
        return None

    current_max = _max_mtime_quick(inv_dir, profile_path)
    if current_max <= cached_mtime:
        return cached
    return None


# ---------------------------------------------------------------------------
# Bundle builder
# ---------------------------------------------------------------------------


def _build_bundle(
    data_root: str,
    cid: str,
    profile: dict,
    inv_dir: str,
    profile_path: str,
) -> dict:
    """Build and return the full fingerprint bundle dict."""
    token_sets: dict[str, set[str]] = {cat: set() for cat in CATEGORY_REGEXES}

    # Fingerprint profile-level fields.
    _extract_profile_tokens(profile, token_sets)

    # Fingerprint inventory files.
    _scan_inventory(inv_dir, token_sets)

    # Artifact roots.
    artifact_roots = _resolve_artifact_roots(profile, data_root)

    # Max mtime.
    source_mtime_max = _max_mtime_quick(inv_dir, profile_path)

    # Normalise token sets → sorted lists.
    tokens_out: dict[str, list[str]] = {cat: sorted(token_sets[cat]) for cat in CATEGORY_REGEXES}

    generated_at = (
        datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    )

    return {
        "customer": cid,
        "artifact_roots": artifact_roots,
        "tokens": tokens_out,
        "generated_at": generated_at,
        "source_mtime_max": source_mtime_max,
    }


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build a customer fingerprint bundle JSON and print it to stdout.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--data-root",
        required=True,
        metavar="PATH",
        help="Resolved yci data root directory.",
    )
    parser.add_argument(
        "--customer",
        required=True,
        metavar="ID",
        help="Customer ID whose bundle to build.",
    )
    parser.add_argument(
        "--no-cache",
        action="store_true",
        default=False,
        help="Skip cache read; always rebuild and rewrite.",
    )

    args = parser.parse_args()
    data_root: str = os.path.realpath(args.data_root)
    cid: str = args.customer
    no_cache: bool = args.no_cache

    profile_path = os.path.join(data_root, "profiles", f"{cid}.yaml")
    cache_file = _cache_path(data_root, cid)

    # Load the profile via load-profile.sh to get the inventory path.
    # (We need it both for cache-check mtime and for full build.)
    profile = _load_profile(data_root, cid)

    inv_section = profile.get("inventory", {})
    raw_inv_path = inv_section.get("path", "") if isinstance(inv_section, dict) else ""
    if raw_inv_path and not os.path.isabs(raw_inv_path):
        raw_inv_path = os.path.join(data_root, raw_inv_path)
    inv_dir = os.path.realpath(raw_inv_path) if raw_inv_path else ""

    # Cache check.
    cached = _try_load_cache(cache_file, inv_dir, profile_path, no_cache)
    if cached is not None:
        print(json.dumps(cached, indent=2))
        return

    # Full build.
    bundle = _build_bundle(data_root, cid, profile, inv_dir, profile_path)

    # Write cache (atomic, warn on failure).
    _write_cache(cache_file, bundle)

    print(json.dumps(bundle, indent=2))


if __name__ == "__main__":
    main()
