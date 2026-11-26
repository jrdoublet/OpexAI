#!/usr/bin/env python3
"""PUB-40: deterministic BaNaNaS/GitHub packager and validator for OpexAI.

Builds a reproducible OpexAI-<version>.tar archive containing the public
profile of OpexAI (generated via src/opexai_schema.py --profile public) from a
whitelisted copy of ai/OpexAI, without ever modifying ai/OpexAI.
"""

from __future__ import annotations

import argparse
import hashlib
import io
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_AI_DIR = ROOT / "ai" / "OpexAI"
DEFAULT_SCHEMA_SCRIPT = ROOT / "src" / "opexai_schema.py"

OPTIONAL_ROOT_FILES = ("LICENSE", "readme.txt", "changelog.txt")
FORBIDDEN_NAMES_LOWER = frozenset({"claude.md", "license.txt", "license.md"})
EXCLUDED_DIR_NAMES = frozenset({"tests", "test", "journaux", "logs", "__pycache__", ".git"})
PUBLIC_SETTING_NAMES = frozenset({
    "difficulty",
    "use_trains",
    "use_road_vehicles",
    "use_aircraft",
    "use_ships",
    "show_signs",
    "log_level",
})
LEGACY_DIFFICULTY_KEYS = ("easy_value", "medium_value", "hard_value", "custom_value")

FIXED_MTIME = 0
FIXED_UID = 0
FIXED_GID = 0
FIXED_UNAME = ""
FIXED_GNAME = ""
DIR_MODE = 0o755
FILE_MODE = 0o644

BANANAS_MAX_PACKET_BYTES = 1400
MAX_DESCRIPTION_CHARS = 200
MAX_BANANAS_DESCRIPTION_BYTES = 600

SETTING_RE = re.compile(r"AddSetting\(\{(.*?)\}\);", re.S)
NUT_COMMENT_OR_STRING_RE = re.compile(
    r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"',
    re.S,
)
IMPORT_CALL_RE = re.compile(r"\bimport\s*\(")


def _join(*parts: str) -> str:
    """Join fragments so this source does not contain the text it searches for."""
    return "".join(parts)


# A literal personal directory in this file would fail the public-tree scan.
_HOME_MARK = _join("/", "home", "/")
_WIN_MARK = _join("C:", "\\", "Users")
HOME_PATH_RE = re.compile(re.escape(_HOME_MARK), re.IGNORECASE)
WIN_USERS_RE = re.compile(r"c:[\\/]users\b", re.IGNORECASE)
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")


class PackageValidationError(ValueError):
    """Raised when one or more PUB-40 / §6 validations fail."""

    def __init__(self, errors: list[str]) -> None:
        self.errors = list(errors)
        super().__init__("\n".join(self.errors))


def is_whitelisted_ai_file(rel_path: Path) -> bool:
    """Return True iff rel_path (relative to package root) is allowed in the package."""
    if not rel_path.parts:
        return False
    if any(part.lower() in EXCLUDED_DIR_NAMES for part in rel_path.parts[:-1]):
        return False
    name = rel_path.name
    lower = name.lower()
    if lower in FORBIDDEN_NAMES_LOWER:
        return False
    if len(rel_path.parts) == 1 and name in OPTIONAL_ROOT_FILES:
        return True
    if rel_path.suffix == ".nut":
        if lower.startswith("test_") or lower.endswith("_test.nut"):
            return False
        return True
    return False


def copy_whitelisted_sources(
    ai_dir: Path,
    staging_dir: Path,
    repo_root: Path | None = None,
) -> list[str]:
    """Copy whitelisted files from ai_dir (and optional root docs/LICENSE) into staging_dir."""
    ai_dir = Path(ai_dir).resolve()
    staging_dir = Path(staging_dir).resolve()
    if not ai_dir.is_dir():
        raise FileNotFoundError(f"AI source directory not found: {ai_dir}")

    staging_dir.mkdir(parents=True, exist_ok=True)
    copied: set[str] = set()

    for src in sorted(ai_dir.rglob("*")):
        if not src.is_file():
            continue
        rel = src.relative_to(ai_dir)
        if not is_whitelisted_ai_file(rel):
            continue
        dst = staging_dir / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        copied.add(rel.as_posix())

    if repo_root is not None:
        repo_root = Path(repo_root).resolve()
        for fname in OPTIONAL_ROOT_FILES:
            if fname in copied:
                continue
            candidate = repo_root / fname
            if candidate.is_file():
                shutil.copyfile(candidate, staging_dir / fname)
                copied.add(fname)

    return sorted(copied)


