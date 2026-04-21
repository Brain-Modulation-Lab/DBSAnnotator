"""Check GitHub Releases for newer versions of the app.

Design goals:

* Silent on failure -- a missing network connection, a GitHub outage, or a
  rate limit must never block startup or show an error dialog to the user.
* At most one check per cooldown window (default 24 h) so repeated launches
  do not spam the GitHub API. The last-check timestamp is persisted with
  :class:`QSettings` so it survives between sessions but never leaks PII.
* The HTTP fetch runs on a worker thread via :class:`QThreadPool`; the
  main-thread slot is only invoked if a strictly-newer version is found.
* The user can always trigger a check from a menu / button with
  ``force=True`` (even when automatic checks are disabled in preferences).
* Among all published (non-draft) releases, only the **highest** version
  greater than the running build is considered (PEP 440 ordering, including
  alpha / beta / rc). GitHub's ``/releases/latest`` endpoint is not used
  because it omits pre-releases.

The release repository is hardcoded to the canonical upstream; change
:data:`DEFAULT_RELEASES_REPO` if the project moves.
"""

from __future__ import annotations

import json
import logging
import urllib.error
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, cast

from packaging.version import InvalidVersion, Version
from PySide6.QtCore import QObject, QRunnable, QSettings, QThreadPool, Signal

from .. import __version__

logger = logging.getLogger(__name__)

#: Owner/repo pair on GitHub whose releases advertise new builds.
DEFAULT_RELEASES_REPO = "Brain-Modulation-Lab/App_ClinicalDBSAnnot"

DEFAULT_COOLDOWN = timedelta(hours=24)
DEFAULT_TIMEOUT_SECONDS = 10
_LAST_CHECK_KEY = "updater/last_check_iso"
_AUTO_CHECK_KEY = "updater/auto_check_enabled"
_RELEASES_PAGE_SIZE = 100
_MAX_RELEASE_PAGES = 5


@dataclass(frozen=True)
class ReleaseInfo:
    """Metadata for a GitHub release that is newer than the running app."""

    version: str
    tag_name: str
    html_url: str
    published_at: str
    body: str
    #: ``True`` if GitHub marked the release as pre-release or the tag parses
    #: as a PEP 440 pre-release (alpha / beta / rc).
    is_prerelease: bool


def _parse_version(tag: str) -> Version | None:
    """Parse a release tag or version string with ``packaging.version``.

    Returns ``None`` if the tag does not look like a PEP 440-compatible
    version -- most commonly a lightweight tag used for infrastructure. Such
    tags are ignored for update-check purposes.
    """
    candidate = tag.lstrip("vV").strip()
    try:
        return Version(candidate)
    except InvalidVersion:
        return None


def _coerce_bool(value: object, default: bool) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        s = value.lower().strip()
        if s in ("false", "0", "no", ""):
            return False
        if s in ("true", "1", "yes"):
            return True
        return default
    if value is None:
        return default
    return bool(value)


class _CheckSignals(QObject):
    """Qt signals for a check worker.

    Signals always run on the main thread, so handlers are free to touch the
    GUI without additional marshalling.
    """

    update_available = Signal(object)
    up_to_date = Signal()
    failed = Signal(str)


class _CheckWorker(QRunnable):
    """Single-shot worker that queries the GitHub Releases API."""

    def __init__(
        self,
        repo: str,
        current_version: str,
        timeout: float,
        signals: _CheckSignals,
    ) -> None:
        super().__init__()
        self._repo = repo
        self._current_version = current_version
        self._timeout = timeout
        self._signals = signals

    def run(self) -> None:
        try:
            latest = self._fetch_newest_applicable_release()
        except Exception as exc:
            logger.info("Update check failed: %s", exc)
            self._signals.failed.emit(str(exc))
            return

        if latest is None:
            self._signals.up_to_date.emit()
            return

        self._signals.update_available.emit(latest)

    def _request(self, url: str) -> urllib.request.Request:
        return urllib.request.Request(
            url,
            headers={
                "Accept": "application/vnd.github+json",
                "User-Agent": f"DBSAnnotator/{self._current_version}",
            },
        )

    def _urlopen_json(self, url: str) -> object:
        request = self._request(url)
        with urllib.request.urlopen(request, timeout=self._timeout) as response:
            return json.loads(response.read().decode("utf-8"))

    def _fetch_releases_page(self, page: int) -> list[dict] | None:
        url = (
            f"https://api.github.com/repos/{self._repo}/releases"
            f"?per_page={_RELEASES_PAGE_SIZE}&page={page}"
        )
        try:
            payload = self._urlopen_json(url)
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                logger.debug(
                    "No GitHub releases list for %s (HTTP %s); treat as no update",
                    self._repo,
                    exc.code,
                )
                return None
            raise
        if not isinstance(payload, list):
            return []
        return cast(list[dict[str, Any]], payload)

    def _fetch_all_releases(self) -> list[dict]:
        merged: list[dict] = []
        for page in range(1, _MAX_RELEASE_PAGES + 1):
            batch = self._fetch_releases_page(page)
            if batch is None:
                return []
            merged.extend(batch)
            if len(batch) < _RELEASES_PAGE_SIZE:
                break
        return merged

    def _fetch_newest_applicable_release(self) -> ReleaseInfo | None:
        """Return single newest published release with version *>* local."""
        payloads = self._fetch_all_releases()
        if not payloads:
            return None

        local = _parse_version(self._current_version)
        if local is None:
            logger.debug(
                "Skipping update comparison; local version not PEP 440: %r",
                self._current_version,
            )
            return None

        best_remote: Version | None = None
        best_payload: dict | None = None

        for payload in payloads:
            if payload.get("draft"):
                continue
            tag = str(payload.get("tag_name", ""))
            if not tag:
                continue
            remote = _parse_version(tag)
            if remote is None or remote <= local:
                continue
            if best_remote is None or remote > best_remote:
                best_remote = remote
                best_payload = payload

        if best_remote is None or best_payload is None:
            return None

        gh_prerelease = bool(best_payload.get("prerelease"))
        is_prerelease = gh_prerelease or best_remote.is_prerelease

        return ReleaseInfo(
            version=str(best_remote),
            tag_name=str(best_payload.get("tag_name", "")),
            html_url=str(best_payload.get("html_url", "")),
            published_at=str(best_payload.get("published_at", "")),
            body=str(best_payload.get("body", "")),
            is_prerelease=is_prerelease,
        )


