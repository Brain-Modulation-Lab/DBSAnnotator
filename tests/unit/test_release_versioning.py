"""Tests for scripts/release_versioning.py (PEP 440 bump helpers)."""

from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location(
    "release_versioning",
    Path(__file__).resolve().parents[2] / "scripts" / "release_versioning.py",
)
assert _SPEC and _SPEC.loader
rv = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(rv)


def test_parse_and_bump_alpha_chain() -> None:
    assert rv.bump_version("0.4.0", "alpha") == "0.4.0a1"
    assert rv.bump_version("0.4.0a1", "alpha") == "0.4.0a2"


def test_bump_beta_from_alpha_and_increment() -> None:
    assert rv.bump_version("0.4.0a3", "beta") == "0.4.0b1"
    assert rv.bump_version("0.4.0b1", "beta") == "0.4.0b2"


def test_bump_rc_from_beta_and_increment() -> None:
    assert rv.bump_version("0.4.0b2", "rc") == "0.4.0rc1"
    assert rv.bump_version("0.4.0rc1", "rc") == "0.4.0rc2"


def test_bump_stable_strips_prerelease() -> None:
    assert rv.bump_version("0.4.0rc2", "stable") == "0.4.0"
    assert rv.bump_version("0.4.0", "stable") == "0.4.0"


def test_bump_semver_after_stable() -> None:
    assert rv.bump_version("0.4.0", "patch") == "0.4.1"
    assert rv.bump_version("0.4.1", "minor") == "0.5.0"
    assert rv.bump_version("0.5.0", "major") == "1.0.0"


def test_bump_patch_rejects_prerelease() -> None:
    with pytest.raises(ValueError, match="stable"):
        rv.bump_version("0.4.0a1", "patch")


def test_bump_alpha_rejects_beta() -> None:
    with pytest.raises(ValueError, match="beta"):
        rv.bump_version("0.4.0b1", "alpha")


def test_parse_rejects_local_and_epoch() -> None:
    with pytest.raises(ValueError, match="Local"):
        rv.parse_release_version("0.4.0+local")
    with pytest.raises(ValueError, match="Epoch"):
        rv.parse_release_version("1!0.4.0")
