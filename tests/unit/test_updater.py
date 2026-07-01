"""Tests for :mod:`dbs_annotator.utils.updater`."""

from __future__ import annotations

import io
import json
import urllib.error
from email.message import Message
from unittest.mock import MagicMock, patch

import pytest

from dbs_annotator.config import RELEASES_GITHUB_REPO
from dbs_annotator.utils import updater as updater_mod
from dbs_annotator.utils.updater import (
    DEFAULT_RELEASES_REPO,
    UpdateChecker,
    _CheckSignals,
    _CheckWorker,
)


@pytest.fixture(autouse=True)
def _stub_ssl_context(request: pytest.FixtureRequest):
    """Avoid slow/hanging certifi SSL setup on Windows CI (except SSL unit test)."""
    if request.node.name == "test_urlopen_uses_certifi_ssl_context":
        yield
        return
    with patch("dbs_annotator.utils.updater._ssl_context", return_value=MagicMock()):
        yield


class _FakeResp:
    def __init__(self, body: bytes) -> None:
        self._body = body

    def __enter__(self) -> _FakeResp:
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def read(self) -> bytes:
        return self._body


def _mock_urlopen(data: object) -> _FakeResp:
    return _FakeResp(json.dumps(data).encode("utf-8"))


def test_fetch_empty_releases_raises() -> None:
    signals = _CheckSignals()
    worker = _CheckWorker("o/r", "1.0.0", 10.0, signals)
    with (
        patch("urllib.request.urlopen", return_value=_mock_urlopen([])),
        pytest.raises(RuntimeError, match="No published releases"),
    ):
        worker._fetch_newest_applicable_release()


def test_fetch_releases_404_raises() -> None:
    signals = _CheckSignals()
    worker = _CheckWorker("o/r", "1.0.0", 10.0, signals)
    err = urllib.error.HTTPError("url", 404, "nf", Message(), io.BytesIO(b""))
    with (
        patch("urllib.request.urlopen", side_effect=err),
        pytest.raises(RuntimeError, match="404"),
    ):
        worker._fetch_newest_applicable_release()


def test_default_releases_repo_matches_config() -> None:
    assert DEFAULT_RELEASES_REPO == RELEASES_GITHUB_REPO


def test_urlopen_uses_certifi_ssl_context() -> None:
    signals = _CheckSignals()
    worker = _CheckWorker("o/r", "1.0.0", 10.0, signals)
    with (
        patch("urllib.request.urlopen", return_value=_mock_urlopen([])) as mock_open,
        patch(
            "dbs_annotator.utils.updater._ssl_context",
            return_value=object(),
        ) as mock_ctx,
    ):
        with pytest.raises(RuntimeError):
            worker._fetch_newest_applicable_release()
    mock_ctx.assert_called()
    assert mock_open.call_args.kwargs.get("context") is mock_ctx.return_value


def test_check_async_uses_fresh_installed_version(monkeypatch) -> None:
    checker = UpdateChecker(current_version=None)
    checker._settings = MagicMock()
    checker._settings.value.return_value = True
    seen: list[str] = []

    def fake_get_version() -> str:
        v = "1.0.0" if len(seen) == 0 else "2.0.0"
        seen.append(v)
        return v

    monkeypatch.setattr("dbs_annotator.utils.updater.get_version", fake_get_version)

    pool = MagicMock()
    with patch(
        "dbs_annotator.utils.updater.QThreadPool.globalInstance",
        return_value=pool,
    ):
        checker.check_async(force=True)
        worker = pool.start.call_args[0][0]
        assert worker._current_version == "1.0.0"

        checker._finish_check()
        checker.check_async(force=True)
        worker2 = pool.start.call_args[0][0]
        assert worker2._current_version == "2.0.0"


def test_check_async_busy_blocks_second_start() -> None:
    checker = UpdateChecker(current_version="1.0.0")
    checker._settings = MagicMock()
    checker._settings.value.return_value = True
    checker._check_in_progress = True

    pool = MagicMock()
    with patch(
        "dbs_annotator.utils.updater.QThreadPool.globalInstance",
        return_value=pool,
    ):
        assert checker.check_async(force=True) is False
    pool.start.assert_not_called()


@pytest.mark.parametrize("code", [403, 500, 502])
def test_fetch_releases_other_http_raises(code: int) -> None:
    signals = _CheckSignals()
    worker = _CheckWorker("o/r", "1.0.0", 10.0, signals)
    err = urllib.error.HTTPError("url", code, "e", Message(), io.BytesIO(b""))
    with (
        patch("urllib.request.urlopen", side_effect=err),
        pytest.raises(urllib.error.HTTPError) as ctx,
    ):
        worker._fetch_newest_applicable_release()
    assert ctx.value.code == code


