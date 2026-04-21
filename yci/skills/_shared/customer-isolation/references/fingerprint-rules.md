# Fingerprint Rules

This document is the authoritative specification for what constitutes a
cross-customer identifier ("fingerprint") in `yci`. The customer-guard hook and
associated extraction scripts derive their behavior from these rules. When a rule
here and a script diverge, the script is wrong.

---

## What counts as a fingerprint

A fingerprint is any token that, if it appeared in a commit, diff, or deliverable
artifact belonging to customer A, would reveal information about customer B. The
following categories are load-bearing:

- **Customer identity**: `customer.id` and `customer.display_name` fields from a
  loaded profile YAML. Even a display name fragment (e.g., a partial company name)
  counts if it is unique enough to identify the customer.

- **Engagement metadata**: `engagement.id` and `engagement.sow_ref` from the
  profile. SOW references are especially sensitive — they appear in billing records
  and contracts.

- **Inventory-extracted identifiers**: hostnames, IPv4 addresses, IPv6 addresses,
  AS numbers, and device serial numbers pulled from every `*.yaml`, `*.yml`, and
  `*.json` file found under the profile's `inventory.path`. The inventory is the
  primary source of device-level fingerprints and is re-scanned on each guard run.

- **Path prefixes**: the canonical `realpath` of each of the four profile-level
  path overrides — `vaults.path`, `inventory.path`, `calendars.path`, and
  `deliverable.path`. If these paths contain the customer name or engagement ID
  (e.g., `~/Dropbox-Acme/deliverables/`), the path itself is a fingerprint. Each
  path is realpath-resolved before comparison to prevent symlink bypasses.

- **Credential references**: `credential_ref` strings such as
  `vault:acme/prod/db-password` or `secret:customerX/api-key`. These are
  placeholder pointers — the secrets they reference are never present in the
  repository — but the pointer tokens identify the customer's credential namespace
  and are therefore fingerprints in their own right.

---

## Generic-token whitelist

The following tokens are explicitly whitelisted and never treated as fingerprints,
regardless of which customer's inventory or profile contains them:

| Token / Range                               | Rationale                                                                       |
| ------------------------------------------- | ------------------------------------------------------------------------------- |
| `127.0.0.0/8`                               | IPv4 loopback — universal                                                       |
| `::1`                                       | IPv6 loopback — universal                                                       |
| `0.0.0.0`                                   | Unspecified address — universal                                                 |
| `localhost`                                 | Hostname alias for loopback — universal                                         |
| `example.com`, `example.net`, `example.org` | IANA reserved example domains (RFC 2606) — ubiquitous in docs and test fixtures |
| `192.0.2.0/24`                              | RFC 5737 documentation range — TEST-NET-1                                       |
| `198.51.100.0/24`                           | RFC 5737 documentation range — TEST-NET-2                                       |
| `203.0.113.0/24`                            | RFC 5737 documentation range — TEST-NET-3                                       |
| `2001:db8::/32`                             | RFC 3849 documentation range — IPv6 doc prefix                                  |

**Rationale**: every test fixture, README example, and lab scaffold in this
repository (and in the wider ecosystem) references these tokens. Without
whitelisting them, the guard produces constant false positives on unrelated commits
and loses operator trust. Adding a new whitelist entry requires a comment here and
a corresponding update to the whitelist constant in both `extract-tokens.py` and
`inventory-fingerprint.py`.

---

## Minimum matching criteria

Not every string that resembles a fingerprint category should trigger a guard
denial. The following floors apply before a candidate token is promoted to
fingerprint status:

