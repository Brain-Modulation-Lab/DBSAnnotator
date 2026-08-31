#!/usr/bin/env python3
"""Bump versions, run Towncrier, and optionally commit (no tag / no push).

Designed for PR-based releases: open a PR with the produced commit, merge, then
tag ``v<version>`` on the merge commit and push the tag as the final deliberate
step. *version* may be any supported PEP 440 string (stable ``X.Y.Z`` or
prereleases such as ``X.Y.Za1``, ``X.Y.Zb2``, ``X.Y.Zrc1``).
"""

from __future__ import annotations

import argparse
import datetime as dt
import importlib.util
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
INIT_PATH = REPO_ROOT / "src" / "dbs_annotator" / "__init__.py"
PYPROJECT_PATH = REPO_ROOT / "pyproject.toml"


def _load_release_versioning():
    path = Path(__file__).resolve().parent / "release_versioning.py"
    spec = importlib.util.spec_from_file_location("_release_versioning", path)
    if spec is None or spec.loader is None:
        sys.exit(f"Could not load sibling module: {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_RV = _load_release_versioning()


def _run(cmd: list[str], *, cwd: Path | None = None) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=cwd or REPO_ROOT, check=True)


def _git_porcelain() -> str:
    r = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return r.stdout.strip()


def _current_branch() -> str:
    r = subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return r.stdout.strip()


def _read_init_version() -> str:
    text = INIT_PATH.read_text(encoding="utf-8")
    m = re.search(
        r'^__version__\s*=\s*["\']([^"\']+)["\']',
        text,
        flags=re.MULTILINE,
    )
    if not m:
        sys.exit(f"Could not read __version__ from {INIT_PATH}")
    return m.group(1)


def _validate_version(v: str) -> None:
    if v.startswith("v"):
        sys.exit("Version must not include a 'v' prefix (use 1.2.3, not v1.2.3).")
    try:
        _RV.parse_release_version(v)
    except ValueError as exc:
        sys.exit(str(exc))


def _bump_init(version: str) -> None:
    text = INIT_PATH.read_text(encoding="utf-8")
    new_text, n = re.subn(
        r'^(__version__\s*=\s*)["\'][^"\']+["\']',
        rf'\1"{version}"',
        text,
        count=1,
        flags=re.MULTILINE,
    )
    if n != 1:
        sys.exit(f"Could not find a single __version__ assignment in {INIT_PATH}")
    INIT_PATH.write_text(new_text, encoding="utf-8")


def _bump_briefcase_pyproject(version: str) -> None:
    lines = PYPROJECT_PATH.read_text(encoding="utf-8").splitlines(keepends=True)
    in_briefcase = False
    replaced = False
    out: list[str] = []
    version_line = re.compile(r'^(\s*version\s*=\s*)["\'][^"\']+["\']\s*$')

    for line in lines:
        stripped = line.strip()
        if stripped == "[tool.briefcase]":
            in_briefcase = True
            out.append(line)
            continue
        if in_briefcase and stripped.startswith("[") and stripped != "[tool.briefcase]":
            in_briefcase = False
        if in_briefcase:
            m = version_line.match(line)
            if m:
                prefix = m.group(1)
                newline = "\n" if line.endswith("\n") else ""
                out.append(f'{prefix}"{version}"{newline}')
                replaced = True
                continue
        out.append(line)

    if not replaced:
        sys.exit(
            'Could not find [tool.briefcase] version = "..." in pyproject.toml '
            "(expected a single static Briefcase version line)."
        )
    PYPROJECT_PATH.write_text("".join(out), encoding="utf-8")


def _towncrier_build(version: str, release_date: str) -> None:
    _run(
        [
            "uv",
            "run",
            "towncrier",
            "build",
            "--yes",
            "--version",
            version,
            "--date",
            release_date,
        ]
    )


