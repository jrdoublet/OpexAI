#!/usr/bin/env python3
"""PUB-42 headless smoke: one short OpenTTD 15.3 game, OpexAI alone.

Downloads the official linux generic build and OpenGFX from the CDN, then
runs a 256x256 map (map log2 8) for one year by default. The content
catalogue is not contacted: this environment can reach it only over IPv6,
and the smoke must not depend on it.

The run uses the null video, sound and music drivers and stops after a
fixed number of ticks. It is not the dedicated-server mode, which does not
exit on its own. -X keeps the game off the user data directory. -x does not
write configuration back.

OpenTTD embeds Squirrel and compiles the AI at load. Failure is a non-zero
engine exit or a script-death / load-failure line. There is no separate
Squirrel compiler in this job.

The CDN rejects clients that send no User-Agent. Archives are checked
against the pinned SHA-256 before use. Cache: OPEX_CI_CACHE, otherwise a
directory under the user cache. libfluidsynth.so.3 must be installed
(package libfluidsynth3 on Ubuntu); this script does not fetch it.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile


CDN = "https://cdn.openttd.org/"
USER_AGENT = "opexai-public-ci"
OPENTTD_VERSION = "15.3"
OPENGFX_VERSION = "7.1"
OPENTTD_NAME = "openttd-15.3-linux-generic-amd64.tar.xz"
OPENGFX_NAME = "opengfx-7.1-all.zip"
OPENGFX_TAR_NAME = "opengfx-7.1.tar"
OPENTTD_URL = CDN + "openttd-releases/15.3/" + OPENTTD_NAME
OPENGFX_URL = CDN + "opengfx-releases/7.1/" + OPENGFX_NAME
OPENTTD_SHA256 = "f49eb25d61b00f8f4d332fee02b530ad75552d1efb8f2bb01e7ca5e6540fe059"
OPENGFX_SHA256 = "928fcf34efd0719a3560cbab6821d71ce686b6315e8825360fba87a7a94d7846"
TICKS_PER_DAY = 74
DAYS_PER_YEAR = 365
# Engine strings. A healthy game must not print any of these.
FAILURE_MARKERS = (
    "Your script made an error",
    "The script died unexpectedly",
    "Failed to load API compatibility script",
    "Error compiling / running API compatibility script",
    "when trying to load the script",
    "Unable to load the script",
    "No suitable AI found",
    "Can't start a new AI",
    "Encountered error while trying to read from script file",
)


class CiSmokeError(Exception):
    """Configuration or download failure. Distinct from an AI that died."""


def build_request(url: str) -> urllib.request.Request:
    """The CDN answers 403 when the client sends no User-Agent."""
    return urllib.request.Request(url, headers={"User-Agent": USER_AGENT})


def default_cache() -> Path:
    override = os.environ.get("OPEX_CI_CACHE")
    if override:
        return Path(override)
    return Path.home() / ".cache" / "opexai-public-ci"


def resolve_ticks(years: int, days: int | None, ticks: int | None) -> int:
    """Explicit ticks win, then days, otherwise years of 365 days."""
    if ticks is not None:
        return ticks
    if days is not None:
        return days * TICKS_PER_DAY
    return years * DAYS_PER_YEAR * TICKS_PER_DAY


def failure_marker(output: str) -> str | None:
    """Return the first fatal script or load line, if any."""
    for marker in FAILURE_MARKERS:
        if marker in output:
            return marker
    return None


def render_cfg(map_log2: int, year: int) -> str:
    """One company slot is filled by start_ai. No rival is started."""
    return (
        "[difficulty]\n"
        "number_towns = 2\n"
        "industry_density = 4\n"
        "max_no_competitors = 0\n"
        "[economy]\n"
        "inflation = false\n"
        "[game_creation]\n"
        f"starting_year = {year}\n"
        f"map_x = {map_log2}\n"
        f"map_y = {map_log2}\n"
        "landscape = temperate\n"
        "[gui]\n"
        "threaded_saves = false\n"
        "autosave = off\n"
        "[network]\n"
        "server_advertise = false\n"
    )


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_archive(url: str, filename: str, expected: str, cache: Path) -> Path:
    """Download into the cache only when the pinned digest is not already there."""
    cache.mkdir(parents=True, exist_ok=True)
    dest = cache / filename
    if dest.is_file() and _sha256(dest) == expected:
        return dest
    partial = dest.with_suffix(dest.suffix + ".partial")
    try:
        with urllib.request.urlopen(build_request(url), timeout=180) as response, partial.open("wb") as handle:
            shutil.copyfileobj(response, handle)
    except OSError as exc:
        partial.unlink(missing_ok=True)
        raise CiSmokeError(f"Download failed for {filename}: {exc}") from exc
    actual = _sha256(partial)
    if actual != expected:
        partial.unlink(missing_ok=True)
        raise CiSmokeError(f"Checksum mismatch for {filename}")
    partial.replace(dest)
    return dest


def openttd_binary(archive: Path, cache: Path) -> Path:
    """Extract the generic build once next to the cached archive."""
    binary = cache / "openttd-15.3-linux-generic-amd64" / "openttd"
    if not binary.is_file():
        with tarfile.open(archive, "r:xz") as archive_handle:
            archive_handle.extractall(cache)
    if not binary.is_file():
        raise CiSmokeError("OpenTTD binary missing after extract")
    binary.chmod(binary.stat().st_mode | 0o111)
    return binary


def install_opengfx(archive: Path, baseset: Path) -> None:
    """OpenGFX ships as a tar inside the zip. The engine reads that tar."""
    baseset.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as bundle:
        members = [name for name in bundle.namelist() if Path(name).name == OPENGFX_TAR_NAME]
        if len(members) != 1:
            raise CiSmokeError(f"Expected one {OPENGFX_TAR_NAME} in the graphics archive")
        target = baseset / OPENGFX_TAR_NAME
        with bundle.open(members[0]) as src, target.open("wb") as dst:
            shutil.copyfileobj(src, dst)


def pack_ai(ai_dir: Path, dest: Path) -> None:
    """Tar whose root folder is the AI name, which is how OpenTTD loads it."""
    if not (ai_dir / "info.nut").is_file() or not (ai_dir / "main.nut").is_file():
        raise CiSmokeError("AI directory needs info.nut and main.nut")
    with tarfile.open(dest, "w", format=tarfile.USTAR_FORMAT) as archive:
        for path in sorted(ai_dir.rglob("*")):
            if path.is_symlink() or not path.is_file():
                continue
            if path.suffix == ".pyc" or "__pycache__" in path.parts:
                continue
            rel = path.relative_to(ai_dir).as_posix()
            archive.add(path, arcname=f"OpexAI/{rel}")


def _tail(text: str, limit: int = 80) -> str:
    lines = text.splitlines()
    return "\n".join(lines[-limit:])


def run_game(
    *,
    ai_dir: Path,
    cache: Path,
    ticks: int,
    map_log2: int,
    seed: int,
    year: int,
    timeout: int,
) -> int:
    if sys.platform != "linux" or os.uname().machine not in {"x86_64", "amd64"}:
        raise CiSmokeError("This smoke expects the linux generic amd64 build")
    if ticks < 1:
        raise CiSmokeError("Tick count must be positive")
    openttd_archive = ensure_archive(OPENTTD_URL, OPENTTD_NAME, OPENTTD_SHA256, cache)
    opengfx_archive = ensure_archive(OPENGFX_URL, OPENGFX_NAME, OPENGFX_SHA256, cache)
    binary = openttd_binary(openttd_archive, cache)
    with tempfile.TemporaryDirectory(prefix="opexai-smoke-") as tmp:
        run_dir = Path(tmp)
        install_opengfx(opengfx_archive, run_dir / "baseset")
        (run_dir / "ai").mkdir()
        (run_dir / "scripts").mkdir()
        pack_ai(ai_dir, run_dir / "ai" / "OpexAI.tar")
        (run_dir / "scripts" / "game_start.scr").write_text("start_ai OpexAI\n", encoding="ascii")
        (run_dir / "opexai-ci.cfg").write_text(render_cfg(map_log2, year), encoding="ascii")
        command = [
            str(binary),
            "-g",
            "-G",
            str(seed),
            "-snull",
            "-mnull",
            f"-vnull:ticks={ticks}",
            "-c",
            "opexai-ci.cfg",
            "-x",
            "-X",
            "-d",
            "script=1",
        ]
        nice = shutil.which("nice")
        if nice:
            command = [nice, "-n", "15", *command]
        env = os.environ.copy()
        env["HOME"] = str(run_dir)
        env["XDG_CONFIG_HOME"] = str(run_dir)
        env["XDG_DATA_HOME"] = str(run_dir)
        try:
            proc = subprocess.run(
                command,
                cwd=run_dir,
                env=env,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=timeout,
                check=False,
            )
        except subprocess.TimeoutExpired:
            print(f"Smoke failed: timeout after {timeout}s", file=sys.stderr)
            return 1
        output = (proc.stdout or "") + "\n" + (proc.stderr or "")
        marker = failure_marker(output)
        if proc.returncode != 0 or marker:
            reason = marker or f"exit {proc.returncode}"
            print(f"Smoke failed: {reason}", file=sys.stderr)
            print(_tail(output), file=sys.stderr)
            return 1
    print(f"Smoke ok ticks={ticks} seed={seed} map_log2={map_log2} year={year}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--years", type=int, default=1)
    parser.add_argument("--days", type=int, default=None)
    parser.add_argument("--ticks", type=int, default=None)
    parser.add_argument("--map-log2", type=int, default=8)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--year", type=int, default=1970)
    parser.add_argument("--ai-dir", type=Path, default=None)
    parser.add_argument("--cache", type=Path, default=None)
    parser.add_argument("--timeout", type=int, default=1800)
    args = parser.parse_args(argv)
    if args.map_log2 < 6 or args.map_log2 > 12:
        print("ERROR: --map-log2 must be from 6 to 12", file=sys.stderr)
        return 2
    if args.seed < 0 or args.timeout < 1:
        print("ERROR: --seed and --timeout must be non-negative / positive", file=sys.stderr)
        return 2
    if args.ticks is None and args.days is None and args.years < 1:
        print("ERROR: --years must be positive when ticks and days are omitted", file=sys.stderr)
        return 2
    if args.days is not None and args.days < 1:
        print("ERROR: --days must be positive", file=sys.stderr)
        return 2
    ai_dir = args.ai_dir if args.ai_dir is not None else Path(__file__).resolve().parents[1] / "ai" / "OpexAI"
    try:
        return run_game(
            ai_dir=ai_dir.resolve(),
            cache=(args.cache or default_cache()).resolve(),
            ticks=resolve_ticks(args.years, args.days, args.ticks),
            map_log2=args.map_log2,
            seed=args.seed,
            year=args.year,
            timeout=args.timeout,
        )
    except CiSmokeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
