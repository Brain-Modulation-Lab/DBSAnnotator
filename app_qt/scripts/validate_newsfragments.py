#!/usr/bin/env python3
"""Validate Towncrier news fragment filenames in ``newsfragments/``.

* Every ``*.md`` file (except ``README.md``) must be named::

    <id>.(added|changed|deprecated|removed|fixed|security).md

  where ``<id>`` is the GitHub issue/PR number (digits only, no leading zeros
  required by the regex, but use the real PR number in practice).

* With ``--pr N`` and ``--diff`` ``BASE_SHA..HEAD_SHA``, every fragment path
  changed between those commits must be ``N.<category>.md`` (PR-scoped
  filenames in CI).
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
NEWS = REPO_ROOT / "newsfragments"
SKIP = frozenset({"README.md"})
NAME_RE = re.compile(
    r"^([1-9]\d*)\.(added|changed|deprecated|removed|fixed|security)\.md$",
    re.IGNORECASE,
)
CATEGORIES = frozenset(
    ("added", "changed", "deprecated", "removed", "fixed", "security")
)


def _discovered_fragments() -> list[Path]:
    if not NEWS.is_dir():
        return []
    return sorted(
        p
        for p in NEWS.iterdir()
        if p.is_file() and p.suffix == ".md" and p.name not in SKIP
    )


def _validate_basename(name: str) -> str | None:
    """Return an error string, or None if valid."""
    m = NAME_RE.match(name)
    if not m:
        return (
            f"Invalid fragment name {name!r}. "
            f"Expected: <id>.<{'|'.join(sorted(CATEGORIES))}>.md"
        )
    if m.group(2).lower() not in CATEGORIES:
        return f"Invalid category in {name!r}"
    return None


def _git_names_from_diff(sha_a: str, sha_b: str) -> set[str]:
    r = subprocess.run(
        ["git", "diff", "--name-only", sha_a, sha_b],
        cwd=REPO_ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        return set()
    return {line.strip() for line in r.stdout.splitlines() if line.strip()}


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--pr",
        type=int,
        help="With --diff, require that each changed fragment uses this id prefix.",
    )
    p.add_argument(
        "--diff",
        metavar="BASE..HEAD",
        help="Two SHAs as BASE..HEAD; changed fragment paths are checked with --pr.",
    )
    args = p.parse_args()
    err = 0
    for path in _discovered_fragments():
        msg = _validate_basename(path.name)
        if msg:
            print(f"ERROR: {path.relative_to(REPO_ROOT)}: {msg}", file=sys.stderr)
            err = 1
    if err:
        return 1
    if args.pr is not None and args.diff:
        parts = args.diff.split("..", 1)
        if len(parts) != 2 or not all(parts):
            print(
                f"ERROR: --diff must be BASE..HEAD (got {args.diff!r})",
                file=sys.stderr,
            )
            return 1
        base_sha, head_sha = parts[0].strip(), parts[1].strip()
        want = str(args.pr)
        for rel in _git_names_from_diff(base_sha, head_sha):
            if not rel.startswith("newsfragments/") or not rel.endswith(".md"):
                continue
            name = Path(rel).name
            if name in SKIP:
                continue
            mpath = REPO_ROOT / rel
            if not mpath.is_file():
                continue
            msg = _validate_basename(name)
            if msg:
                print(f"ERROR: {rel}: {msg}", file=sys.stderr)
                err = 1
                continue
            m = NAME_RE.match(name)
            assert m  # already validated
            if m.group(1) != want:
                print(
                    f"ERROR: {rel} must be {want}.<category>.md for PR #{want} "
                    f"(filename starts with {m.group(1)!r}, not {want!r}).",
                    file=sys.stderr,
                )
                err = 1
    elif args.pr is not None and not args.diff:
        print("ERROR: --pr requires --diff", file=sys.stderr)
        return 1
    return err


if __name__ == "__main__":
    raise SystemExit(main())
