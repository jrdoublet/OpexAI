#!/usr/bin/env python3
"""PUB-11 publication guard (stdlib only, no network or Git operations).

Usage: python3 tools/leak_scan.py TREE [--exceptions reviewed.json]
Exit 0 means no findings, 1 means findings, 2 means invalid input/configuration.
Exceptions default to an empty list. JSON entries require exact relative ``path``,
``rule``, matched ``value`` and a nonempty review ``reason``; no glob exemptions.
Only the explicit noreply address forms below are automatically allowed.
This is a heuristic guard, not a proof of absence of secrets. Compressed/encrypted
payloads are not decompressed; publication snapshots should contain source/text.
"""

from __future__ import annotations

import argparse
import base64
import binascii
from dataclasses import dataclass
import ipaddress
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    rule: str


def _c(*parts):
    """Join text so this source does not contain the needles it searches for."""
    return "".join(parts)


def _dots(*parts):
    return ".".join(parts)


def _colons(*parts):
    return ":".join(parts)


# Needles are concatenated. A literal home directory, loopback name or private
# network in this file would be reported when the public tree scans itself.
_HOME = _c("/", "home", "/")
_LOOP = _c("local", "host")
_BOX = _c("BH", "6001")

PATTERNS = {
    "secret": re.compile(
        r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|"
        r"sk-(?:proj-|ant-)?[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16}|"
        r"ASIA[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|"
        r"eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)\b"
        r"|-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----"
        r"|(?i:\b(?:api[_-]?key|access[_-]?token|auth[_-]?token|secret|"
        r"password|passwd|client[_-]?secret)\b[\"']?\s*[:=]\s*[\"']"
        r"[^\"'\r\n]{4,}[\"'])"
        r"|(?i:\b(?:api[_-]?key|access[_-]?token|auth[_-]?token|token|"
        r"secret|secret[_-]?key|password|passwd|client[_-]?secret)\b\s*[:=]\s*"
        r"[A-Za-z0-9_+/.-]{12,}(?:={0,2})(?=[\s,;#]|$))"
        r"|(?i:\bbearer\s+[A-Za-z0-9+/_.=-]{12,})"
        r"|(?i:\bbasic\s+[A-Za-z0-9+/=]{8,})"
    ),
    "home-path": re.compile(
        _HOME + r"(?:[^\s\"'<>]+)?|(?i:[a-z]:[\\/]+Users(?:[\\/]+[^\s\"'<>]*)?)"
    ),
    "email": re.compile(r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}"),
    "private-ip": re.compile(r"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])|(?<![\w:])(?:[0-9a-fA-F]{0,4}:){2,}[0-9a-fA-F:.]*(?:%[\w.-]+)?"),
    "internal-hostname": re.compile(
        r"(?i:\b(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+"
        r"(?:internal|intranet|local|lan|corp|" + _LOOP + r")\b|\b" + _LOOP
        + r"\b|\b" + _BOX + r"\b)"
        r"|(?i:(?<=://)[a-z][a-z0-9-]*(?=[:/\s]|$))"
    ),
}

PRIVATE_NETWORKS = tuple(ipaddress.ip_network(value) for value in (
    _dots("10", "0", "0", "0") + "/8",
    _dots("172", "16", "0", "0") + "/12",
    _dots("192", "168", "0", "0") + "/16",
    _dots("127", "0", "0", "0") + "/8",
    _dots("169", "254", "0", "0") + "/16",
    _colons("fc00", "", "") + "/7",
    _colons("fe80", "", "") + "/10",
    _colons("", "", "1") + "/128",
))


def _noreply(value):
    local, domain = value.lower().rsplit("@", 1)
    return local in ("noreply", "no-reply") or domain == "users.noreply.github.com"


def _matches(text):
    for rule, pattern in PATTERNS.items():
        for match in pattern.finditer(text):
            value = match.group()
            if rule == "secret" and value.lower().startswith("basic"):
                try:
                    credential = base64.b64decode(value.split()[1], validate=True)
                except (ValueError, binascii.Error):
                    continue
                if b":" not in credential:
                    continue
            if rule == "email" and _noreply(value):
                continue
            if rule == "private-ip":
                try:
                    address = ipaddress.ip_address(value.split("%", 1)[0])
                except ValueError:
                    continue
                if isinstance(address, ipaddress.IPv6Address) and address.ipv4_mapped:
                    address = address.ipv4_mapped
                if not any(address.version == network.version and address in network
                           for network in PRIVATE_NETWORKS):
                    continue
            yield rule, match