def generate_public_profile(
    staging_dir: Path,
    schema_script: Path = DEFAULT_SCHEMA_SCRIPT,
) -> None:
    """Generate the public profile inside staging_dir via src/opexai_schema.py."""
    cmd = [
        sys.executable,
        str(Path(schema_script).resolve()),
        "--profile",
        "public",
        "--output-dir",
        str(Path(staging_dir).resolve()),
    ]
    proc = subprocess.run(cmd, check=False, capture_output=True, text=True)
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()
        raise RuntimeError(
            f"Public profile generation failed (rc={proc.returncode}): {detail}"
        )


def strip_nut_comments_and_strings(text: str) -> str:
    """Replace Squirrel comments and string literals with spaces."""
    return NUT_COMMENT_OR_STRING_RE.sub(" ", text)


def _extract_return_string(text: str, method: str) -> str | None:
    match = re.search(
        rf'function\s+{method}\(\)\s*\{{\s*return\s+"([^"]*)";\s*\}}',
        text,
    )
    return match.group(1) if match else None


def _extract_return_int(text: str, method: str) -> int | None:
    match = re.search(
        rf"function\s+{method}\(\)\s*\{{\s*return\s+(-?\d+);\s*\}}",
        text,
    )
    return int(match.group(1)) if match else None


def parse_info_nut(text: str) -> dict:
    """Extract metadata and AddSetting blocks from info.nut."""
    settings: list[dict] = []
    for block in SETTING_RE.findall(text):
        name_m = re.search(r'name\s*=\s*"([^"]+)"', block)
        desc_m = re.search(r'description\s*=\s*"([^"]*)"', block)
        default_m = re.search(r"\bdefault_value\s*=\s*(-?\d+)", block)
        legacy = [key for key in LEGACY_DIFFICULTY_KEYS if re.search(rf"\b{key}\b", block)]
        settings.append({
            "name": name_m.group(1) if name_m else None,
            "description": desc_m.group(1) if desc_m else None,
            "default_value": int(default_m.group(1)) if default_m else None,
            "legacy_keys": legacy,
        })

    return {
        "extends_aiinfo": bool(re.search(r"\bclass\s+\w+\s+extends\s+AIInfo\b", text)),
        "author": _extract_return_string(text, "GetAuthor"),
        "name": _extract_return_string(text, "GetName"),
        "description": _extract_return_string(text, "GetDescription"),
        "version": _extract_return_int(text, "GetVersion"),
        "min_version_to_load": _extract_return_int(text, "MinVersionToLoad"),
        "date": _extract_return_string(text, "GetDate"),
        "url": _extract_return_string(text, "GetURL"),
        "create_instance": _extract_return_string(text, "CreateInstance"),
        "short_name": _extract_return_string(text, "GetShortName"),
        "api_version": _extract_return_string(text, "GetAPIVersion"),
        "has_difficulty_labels": 'AddLabels("difficulty"' in text,
        "settings": settings,
    }