class UpdateChecker(QObject):
    """Orchestrates background update checks with a configurable cooldown.

    Create one of these on the main thread (typically owned by the main
    window) and call :meth:`check_async`. A ``check_async(force=True)`` call
    bypasses the cooldown -- wire it to a "Check for updates" menu action.
    Automatic checks respect :meth:`auto_update_checks_enabled` (stored in
    ``QSettings`` under :data:`_AUTO_CHECK_KEY`).
    """

    update_available = Signal(object)
    up_to_date = Signal()
    failed = Signal(str)

    def __init__(
        self,
        repo: str = DEFAULT_RELEASES_REPO,
        current_version: str | None = None,
        cooldown: timedelta = DEFAULT_COOLDOWN,
        timeout: float = DEFAULT_TIMEOUT_SECONDS,
        parent: QObject | None = None,
    ) -> None:
        super().__init__(parent)
        self._repo = repo
        self._current_version = current_version or __version__
        self._cooldown = cooldown
        self._timeout = timeout
        self._settings = QSettings()
        self._signals = _CheckSignals()
        self._signals.update_available.connect(self._on_update_available)
        self._signals.up_to_date.connect(self._on_up_to_date)
        self._signals.failed.connect(self._on_failed)

    def auto_update_checks_enabled(self) -> bool:
        """Whether startup / periodic background checks are allowed."""
        raw = self._settings.value(_AUTO_CHECK_KEY, True)
        return _coerce_bool(raw, True)

    def set_auto_update_checks_enabled(self, enabled: bool) -> None:
        """Persist preference for automatic update checks."""
        self._settings.setValue(_AUTO_CHECK_KEY, enabled)
        self._settings.sync()

    def _on_update_available(self, release: ReleaseInfo) -> None:
        self._record_check_time()
        self.update_available.emit(release)

    def _on_up_to_date(self) -> None:
        self._record_check_time()
        self.up_to_date.emit()

    def _on_failed(self, error: str) -> None:
        # Intentionally do NOT record a check time on hard failures so the
        # next launch retries instead of waiting out the cooldown.
        self.failed.emit(error)

    def check_async(
        self,
        *,
        force: bool = False,
        now: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> bool:
        """Schedule a background check.

        Args:
            force: If True, bypass the cooldown and automatic-check opt-out.
            now: Injectable clock, only for tests.

        Returns:
            True if a check was scheduled; False if the cooldown suppressed
            it, automatic checks are disabled, or (when not forced) opt-out
            applies.
        """
        if not force and not self.auto_update_checks_enabled():
            return False
        if not force and not self._cooldown_elapsed(now()):
            return False

        worker = _CheckWorker(
            repo=self._repo,
            current_version=self._current_version,
            timeout=self._timeout,
            signals=self._signals,
        )
        QThreadPool.globalInstance().start(worker)
        return True

    def _cooldown_elapsed(self, now: datetime) -> bool:
        # QSettings.value overloads are loose in stubs; narrow before fromisoformat.
        raw = self._settings.value(_LAST_CHECK_KEY, "")
        if not isinstance(raw, str) or not raw:
            return True
        try:
            last = datetime.fromisoformat(raw)
        except ValueError:
            return True
        if last.tzinfo is None:
            last = last.replace(tzinfo=UTC)
        return (now - last) >= self._cooldown

    def _record_check_time(self) -> None:
        self._settings.setValue(_LAST_CHECK_KEY, datetime.now(UTC).isoformat())
