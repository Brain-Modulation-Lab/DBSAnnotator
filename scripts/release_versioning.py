"""PEP 440 version parsing and bump helpers for ``release_prepare.py``.

Supports prerelease segments (``aN``, ``bN``, ``rcN``) and stable ``X.Y.Z``
bumps. Not supported: epochs, local labels (``+foo``), dev releases, post
releases, or more than three release segments (``1.2.3.4``).
"""

from __future__ import annotations

from packaging.version import InvalidVersion, Version

_BUMP_KINDS = frozenset({"alpha", "beta", "rc", "stable", "patch", "minor", "major"})


def supported_bump_kinds() -> frozenset[str]:
    return _BUMP_KINDS


def parse_release_version(s: str) -> Version:
    """Parse *s* as :class:`packaging.version.Version` with supported constraints."""
    try:
        v = Version(s)
    except InvalidVersion as exc:
        raise ValueError(f"Not a valid PEP 440 version: {s!r}") from exc
    if v.epoch != 0:
        raise ValueError(f"Epoch versions are not supported: {s!r}")
    if v.local is not None:
        raise ValueError(f"Local version labels are not supported: {s!r}")
    if v.dev is not None:
        raise ValueError(f"Dev releases (.devN) are not supported: {s!r}")
    if v.post is not None:
        raise ValueError(f"Post releases (.postN) are not supported: {s!r}")
    return v


def as_triple(v: Version) -> tuple[int, int, int]:
    """Return ``(major, minor, patch)`` from the release tuple (padding with 0)."""
    r = v.release
    if not r:
        return (0, 0, 0)
    if len(r) > 3:
        raise ValueError(
            f"Only X.Y.Z release segments are supported, got release={r!r}"
        )
    x = int(r[0])
    y = int(r[1]) if len(r) > 1 else 0
    z = int(r[2]) if len(r) > 2 else 0
    return (x, y, z)


def fmt_xyz(x: int, y: int, z: int) -> str:
    return f"{x}.{y}.{z}"


def _require_no_prerelease(v: Version, op: str) -> None:
    if v.pre is not None:
        raise ValueError(
            f"Cannot {op} while version has a prerelease ({v.pre!r}); "
            "use --bump stable first, or use --bump alpha/beta/rc."
        )


def bump_version(current: str, kind: str) -> str:
    """Return the next version string after applying *kind* to *current*."""
    if kind not in _BUMP_KINDS:
        kinds = ", ".join(sorted(_BUMP_KINDS))
        raise ValueError(f"Unknown bump kind {kind!r}; expected one of: {kinds}")

    v = parse_release_version(current)
    x, y, z = as_triple(v)
    base = fmt_xyz(x, y, z)
    pre = v.pre

    if kind == "stable":
        return base

    if kind == "alpha":
        if pre is None:
            return f"{base}a1"
        if pre[0] == "a":
            return f"{base}a{int(pre[1]) + 1}"
        raise ValueError(
            f"Cannot bump alpha from prerelease {pre!r}; use --bump beta or --bump rc."
        )

    if kind == "beta":
        if pre is None:
            return f"{base}b1"
        if pre[0] == "a":
            return f"{base}b1"
        if pre[0] == "b":
            return f"{base}b{int(pre[1]) + 1}"
        if pre[0] == "rc":
            raise ValueError(
                "Cannot bump beta from an rc prerelease; use --bump rc or "
                "--bump stable."
            )
        raise AssertionError(f"unexpected prerelease tag: {pre!r}")

    if kind == "rc":
        if pre is None:
            return f"{base}rc1"
        if pre[0] in ("a", "b"):
            return f"{base}rc1"
        if pre[0] == "rc":
            return f"{base}rc{int(pre[1]) + 1}"
        raise AssertionError(f"unexpected prerelease tag: {pre!r}")

    if kind == "patch":
        _require_no_prerelease(v, "bump patch")
        return fmt_xyz(x, y, z + 1)

    if kind == "minor":
        _require_no_prerelease(v, "bump minor")
        return fmt_xyz(x, y + 1, 0)

    if kind == "major":
        _require_no_prerelease(v, "bump major")
        return fmt_xyz(x + 1, 0, 0)

    raise AssertionError(f"unhandled kind: {kind!r}")