def validate_package_dir(
    pkg_dir: Path,
    *,
    expected_version: str | None = None,
    source_info_path: Path | None = None,
) -> tuple[list[str], dict]:
    """Run all §6 and BaNaNaS §1.3 validations on a staged package directory."""
    pkg_dir = Path(pkg_dir).resolve()
    errors: list[str] = []
    metadata: dict = {}

    if not pkg_dir.is_dir():
        return [f"Package directory does not exist: {pkg_dir}"], metadata

    all_files = sorted(p for p in pkg_dir.rglob("*") if p.is_file())
    rel_paths = [p.relative_to(pkg_dir) for p in all_files]
    rel_posix = [r.as_posix() for r in rel_paths]

    for required in ("info.nut", "main.nut", "settings.nut"):
        if required not in rel_posix:
            errors.append(f"Missing required file: {required}")

    for path, rel in zip(all_files, rel_paths):
        posix = rel.as_posix()
        lower_name = rel.name.lower()
        if lower_name in FORBIDDEN_NAMES_LOWER:
            errors.append(f"Forbidden file in package: {posix}")
        elif not is_whitelisted_ai_file(rel):
            errors.append(f"Non-whitelisted file in package: {posix}")

        raw = path.read_bytes()
        non_ascii = [(i, b) for i, b in enumerate(raw) if b >= 0x80]
        if non_ascii:
            errors.append(
                f"Non-ASCII byte(s) in {posix}: count={len(non_ascii)}, first={non_ascii[0]!r}"
            )

        text = raw.decode("ascii", errors="replace")

        if HOME_PATH_RE.search(text):
            errors.append(f"Personal path '{_HOME_MARK}' found in {posix}")
        if WIN_USERS_RE.search(text):
            errors.append(f"Personal path '{_WIN_MARK}' found in {posix}")
        email_m = EMAIL_RE.search(text)
        if email_m:
            errors.append(f"Email address '{email_m.group(0)}' found in {posix}")

        if rel.suffix == ".nut":
            code = strip_nut_comments_and_strings(text)
            if IMPORT_CALL_RE.search(code):
                errors.append(f"Forbidden BaNaNaS import() call found in {posix}")

    info_path = pkg_dir / "info.nut"
    if info_path.is_file():
        info_text = info_path.read_bytes().decode("ascii", errors="replace")
        info = parse_info_nut(info_text)
        metadata["info"] = info

        if not info["extends_aiinfo"]:
            errors.append("info.nut must declare a class extending AIInfo")
        if not info["name"]:
            errors.append("info.nut missing non-empty GetName()")
        if not info["author"]:
            errors.append("info.nut missing non-empty GetAuthor()")
        if not info["create_instance"]:
            errors.append("info.nut missing non-empty CreateInstance()")
        if not info["api_version"]:
            errors.append("info.nut missing non-empty GetAPIVersion()")
        if not info["short_name"] or len(info["short_name"]) != 4:
            errors.append(f"info.nut GetShortName() must be 4 ASCII chars, got {info['short_name']!r}")
        if not info["date"] or not DATE_RE.match(info["date"]):
            errors.append(f"info.nut GetDate() must be YYYY-MM-DD, got {info['date']!r}")
        if info["url"] is None:
            errors.append("info.nut missing GetURL()")

        desc = info["description"]
        if not desc:
            errors.append("info.nut missing non-empty GetDescription()")
        else:
            if len(desc) > MAX_DESCRIPTION_CHARS:
                errors.append(
                    f"info.nut GetDescription() exceeds {MAX_DESCRIPTION_CHARS} chars ({len(desc)})"
                )
            if len(desc.encode("utf-8")) > MAX_BANANAS_DESCRIPTION_BYTES:
                errors.append(
                    f"info.nut GetDescription() exceeds {MAX_BANANAS_DESCRIPTION_BYTES} bytes"
                )

        version = info["version"]
        min_ver = info["min_version_to_load"]
        if version is None or version < 1:
            errors.append(f"info.nut GetVersion() must be a positive int, got {version!r}")
        if min_ver is None or min_ver < 1:
            errors.append(f"info.nut MinVersionToLoad() must be a positive int, got {min_ver!r}")
        if version is not None and min_ver is not None and min_ver > version:
            errors.append(
                f"Inconsistent version: MinVersionToLoad()={min_ver} > GetVersion()={version}"
            )

        if source_info_path is not None and Path(source_info_path).is_file():
            src_info = parse_info_nut(Path(source_info_path).read_text(encoding="utf-8", errors="replace"))
            if src_info["version"] != version:
                errors.append(
                    f"Version mismatch between source info.nut ({src_info['version']}) and public info.nut ({version})"
                )
            if src_info["min_version_to_load"] != min_ver:
                errors.append(
                    f"MinVersionToLoad mismatch between source info.nut ({src_info['min_version_to_load']}) and public info.nut ({min_ver})"
                )

        if expected_version is not None:
            if not expected_version or any(ch in expected_version for ch in ("/", "\\", "..", " ", "\t", "\n")):
                errors.append(f"Invalid --version string: {expected_version!r}")
            elif not expected_version.isascii():
                errors.append(f"--version must be pure ASCII: {expected_version!r}")
            elif expected_version.isdigit():
                if version is not None and int(expected_version) != version:
                    errors.append(
                        f"Inconsistent version: --version={expected_version} != info.nut GetVersion()={version}"
                    )
            elif not SEMVER_RE.match(expected_version):
                errors.append(
                    f"Invalid --version format {expected_version!r} (expected integer matching GetVersion or SemVer X.Y.Z)"
                )
            package_version = expected_version
        else:
            package_version = str(version) if version is not None else ""
        metadata["package_version"] = package_version

        settings = info["settings"]
        if len(settings) != 7:
            errors.append(f"Public info.nut must declare exactly 7 settings, found {len(settings)}")
        declared_names = [s["name"] for s in settings]
        if set(declared_names) != PUBLIC_SETTING_NAMES:
            errors.append(
                f"Public info.nut setting names mismatch: expected {sorted(PUBLIC_SETTING_NAMES)}, got {sorted(n or '' for n in declared_names)}"
            )
        for s in settings:
            sname = s["name"] or "<unnamed>"
            if s["default_value"] is None:
                errors.append(f"Public setting '{sname}' missing default_value")
            if s["legacy_keys"]:
                errors.append(
                    f"Public setting '{sname}' uses deprecated keys: {', '.join(s['legacy_keys'])}"
                )
            sdesc = s["description"]
            if not sdesc:
                errors.append(f"Public setting '{sname}' missing description")
            elif len(sdesc) > MAX_DESCRIPTION_CHARS:
                errors.append(
                    f"Public setting '{sname}' description exceeds {MAX_DESCRIPTION_CHARS} chars ({len(sdesc)})"
                )
        if not info["has_difficulty_labels"]:
            errors.append('Public info.nut missing AddLabels("difficulty", ...)')

        packet_len = len(
            (
                (info["name"] or "")
                + package_version
                + (info["url"] or "")
                + (desc or "")
            ).encode("utf-8")
        )
        metadata["bananas_packet_bytes"] = packet_len
        if packet_len >= BANANAS_MAX_PACKET_BYTES:
            errors.append(
                f"BaNaNaS metadata entry too large: {packet_len} >= {BANANAS_MAX_PACKET_BYTES} bytes"
            )

    metadata["files"] = rel_posix
    return errors, metadata