- **Hostnames**: must be at least 4 characters long AND match the `hostname` regex
  in [§ Category regexes](#category-regexes) below, OR appear verbatim in an
  inventory file associated with the current or a different customer. Bare
  filesystem tokens like `file.txt` WILL match the regex (it is intentionally
  structural and loose); downstream enforcement happens in extractor-side
  post-filtering — the last label must contain at least one letter (so pure-digit
  labels that look like truncated IPs don't match) and the token must not be in
  `WHITELISTED_HOSTNAMES`. See `_is_valid_hostname()` in `extract-tokens.py`.

- **IPv4 / IPv6**: must pass CIDR validation via Python `ipaddress.ip_address()`
  after the regex match. The literal string `10.0.0.1` inside a shell command is a
  fingerprint; the fragment `10.0` is not (it does not parse as a valid IP address).

- **AS numbers**: must match `^AS\d+$` (case-insensitive). Bare integers or
  partial strings like `AS` alone do not qualify.

- **SOW references**: must match the default regex `sow[-/ ]\d+`
  (case-insensitive). Customers may declare a per-profile override via
  `engagement.sow_ref_pattern`; when present, only the profile-specific pattern
  applies for that customer's artifacts. The default pattern applies for all
  profiles that do not declare an override.

- **Customer IDs (raw strings)**: must match `^[a-z0-9][a-z0-9-]{2,63}$` AND
  equal the `customer.id` of at least one loaded profile other than the currently
  active one to trigger a cross-customer collision. Matching the shape alone is
  insufficient; there must be an actual profile ID match.

---

## Category regexes

The following named regexes are defined per category. Each is written as a Python
raw string. The guard scripts compile these once at module level; do not repeat the
compilation inline. Each regex covers the detection pass — downstream validation
(e.g., `ipaddress.ip_address()`, profile-id lookup) handles false-positive
reduction.

- **`ipv4`**:

  ```
  \b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b
  ```

  Matches well-formed dotted-quad IPv4 addresses. CIDR/address validation happens
  downstream via `ipaddress.ip_address()` to filter partial matches.

- **`ipv6`**:

  ```
  \b(?:[A-Fa-f0-9]{1,4}:){2,7}[A-Fa-f0-9]{1,4}\b|::1
  ```

  The greedy grouped form covers both compressed and canonical representations;
  `::1` is the loopback special-case. `ipaddress.ip_address()` filters edge-case
  false positives (e.g., hex strings that happen to look like IPv6 segments).

- **`hostname`**:

  ```
  \b[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+\b
  ```

  Requires at least one dot with a TLD-ish last label and a per-label length floor.
  This combination filters bare tokens like `file.txt` — the last label `txt`
  passes but bare single-extension filenames without a second label do not produce
  a multi-label match. Apply case-insensitively.

- **`asn`**:

  ```
  \bAS\d+\b
  ```

  Case-insensitive. Matches `AS64496` and `as12345`. Bare integers are not matched.

- **`sow-ref`**:

  ```
  \bSOW[-/ ]\d+\b
  ```

  Case-insensitive. This is the default pattern. Individual profiles may declare
  `engagement.sow_ref_pattern` to replace it for their artifacts.

- **`credential-ref`**:

  ```
  \b(?:vault|secret|kms):[\w./-]+\b
  ```

  Covers `vault:acme/prod/db`, `secret:customerX/key`, and
  `kms:arn:aws:kms:us-east-1:123456789012:key/...`. The prefix anchors the token
  to a secrets-backend namespace, distinguishing it from arbitrary path strings.

- **`customer-id`**:

  ```
  \b[a-z0-9][a-z0-9-]{2,63}\b
  ```

  Matches raw customer-ID-shaped tokens. Because this pattern is intentionally
  broad, matches are deduplicated against actual `customer.id` values from loaded
  profiles before a collision is reported. A match that does not equal a known
  profile ID is discarded.

---

## Adding a new category

To add a new fingerprint category, follow these steps in order — skipping any step
or doing them out of order risks the guard silently not enforcing the new rule, or
enforcing it inconsistently across detection paths:

1. **Add the category and regex here first.** This document is the specification.
   Define the category name, the Python raw-string regex, the minimum matching
   criteria (length floor, downstream validation, whitelist interaction), and a
   one-sentence rationale. Get a review before proceeding — once scripts depend on
   it, rollback is more expensive.

2. **Add the regex to both `extract-tokens.py` and `inventory-fingerprint.py`.**
   These are intentionally standalone scripts (no shared import layer), so the
   regex must be duplicated. Keep the two copies byte-identical; a diff between
   them is a defect. Compile the pattern once at module level with
   `re.compile(pattern, re.IGNORECASE)` (or without `re.IGNORECASE` if the
   category is case-sensitive). Do not inline the compile call inside a loop.

3. **Add a unit test in
   `yci/skills/_shared/customer-isolation/tests/test_extract_tokens.sh`.**
   The test must cover at least one positive match (a token that should be detected
   as a fingerprint) and one whitelist-bypass case (a token that resembles the
   category but should be suppressed). Both cases must assert the correct exit code
   and output.

4. **Add a corresponding entry in
   `yci/hooks/customer-guard/references/error-messages.md`** only if the new
   category surfaces a distinct deny-reason that operators need to act on
   differently from existing categories. Most new categories reuse the existing
   `guard-fingerprint-collision` error code and add a `category:` field value in
   the structured output — a new top-level error code is warranted only when the
   remediation path differs materially (e.g., a new category that requires a
   different sign-off workflow).

> **Gotcha — false-positive rate is load-bearing.** Fingerprint rules determine
> how often operators see guard denials on legitimate commits. Err toward
> under-matching on generic-token edges (bare IPv4 literals, single-label
> hostnames, short alphanumeric strings) rather than over-matching. The PRD
> prioritizes "clear actionable error" over "zero leaks at any operational cost" —
> subsequent passes can tighten the rules once the false-positive rate is measured
> in practice. A guard that fires on every `127.0.0.1` in a test config teaches
> operators to bypass it.