def main() -> None:
    bump_choices = sorted(_RV.supported_bump_kinds())
    parser = argparse.ArgumentParser(
        description="Prepare a release: bump versions, run Towncrier, optional commit.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  uv run python scripts/release_prepare.py 0.4.0 --dry-run\n"
            "  uv run python scripts/release_prepare.py 0.4.0b2 --commit\n"
            "  uv run python scripts/release_prepare.py --bump alpha --dry-run\n"
            "  uv run python scripts/release_prepare.py --bump stable --commit\n"
            f"  --bump choices: {', '.join(bump_choices)}\n"
        ),
    )
    parser.add_argument(
        "version",
        nargs="?",
        default=None,
        help='Explicit PEP 440 version (e.g. "0.4.0", "0.4.0a1", "0.4.0rc2"). '
        "No leading v. Omit when using --bump.",
    )
    parser.add_argument(
        "--bump",
        choices=bump_choices,
        metavar="KIND",
        help=(
            "Compute the next version from the current __version__ in __init__.py. "
            "Examples: alpha 0.4.0 -> 0.4.0a1, 0.4.0a1 -> 0.4.0a2; beta 0.4.0a2 -> "
            "0.4.0b1; stable 0.4.0rc1 -> 0.4.0. patch/minor/major require a stable "
            "release (no prerelease segment)."
        ),
    )
    parser.add_argument(
        "--date",
        dest="release_date",
        metavar="YYYY-MM-DD",
        help="Towncrier release date (default: today, local).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print actions only; do not write files or run towncrier.",
    )
    parser.add_argument(
        "--commit",
        action="store_true",
        help="Stage all changes and create a single git commit (no push, no tag).",
    )
    parser.add_argument(
        "--any-branch",
        action="store_true",
        help="Allow running on main when using --commit (for automation; "
        "local users should use a branch).",
    )
    parser.add_argument(
        "--allow-dirty",
        action="store_true",
        help="Do not require a clean working tree before modifying files.",
    )
    parser.add_argument(
        "--skip-towncrier",
        action="store_true",
        help="Only bump versions (emergency use; skips changelog assembly).",
    )
    args = parser.parse_args()

    if args.bump is not None and args.version is not None:
        sys.exit("Pass either a positional version or --bump, not both.")
    if args.bump is None and args.version is None:
        sys.exit(
            "Pass a PEP 440 version (e.g. 0.4.0 or 0.4.0a1) or use --bump "
            f"({'|'.join(bump_choices)})."
        )

    if args.bump is not None:
        current = _read_init_version()
        try:
            version = _RV.bump_version(current, args.bump)
        except ValueError as exc:
            sys.exit(str(exc))
        print(f"--bump {args.bump}: {current!r} -> {version!r}", flush=True)
    else:
        version = args.version.strip()
        _validate_version(version)

    release_date = args.release_date or dt.date.today().isoformat()
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", release_date):
        sys.exit("--date must be YYYY-MM-DD.")

    dirty = _git_porcelain()
    if dirty and not args.allow_dirty:
        sys.exit(
            "Working tree is not clean. Commit or stash changes first, "
            "or pass --allow-dirty."
        )

    branch = _current_branch()
    if args.commit and branch == "main" and not args.any_branch:
        sys.exit(
            "Refusing to --commit on branch 'main'. Create a branch first, e.g.\n"
            f"  git checkout -b chore/release-prep-{version}\n"
            "Or pass --any-branch if you know what you are doing "
            "(CI uses this on a throwaway branch)."
        )

    if args.dry_run:
        print(
            "Dry run: would bump __version__ and [tool.briefcase].version to",
            repr(version),
        )
        if not args.skip_towncrier:
            print("Dry run: would run towncrier build", version, release_date)
        if args.commit:
            print("Dry run: would git add and commit")
        return

    _bump_init(version)
    _bump_briefcase_pyproject(version)
    if not args.skip_towncrier:
        _towncrier_build(version, release_date)

    if args.commit:
        stage = [
            "src/dbs_annotator/__init__.py",
            "pyproject.toml",
            "CHANGELOG.md",
            "newsfragments",
        ]
        _run(["git", "add", *stage])
        msg = f"chore(release): prepare v{version}"
        _run(["git", "commit", "-m", msg])
        print()
        print("Committed:", msg)
        print()
        print("Next (human steps):")
        print("  1. Push this branch and open a PR; merge after CI passes.")
        print("  2. On the updated main, tag the merge commit:")
        print("     git checkout main && git pull")
        print(f'     git tag -a v{version} -m "Release v{version}" <merge_sha>')
        print(f"     git push origin v{version}")
        print("  Tag push triggers the CD release workflow (builds + GitHub Release).")


if __name__ == "__main__":
    main()