def build_deterministic_tar_bytes(pkg_dir: Path, root_dir_name: str) -> bytes:
    """Build a byte-deterministic USTAR .tar archive with sorted entries and fixed metadata."""
    pkg_dir = Path(pkg_dir).resolve()
    buf = io.BytesIO()

    dir_arcs: set[str] = {root_dir_name}
    file_entries: list[tuple[str, Path]] = []

    for path in sorted(pkg_dir.rglob("*"), key=lambda p: p.relative_to(pkg_dir).as_posix()):
        rel = path.relative_to(pkg_dir)
        arcname = f"{root_dir_name}/{rel.as_posix()}"
        if path.is_dir():
            dir_arcs.add(arcname)
        elif path.is_file():
            for parent in rel.parents:
                if parent != Path("."):
                    dir_arcs.add(f"{root_dir_name}/{parent.as_posix()}")
            file_entries.append((arcname, path))

    entries: list[tuple[str, str, Path | None]] = (
        [(d, "dir", None) for d in dir_arcs]
        + [(arc, "file", p) for arc, p in file_entries]
    )
    entries.sort(key=lambda item: item[0])

    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as tf:
        for arcname, kind, src_path in entries:
            info = tarfile.TarInfo(name=arcname)
            info.mtime = FIXED_MTIME
            info.uid = FIXED_UID
            info.gid = FIXED_GID
            info.uname = FIXED_UNAME
            info.gname = FIXED_GNAME
            if kind == "dir":
                info.type = tarfile.DIRTYPE
                info.mode = DIR_MODE
                info.size = 0
                tf.addfile(info)
            else:
                assert src_path is not None
                data = src_path.read_bytes()
                info.type = tarfile.REGTYPE
                info.mode = FILE_MODE
                info.size = len(data)
                tf.addfile(info, io.BytesIO(data))

    return buf.getvalue()