def test_picks_highest_semver_over_multiple_candidates() -> None:
    signals = _CheckSignals()
    worker = _CheckWorker("o/r", "1.0.0", 10.0, signals)
    releases = [
        {
            "draft": False,
            "tag_name": "v1.1.0",
            "html_url": "https://u/1",
            "published_at": "t1",
            "body": "a",
            "prerelease": False,
        },
        {
            "draft": False,
            "tag_name": "v1.2.0b1",
            "html_url": "https://u/2",
            "published_at": "t2",
            "body": "b",
            "prerelease": True,
        },
        {
            "draft": False,
            "tag_name": "v0.9.0",
            "html_url": "https://u/0",
            "published_at": "t0",
            "body": "",
            "prerelease": False,
        },
    ]
    with patch("urllib.request.urlopen", return_value=_mock_urlopen(releases)):
        info = worker._fetch_newest_applicable_release()
    assert info is not None
    assert info.version == "1.2.0b1"
    assert info.html_url == "https://u/2"
    assert info.is_prerelease is True


def test_stable_release_not_marked_prerelease() -> None:
    signals = _CheckSignals()
    worker = _CheckWorker("o/r", "1.0.0", 10.0, signals)
    releases = [
        {
            "draft": False,
            "tag_name": "v1.0.1",
            "html_url": "https://u/x",
            "published_at": "",
            "body": "",
            "prerelease": False,
        },
    ]
    with patch("urllib.request.urlopen", return_value=_mock_urlopen(releases)):
        info = worker._fetch_newest_applicable_release()
    assert info is not None
    assert info.is_prerelease is False


def test_tag_prerelease_without_github_flag() -> None:
    """PEP 440 pre-release in tag even if GitHub prerelease box is false."""
    signals = _CheckSignals()
    worker = _CheckWorker("o/r", "1.0.0", 10.0, signals)
    releases = [
        {
            "draft": False,
            "tag_name": "v2.0.0a1",
            "html_url": "https://u/y",
            "published_at": "",
            "body": "",
            "prerelease": False,
        },
    ]
    with patch("urllib.request.urlopen", return_value=_mock_urlopen(releases)):
        info = worker._fetch_newest_applicable_release()
    assert info is not None
    assert info.is_prerelease is True


def test_skips_draft_releases() -> None:
    signals = _CheckSignals()
    worker = _CheckWorker("o/r", "1.0.0", 10.0, signals)
    releases = [
        {
            "draft": True,
            "tag_name": "v9.0.0",
            "html_url": "",
            "published_at": "",
            "body": "",
            "prerelease": False,
        },
        {
            "draft": False,
            "tag_name": "v1.0.1",
            "html_url": "ok",
            "published_at": "",
            "body": "",
            "prerelease": False,
        },
    ]
    with patch("urllib.request.urlopen", return_value=_mock_urlopen(releases)):
        info = worker._fetch_newest_applicable_release()
    assert info is not None
    assert info.version == "1.0.1"


def test_check_async_respects_auto_disable() -> None:
    checker = UpdateChecker()
    checker._settings = MagicMock()
    checker._settings.value.return_value = False

    pool = MagicMock()
    with patch(
        "dbs_annotator.utils.updater.QThreadPool.globalInstance",
        return_value=pool,
    ):
        scheduled = checker.check_async(force=False)
    assert scheduled is False
    pool.start.assert_not_called()


def test_check_async_force_bypasses_auto_disable() -> None:
    checker = UpdateChecker()
    checker._settings = MagicMock()
    checker._settings.value.return_value = False

    pool = MagicMock()
    with patch(
        "dbs_annotator.utils.updater.QThreadPool.globalInstance",
        return_value=pool,
    ):
        checker.check_async(force=True)
    pool.start.assert_called_once()


@pytest.mark.parametrize(
    ("raw", "default", "expected"),
    [
        (True, False, True),
        (False, True, False),
        ("false", True, False),
        ("true", False, True),
        ("0", True, False),
        ("1", False, True),
        ("", True, False),
        (None, True, True),
    ],
)
def test_coerce_bool(raw: object, default: bool, expected: bool) -> None:
    assert updater_mod._coerce_bool(raw, default) is expected


def test_set_auto_update_checks_persists_via_qsettings() -> None:
    checker = UpdateChecker()
    checker._settings = MagicMock()
    checker.set_auto_update_checks_enabled(False)
    checker._settings.setValue.assert_called_once()
    checker._settings.sync.assert_called_once()
