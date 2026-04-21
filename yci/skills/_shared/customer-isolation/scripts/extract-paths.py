#!/usr/bin/env python3
"""extract-paths.py — yci customer-isolation path extractor.

Reads a PreToolUse JSON payload (from argv[1] as a path, or stdin when no argv)
and prints candidate absolute paths, one per line, on stdout. Always exits 0.
Used by `yci/skills/_shared/customer-isolation/detect.sh`.
"""

import json
import os
import os.path
import re
import shlex
import sys
import urllib.parse

# Regex for scanning path-like tokens in Task.prompt and unknown-tool fallback.
PATH_HINT_RE = re.compile(r"(?:^|\s)([~./][\w./@-]{2,})")

# Regex to identify path-looking tokens from Bash command splits.
# A token looks like a path if it starts with /, ~/, ./, ../, or contains a /
# with at least one alphanumeric on each side of at least one slash.
_PATH_START_RE = re.compile(r"^(?:/|~/|\.{1,2}/)")
_PATH_SLASH_RE = re.compile(r"[a-zA-Z0-9][/][a-zA-Z0-9]")


def _looks_like_path(token: str) -> bool:
    """Return True if the token looks like a filesystem path."""
    if _PATH_START_RE.match(token):
        return True
    if "/" in token and _PATH_SLASH_RE.search(token):
        return True
    return False


def _canonicalize(candidate: str, cwd: str) -> str:
    """Expand, resolve against cwd if relative, then realpath or abspath."""
    # Expand ~ only when $HOME is set.
    if "~" in candidate and os.environ.get("HOME"):
        candidate = os.path.expanduser(candidate)

    if not os.path.isabs(candidate):
        base = cwd if cwd else os.getcwd()
        candidate = os.path.join(base, candidate)

    if os.path.lexists(candidate):
        return os.path.realpath(candidate)
    return os.path.abspath(candidate)


def _emit(paths: "dict[str, None]", candidate: str, cwd: str) -> None:
    """Canonicalize candidate and add to dedup dict if non-empty."""
    if not candidate or not candidate.strip():
        return
    resolved = _canonicalize(candidate.strip(), cwd)
    if resolved:
        paths[resolved] = None


def _extract_from_bash(command: str, cwd: str, paths: "dict[str, None]") -> None:
    """Split a Bash command string and extract path-looking tokens."""
    try:
        tokens = shlex.split(command, posix=True)
    except ValueError:
        print("truncated:paths:shlex-error", file=sys.stderr)
        tokens = re.split(r"\s+", command)

    actual_count = len(tokens)
    if actual_count > 512:
        print(f"truncated:paths:{actual_count}", file=sys.stderr)
        tokens = tokens[:512]

    for token in tokens:
        if _looks_like_path(token):
            _emit(paths, token, cwd)


def _scan_for_path_hints(text: str, cwd: str, paths: "dict[str, None]") -> None:
    """Scan free-form text for path-like tokens using PATH_HINT_RE."""
    for match in PATH_HINT_RE.finditer(text):
        _emit(paths, match.group(1), cwd)


def _extract_from_tool_input(tool_name: str, tool_input: dict, cwd: str, paths: "dict[str, None]") -> None:
    """Dispatch per tool_name to extract candidate paths from tool_input."""
    if tool_name in ("Read", "Write", "Edit", "MultiEdit"):
        fp = tool_input.get("file_path")
        if fp and isinstance(fp, str):
            _emit(paths, fp, cwd)

    elif tool_name == "NotebookEdit":
        np = tool_input.get("notebook_path")
        if np and isinstance(np, str):
            _emit(paths, np, cwd)

    elif tool_name in ("Glob", "Grep"):
        p = tool_input.get("path")
        if p and isinstance(p, str):
            _emit(paths, p, cwd)

    elif tool_name == "Bash":
        cmd = tool_input.get("command")
        if cmd and isinstance(cmd, str):
            _extract_from_bash(cmd, cwd, paths)

    elif tool_name == "WebFetch":
        url = tool_input.get("url")
        if url and isinstance(url, str):
            parsed = urllib.parse.urlparse(url)
            if parsed.scheme == "file":
                _emit(paths, urllib.parse.unquote(parsed.path), cwd)

    elif tool_name == "Task":
        prompt = tool_input.get("prompt")
        if prompt and isinstance(prompt, str):
            _scan_for_path_hints(prompt, cwd, paths)

    else:
        # Unknown tool — scan all string values in tool_input.
        for value in tool_input.values():
            if isinstance(value, str):
                _scan_for_path_hints(value, cwd, paths)


def main() -> None:
    # Read input: argv[1] as file path if provided and readable, else stdin.
    raw: str
    if len(sys.argv) > 1:
        arg_path = sys.argv[1]
        try:
            with open(arg_path, encoding="utf-8") as fh:
                raw = fh.read()
        except OSError:
            # Fall back to stdin if the path is not readable.
            raw = sys.stdin.read()
    else:
        raw = sys.stdin.read()

    try:
        payload = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        print("truncated:paths:invalid-json", file=sys.stderr)
        return

    if not isinstance(payload, dict):
        return

    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return

    tool_name: str = payload.get("tool_name", "")
    cwd: str = payload.get("cwd", "") or ""
    if not isinstance(cwd, str):
        cwd = ""

    # Use order-preserving dict for deduplication.
    paths: dict[str, None] = {}
    _extract_from_tool_input(tool_name, tool_input, cwd, paths)

    for path in paths:
        print(path)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        # Never raise past the top level — always exit 0 so an unexpected
        # crash can't take down the whole PreToolUse hook. Emit a recognizable
        # marker on stderr so callers can still tell something went wrong.
        print(f"truncated:paths:internal-error:{exc!r}", file=sys.stderr)
    sys.exit(0)