def _resolve_output_tar_path(out: Path | None, tar_name: str, repo_root: Path) -> Path:
    if out is None:
        return (repo_root / "dist" / tar_name).resolve()
    out_path = Path(out)
    if out_path.suffix == ".tar":
        return out_path.resolve()
    return (out_path / tar_name).resolve()


def package_opexai(
    *,
    out: Path | None = None,
    dry_run: bool = False,
    version: str | None = None,
    ai_dir: Path = DEFAULT_AI_DIR,
    repo_root: Path = ROOT,
    schema_script: Path = DEFAULT_SCHEMA_SCRIPT,
    already_public: bool = False,
) -> dict:
    """Copy, generate public profile, validate, and build deterministic OpexAI .tar + md5.

    already_public skips the schema generator. The public repository already
    contains the generated profile and does not ship the generator.
    """
    ai_dir_resolved = Path(ai_dir).resolve()
    repo_root_resolved = Path(repo_root).resolve()

    with tempfile.TemporaryDirectory(prefix="opexai_pkg_") as tmp:
        staging_dir = Path(tmp) / "stage"
        copy_whitelisted_sources(ai_dir_resolved, staging_dir, repo_root=repo_root_resolved)
        if not already_public:
            generate_public_profile(staging_dir, schema_script=schema_script)

        errors, metadata = validate_package_dir(
            staging_dir,
            expected_version=version,
            source_info_path=ai_dir_resolved / "info.nut",
        )
        if errors:
            raise PackageValidationError(errors)

        pkg_version = metadata["package_version"]
        root_dir_name = f"OpexAI-{pkg_version}"
        tar_name = f"{root_dir_name}.tar"
        tar_path = _resolve_output_tar_path(out, tar_name, repo_root_resolved)

        if ai_dir_resolved in tar_path.parents or tar_path == ai_dir_resolved:
            raise ValueError(f"Output path must not be inside ai/OpexAI: {tar_path}")

        tar_bytes = build_deterministic_tar_bytes(staging_dir, root_dir_name)
        md5_hex = hashlib.md5(tar_bytes).hexdigest()
        md5_path = Path(f"{tar_path}.md5")

        if not dry_run:
            tar_path.parent.mkdir(parents=True, exist_ok=True)
            tar_path.write_bytes(tar_bytes)
            md5_path.write_text(f"{md5_hex}  {tar_path.name}\n", encoding="ascii")

        return {
            "version": pkg_version,
            "root_dir": root_dir_name,
            "archive_name": tar_path.name,
            "tar_path": tar_path,
            "md5_path": md5_path,
            "md5": md5_hex,
            "md5_prefix8": md5_hex[:8],
            "size_bytes": len(tar_bytes),
            "file_count": len(metadata["files"]),
            "files": metadata["files"],
            "dry_run": dry_run,
        }


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out",
        type=Path,
        default=None,
        help="Output directory or .tar file path (default: <repo>/dist/OpexAI-<version>.tar)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Run copy, public profile generation, all validations and tar/md5 computation without writing files",
    )
    parser.add_argument(
        "--version",
        type=str,
        default=None,
        help="Optional package version (integer matching info.nut GetVersion() or SemVer X.Y.Z)",
    )
    parser.add_argument(
        "--ai-dir",
        type=Path,
        default=DEFAULT_AI_DIR,
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--schema-script",
        type=Path,
        default=DEFAULT_SCHEMA_SCRIPT,
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--already-public",
        action="store_true",
        help="Sources are already the public profile; do not run the schema generator",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)
    try:
        result = package_opexai(
            out=args.out,
            dry_run=args.dry_run,
            version=args.version,
            ai_dir=args.ai_dir,
            schema_script=args.schema_script,
            already_public=args.already_public,
        )
    except (PackageValidationError, ValueError, FileNotFoundError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    mode = "DRY-RUN" if result["dry_run"] else "WROTE"
    print(f"{result['md5']}  {result['archive_name']}")
    print(
        f"[{mode}] version={result['version']} files={result['file_count']} "
        f"bytes={result['size_bytes']} md5_prefix8={result['md5_prefix8']} "
        f"path={result['tar_path']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
