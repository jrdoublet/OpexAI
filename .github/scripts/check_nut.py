#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate Squirrel (.nut) files for OpexAI CI (stdlib only).

Checks:
  1. Pure ASCII encoding and SPDX-License-Identifier: GPL-3.0-or-later header.
  2. Balanced (), [], and {} delimiters while ignoring strings and comments.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

SPDX_RE = re.compile(r"^\s*//\s*SPDX-License-Identifier:\s*GPL-3\.0-or-later\s*$")
OPEN_TO_CLOSE = {"(": ")", "[": "]", "{": "}"}
CLOSE_CHARS = {")", "]", "}"}


def iter_nut_files(root: Path) -> list[Path]:
    if root.is_file():
        return [root]
    return sorted(root.rglob("*.nut"))


def check_ascii_and_spdx(path: Path) -> list[str]:
    errors: list[str] = []
    raw = path.read_bytes()
    try:
        text = raw.decode("ascii")
    except UnicodeDecodeError as exc:
        line = raw[: exc.start].count(b"\n") + 1
        errors.append(
            f"{path}:{line}: non-ASCII byte 0x{raw[exc.start]:02x} at offset {exc.start}"
        )
        return errors

    if not any(SPDX_RE.match(line) for line in text.splitlines()):
        errors.append(f"{path}: missing 'SPDX-License-Identifier: GPL-3.0-or-later' header")

    return errors


def check_brackets(path: Path) -> list[str]:
    """Check (), [], {} balance in a Squirrel file, ignoring strings and comments."""
    errors: list[str] = []
    text = path.read_bytes().decode("latin-1")
    n = len(text)
    i = 0
    line = 1
    col = 1
    stack: list[tuple[str, int, int]] = []

    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""

        # Line comment: // ... or # ...
        if (ch == "/" and nxt == "/") or ch == "#":
            i += 2 if ch == "/" else 1
            col += 2 if ch == "/" else 1
            while i < n and text[i] != "\n":
                i += 1
                col += 1
            continue

        # Block comment: /* ... */
        if ch == "/" and nxt == "*":
            start_line, start_col = line, col
            i += 2
            col += 2
            closed = False
            while i < n:
                if text[i] == "*" and i + 1 < n and text[i + 1] == "/":
                    i += 2
                    col += 2
                    closed = True
                    break
                if text[i] == "\n":
                    line += 1
                    col = 1
                else:
                    col += 1
                i += 1
            if not closed:
                errors.append(f"{path}:{start_line}:{start_col}: unclosed block comment")
            continue

        # Squirrel verbatim string: @"..." with "" as escaped quote
        if ch == "@" and nxt == '"':
            start_line, start_col = line, col
            i += 2
            col += 2
            closed = False
            while i < n:
                if text[i] == '"':
                    if i + 1 < n and text[i + 1] == '"':
                        i += 2
                        col += 2
                        continue
                    i += 1
                    col += 1
                    closed = True
                    break
                if text[i] == "\n":
                    line += 1
                    col = 1
                else:
                    col += 1
                i += 1
            if not closed:
                errors.append(f"{path}:{start_line}:{start_col}: unclosed verbatim string")
            continue

        # Standard double-quoted string or single-quoted char literal
        if ch in ('"', "'"):
            quote = ch
            start_line, start_col = line, col
            i += 1
            col += 1
            closed = False
            while i < n:
                c = text[i]
                if c == "\\":
                    if i + 1 < n:
                        if text[i + 1] == "\n":
                            line += 1
                            col = 1
                        else:
                            col += 2
                        i += 2
                        continue
                    i += 1
                    col += 1
                    break
                if c == quote:
                    i += 1
                    col += 1
                    closed = True
                    break
                if c == "\n":
                    # Unescaped newline ends a non-verbatim string/char literal
                    break
                i += 1
                col += 1
            if not closed:
                kind = "string" if quote == '"' else "char literal"
                errors.append(f"{path}:{start_line}:{start_col}: unclosed {kind}")
            continue

        if ch in OPEN_TO_CLOSE:
            stack.append((ch, line, col))
        elif ch in CLOSE_CHARS:
            if not stack:
                errors.append(f"{path}:{line}:{col}: unexpected closing '{ch}'")
            else:
                open_ch, open_line, open_col = stack.pop()
                expected = OPEN_TO_CLOSE[open_ch]
                if ch != expected:
                    errors.append(
                        f"{path}:{line}:{col}: mismatched '{ch}' "
                        f"(expected '{expected}' for '{open_ch}' opened at {open_line}:{open_col})"
                    )

        if ch == "\n":
            line += 1
            col = 1
        else:
            col += 1
        i += 1

    for open_ch, open_line, open_col in stack:
        errors.append(f"{path}:{open_line}:{open_col}: unclosed '{open_ch}'")

    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate OpexAI Squirrel (.nut) files.")
    parser.add_argument(
        "root",
        nargs="?",
        default="ai/OpexAI",
        help="Directory or .nut file to scan (default: ai/OpexAI)",
    )
    parser.add_argument(
        "--ascii-spdx",
        action="store_true",
        help="Check pure ASCII encoding and SPDX-License-Identifier header",
    )
    parser.add_argument(
        "--brackets",
        action="store_true",
        help="Check (), [], {} balance ignoring strings and comments",
    )
    args = parser.parse_args(argv)

    run_ascii = args.ascii_spdx or not args.brackets
    run_brackets = args.brackets or not args.ascii_spdx

    root = Path(args.root)
    files = iter_nut_files(root)
    if not files:
        print(f"ERROR: no .nut files found under {root}", file=sys.stderr)
        return 1

    all_errors: list[str] = []
    for path in files:
        if run_ascii:
            all_errors.extend(check_ascii_and_spdx(path))
        if run_brackets:
            all_errors.extend(check_brackets(path))

    if all_errors:
        for err in all_errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1

    checks = []
    if run_ascii:
        checks.append("ASCII+SPDX")
    if run_brackets:
        checks.append("brackets")
    print(f"OK: {len(files)} .nut files passed ({', '.join(checks)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
