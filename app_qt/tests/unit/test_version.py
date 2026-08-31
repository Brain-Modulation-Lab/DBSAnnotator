"""Tests for dbs_annotator.version."""

import re

import pytest

from dbs_annotator import __version__
from dbs_annotator.version import get_pep440_base_version, get_version


def test_get_version_returns_non_empty():
    v = get_version()
    assert isinstance(v, str)
    assert len(v) > 0


def test_get_version_matches_package_attr():
    assert get_version() == __version__


def test_get_pep440_base_version_matches_semver_portion():
    base = get_pep440_base_version()
    assert re.match(r"^\d+\.\d+\.\d+$", base)


def test_get_pep440_base_version_raises_on_bad_string(monkeypatch):
    monkeypatch.setattr("dbs_annotator.version.get_version", lambda: "not-a-version")
    with pytest.raises(RuntimeError, match="Could not extract"):
        get_pep440_base_version()
