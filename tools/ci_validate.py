#!/usr/bin/env python3
"""PUB-42 package gate for the public tree (stdlib only).

Builds the deterministic archive with tools/package_opexai.py, then checks
that info.nut and main.nut are present, GetVersion() is a positive integer,
every .nut is pure ASCII, carries an SPDX license identifier, and has
balanced delimiters.

OpenTTD embeds its own Squirrel. A standalone compiler is not a valid gate:
it cannot resolve require() or the game API, and it is not installed here.
The static check below is comment- and string-aware balance of () [] {},
plus unclosed strings, unclosed block comments and NUL bytes. The headless
smoke compiles the AI with the engine.

On the laboratory tree the schema generator is present and the public
profile is produced into the archive. On the public tree the generator is
absent and the sources are already the public profile (--already-public).

--prove-leak-scan writes a personal path into a temporary tree and requires
tools/leak_scan.py to reject it. That path is assembled at runtime so this
file stays clean under its own scan.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

if __package__:
    from . import package_opexai
else:
    import package_opexai


ROOT = Path(__file__).resolve().parents[1]
SPDX_MARK = "SPDX-License-Identifier:"


def check_squirrel_syntax(text: str) -> list[str]:
    """Return syntax problems for one Squirrel source.

    Strings use double quotes with backslash escapes. Comments are // and
    non-nesting /* */. Braces inside either do not count. This is not a
    statement parser.
    """
    errors: list[str] = []
    if "\x00" in text:
        errors.append("NUL byte")
    line = 1
    index = 0
    length = len(text)
    mode = "code"
    stack: list[tuple[str, int]] = []
    pairs = {")": "(", "]": "[", "}": "{"}
    while index < length:
        char = text[index]
        nxt = text[index + 1] if index + 1 < length else ""
        if char == "\n":
            line += 1
            if mode == "line":
                mode = "code"
            index += 1
            continue
        if mode == "line":
            index += 1
            continue
        if mode == "block":
            if char == "*" and nxt == "/":
                mode = "code"
                index += 2
                continue
            index += 1
            continue
        if mode == "string":
            if char == "\\":
                if index + 1 < length and text[index + 1] == "\n":
                    line += 1
                index += 2
                continue
            if char == '"':
                mode = "code"
            index += 1
            continue
        if char == "/" and nxt == "/":
            mode = "line"
            index += 2
            continue
        if char == "/" and nxt == "*":
            mode = "block"
            index += 2
            continue
        if char == '"':
            mode = "string"
            index += 1
            continue
        if char in "([{":
            stack.append((char, line))
        elif char in pairs:
            if not stack or stack[-1][0] != pairs[char]:
                errors.append(f"unmatched {char} at line {line}")
            else:
                stack.pop()
        index += 1
    if mode == "string":
        errors.append("unclosed string")
    if mode == "block":
        errors.append("unclosed block comment")
    for opener, opened in stack:
        errors.append(f"unclosed {opener} from line {opened}")
    return errors


def check_nut_bytes(name: str, data: bytes) -> list[str]:
    """ASCII, SPDX and delimiter checks for one archived .nut."""
    errors: list[str] = []
    if any(byte >= 0x80 for byte in data):
        errors.append(f"{name}: non-ASCII byte")
    if b"\x00" in data:
        errors.append(f"{name}: NUL byte")
    try:
        text = data.decode("ascii")
    except UnicodeDecodeError:
        return errors or [f"{name}: not ASCII"]
    if SPDX_MARK not in text:
        errors.append(f"{name}: missing {SPDX_MARK}")
    for problem in check_squirrel_syntax(text):
        errors.append(f"{name}: {problem}")
    return errors


def inspect_tar(tar_path: Path) -> list[str]:
    """Check the archive members the package gate must see."""
    errors: list[str] = []
    info_text: str | None = None
    saw_main = False
    with tarfile.open(tar_path, "r:") as archive:
        for member in archive.getmembers():
            if not member.isfile() or not member.name.endswith(".nut"):
                continue
            extracted = archive.extractfile(member)
            if extracted is None:
                errors.append(f"{member.name}: unreadable archive member")
                continue
            data = extracted.read()
            errors.extend(check_nut_bytes(member.name, data))
            if member.name == "info.nut" or member.name.endswith("/info.nut"):
                info_text = data.decode("ascii", errors="replace")
            if member.name == "main.nut" or member.name.endswith("/main.nut"):
                saw_main = True
    if info_text is None:
        errors.append("Archive is missing info.nut")
    else:
        version = package_opexai.parse_info_nut(info_text).get("version")
        if not isinstance(version, int) or version < 1:
            errors.append(f"GetVersion() must be a positive int, got {version!r}")
    if not saw_main:
        errors.append("Archive is missing main.nut")
    return errors


def uses_public_profile(repo_root: Path, forced: bool) -> bool:
    """True when the tree has no schema generator, or the flag forces it."""
    if forced:
        return True
    return not (repo_root / "src" / "opexai_schema.py").is_file()


def validate_archive(repo_root: Path, *, already_public: bool) -> int:
    """Build the archive in a temporary directory and run the extra checks."""
    with tempfile.TemporaryDirectory(prefix="opexai-ci-pkg-") as tmp:
        try:
            result = package_opexai.package_opexai(
                out=Path(tmp),
                repo_root=repo_root,
                ai_dir=repo_root / "ai" / "OpexAI",
                schema_script=repo_root / "src" / "opexai_schema.py",
                already_public=already_public,
            )
        except (package_opexai.PackageValidationError, ValueError, FileNotFoundError, RuntimeError) as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1
        errors = inspect_tar(result["tar_path"])
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    mode = "already-public" if already_public else "generated-profile"
    print(
        f"Package ok mode={mode} version={result['version']} "
        f"files={result['file_count']} md5={result['md5']}"
    )
    return 0


def prove_leak_scan() -> int:
    """Return 0 only when the scanner rejects a planted personal path."""
    needle = "".join(("/", "home", "/ci-probe"))
    script = Path(__file__).resolve().parent / "leak_scan.py"
    with tempfile.TemporaryDirectory(prefix="opexai-leak-") as tmp:
        root = Path(tmp)
        (root / "note.txt").write_text("see " + needle + "\n", encoding="ascii")
        proc = subprocess.run(
            [sys.executable, str(script), str(root)],
            capture_output=True,
            text=True,
            check=False,
        )
    if proc.returncode != 1 or "home-path" not in proc.stdout:
        print("Leak scan did not fail on a planted personal path", file=sys.stderr)
        return 1
    print("Planted leak rejected (home-path).")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--prove-leak-scan",
        action="store_true",
        help="Require the leak scanner to fail on a planted personal path, then exit",
    )
    parser.add_argument(
        "--already-public",
        action="store_true",
        help="Force the public-profile path (skip the schema generator)",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=ROOT,
        help=argparse.SUPPRESS,
    )
    args = parser.parse_args(argv)
    if args.prove_leak_scan:
        return prove_leak_scan()
    repo_root = args.repo_root.resolve()
    already = uses_public_profile(repo_root, args.already_public)
    return validate_archive(repo_root, already_public=already)


if __name__ == "__main__":
    raise SystemExit(main())
