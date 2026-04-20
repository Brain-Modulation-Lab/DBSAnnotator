#!/usr/bin/env python3
"""Bump versions, run Towncrier, and optionally commit (no tag / no push).

Designed for PR-based releases: open a PR with the produced commit, merge, then
tag ``vX.Y.Z`` on the merge commit and push the tag as the final deliberate step.
"""

from __future__ import annotations

import argparse
import datetime as dt
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
INIT_PATH = REPO_ROOT / "src" / "dbs_annotator" / "__init__.py"
PYPROJECT_PATH = REPO_ROOT / "pyproject.toml"


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


def _validate_version(v: str) -> None:
    if v.startswith("v"):
        sys.exit("Version must not include a 'v' prefix (use 1.2.3, not v1.2.3).")
    if not re.fullmatch(r"\d+\.\d+\.\d+([a-zA-Z0-9._-]+)?", v):
        sys.exit(
            "Version must be PEP 440-ish (e.g. 1.2.3 or 1.2.3rc1). "
            "Patch releases use three numeric segments."
        )


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
    parser = argparse.ArgumentParser(
        description="Prepare a release: bump versions, run Towncrier, optional commit."
    )
    parser.add_argument(
        "version",
        help='Release version, e.g. "0.4.0" (no leading v).',
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
            "Dry run: would bump __version__ and [tool.briefcase].version to", version
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