def _validate_exceptions(entries):
    if not isinstance(entries, (list, tuple)):
        raise ValueError("Exceptions must be a JSON list")
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != {"path", "rule", "value", "reason"}:
            raise ValueError("Each exception requires path, rule, value and reason")
        if any(not isinstance(value, str) or not value.strip() for value in entry.values()):
            raise ValueError("Exception fields must be nonempty strings")
        path = entry["path"]
        if (PurePosixPath(path).is_absolute() or ".." in PurePosixPath(path).parts
                or "\\" in path or any(char in path for char in "*?[]")
                or PurePosixPath(path).as_posix() != path):
            raise ValueError("Exception path must be an exact relative POSIX path")
        if entry["rule"] not in PATTERNS:
            raise ValueError("Unknown exception rule")
    return entries


def load_exceptions(path):
    """Read a deliberately explicit, reviewed allowlist; no built-in exemptions."""
    return _validate_exceptions(json.loads(Path(path).read_text(encoding="utf-8")))


# Version-control metadata is not publication content. A checkout still has it,
# and packed objects false-match a text scan. Directory names only; a regular
# file with the same name is still scanned.
SKIP_DIR_NAMES = frozenset({".git", ".hg", ".svn"})


def scan_tree(root, exceptions=()):
    """Scan filenames and every regular file, without following symlinks.

    Line 0 denotes a filename or a filesystem finding. Read errors, symlinks and
    special files are findings and cannot be suppressed by content exceptions.
    Byte-oriented decoding retains ASCII embedded in otherwise binary files;
    BOM-marked UTF-16/32 text is additionally decoded for those encodings.
    """
    exceptions = _validate_exceptions(exceptions)
    allowed = {(entry["path"], entry["rule"], entry["value"]) for entry in exceptions}
    root = Path(root)
    if root.is_symlink() or not root.is_dir():
        raise ValueError("Scan root must be an existing directory, not a symlink")
    findings = set()

    def inspect(text, relative, filename=False):
        for rule, match in _matches(text):
            if (relative, rule, match.group()) not in allowed:
                line = 0 if filename else text.count("\n", 0, match.start()) + 1
                findings.add(Finding(relative, line, rule))

    def walk_error(error):
        try:
            relative = Path(error.filename).relative_to(root).as_posix()
        except (TypeError, ValueError):
            relative = "."
        findings.add(Finding(relative, 0, "read-error"))

    for directory, dirs, files in os.walk(root, followlinks=False, onerror=walk_error):
        dirs[:] = sorted(name for name in dirs if name not in SKIP_DIR_NAMES)
        for name in dirs + sorted(files):
            path = Path(directory) / name
            relative = path.relative_to(root).as_posix()
            inspect(relative, relative, filename=True)
            try:
                mode = path.lstat().st_mode
                if stat.S_ISLNK(mode):
                    findings.add(Finding(relative, 0, "symlink"))
                    continue
                if stat.S_ISDIR(mode):
                    continue
                if not stat.S_ISREG(mode):
                    findings.add(Finding(relative, 0, "special-file"))
                    continue
                data = path.read_bytes()
                if data.startswith((b"\xff\xfe\x00\x00", b"\x00\x00\xfe\xff")):
                    inspect(data.decode("utf-32", errors="replace"), relative)
                elif data.startswith((b"\xff\xfe", b"\xfe\xff")):
                    inspect(data.decode("utf-16", errors="replace"), relative)
                else:
                    inspect(data.decode("utf-8", errors="replace"), relative)
            except OSError:
                findings.add(Finding(relative, 0, "read-error"))
    return sorted(findings, key=lambda finding: (finding.path, finding.line, finding.rule))


def print_findings(findings):
    """Do not print matched values, even if a filename contains one."""
    for finding in findings:
        path = finding.path
        spans = sorted((match.start(), match.end()) for _, match in _matches(path))
        # Replacing right to left also safely redacts overlapping match spans.
        merged = []
        for start, end in spans:
            if merged and start <= merged[-1][1]:
                merged[-1] = (merged[-1][0], max(end, merged[-1][1]))
            else:
                merged.append((start, end))
        for start, end in reversed(merged):
            path = path[:start] + "[redacted]" + path[end:]
        print(f"{json.dumps(path, ensure_ascii=True)}:{finding.line}: {finding.rule}")
    print(f"{len(findings)} finding(s)")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tree", type=Path)
    parser.add_argument("--exceptions", type=Path, help="Reviewed JSON list (default: empty)")
    args = parser.parse_args(argv)
    try:
        exceptions = load_exceptions(args.exceptions) if args.exceptions else ()
        findings = scan_tree(args.tree, exceptions)
    except (OSError, ValueError):
        parser.exit(2, "Invalid scan root or exceptions file\n")
    print_findings(findings)
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
