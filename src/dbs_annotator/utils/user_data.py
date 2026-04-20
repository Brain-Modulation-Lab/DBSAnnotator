"""Upgrade-safe per-user data locations.

All user-owned runtime files (config JSON, preset overrides, cached state) MUST
resolve under :func:`user_data_dir` so they survive reinstalls and in-place
upgrades on every platform. The install directory (Windows ``Program Files`` /
``%LOCALAPPDATA%\\Programs\\...``, the macOS ``.app`` bundle, the Linux
``/opt`` or ``/usr`` prefix) is wiped or replaced by every MSI / DMG / dpkg
upgrade and must never hold user data.

The path is derived from Qt's :class:`QStandardPaths` so it automatically
respects the platform conventions. Organization and application directory
names are set in ``dbs_annotator.config`` as ``FS_ORG_NAME`` / ``FS_APP_NAME``
(ASCII, no spaces) and applied in ``__main__`` via ``QApplication``:

* Windows: ``%LOCALAPPDATA%\\WyssCenter\\DBSAnnotator``
* macOS:   ``~/Library/Application Support/WyssCenter/DBSAnnotator``
* Linux:   ``~/.local/share/WyssCenter/DBSAnnotator``
"""

from __future__ import annotations

import logging
import shutil
import sys
from pathlib import Path

from PySide6.QtCore import QStandardPaths

logger = logging.getLogger(__name__)


def user_data_dir() -> Path:
    """Return the platform-appropriate per-user data directory for the app.

    The directory is created if it does not yet exist. If Qt cannot determine a
    writable location (e.g. headless CI without a home directory), the caller
    gets a sensible fallback under ``~/.dbs-annotator``.
    """
    location = QStandardPaths.writableLocation(
        QStandardPaths.StandardLocation.AppLocalDataLocation
    )
    base = Path(location) if location else Path.home() / ".dbs-annotator"
    base.mkdir(parents=True, exist_ok=True)
    return base


def user_config_file(name: str) -> Path:
    """Return a path under :func:`user_data_dir` for a named config file.

    Parent directories are created on demand so callers can immediately write
    to the returned path.
    """
    path = user_data_dir() / name
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def _legacy_qt_data_candidates() -> list[Path]:
    """User-data directories from earlier QApplication identities.

    Older builds used different ``setOrganizationName`` /
    ``setApplicationName`` pairs. We probe each legacy folder so configs
    written there still migrate into the current ``FS_ORG_NAME`` /
    ``FS_APP_NAME`` tree.
    """
    candidates: list[Path] = []
    try:
        base = QStandardPaths.writableLocation(
            QStandardPaths.StandardLocation.GenericDataLocation
        )
    except Exception:
        base = ""
    if not base:
        return candidates
    root = Path(base)
    candidates.extend(
        [
            root / "BML" / "Clinical DBS Annotator",
            root / "Wyss Center" / "DBS Annotator",
            root / "BML" / "DBS Annotator",
            root / "Wyss Center" / "DBSAnnotator",
        ]
    )
    return candidates


def _legacy_install_dir_candidates() -> list[Path]:
    """Candidate locations where pre-packaging builds wrote user config.

    Historically the app stored ``program_names.json`` and ``scale_presets.json``
    next to the executable (``<install>/logs/``), which was destroyed by MSI
    upgrades. We probe those paths so an existing install can migrate its data
    the first time the new code runs.
    """
    candidates: list[Path] = []
    if getattr(sys, "frozen", False):
        candidates.append(Path(sys.executable).parent / "logs")
    # Development checkout fallback (repo root / logs).
    candidates.append(Path(__file__).resolve().parents[3] / "logs")
    return candidates


def _legacy_candidates() -> list[Path]:
    """All legacy directories to probe, ordered from most- to least-preferred."""
    return _legacy_qt_data_candidates() + _legacy_install_dir_candidates()


def migrate_legacy_file(filename: str) -> Path:
    """Copy a legacy install-dir config file into the user data dir if needed.

    Returns the destination path under :func:`user_data_dir` regardless of
    whether a migration occurred. Idempotent: if the destination already
    exists, nothing is copied (the user's newer data always wins).
    """
    destination = user_config_file(filename)
    if destination.exists():
        return destination

    for legacy_dir in _legacy_candidates():
        legacy_path = legacy_dir / filename
        if legacy_path.is_file():
            try:
                shutil.copy2(legacy_path, destination)
                logger.info("Migrated legacy config %s -> %s", legacy_path, destination)
            except OSError:
                logger.exception(
                    "Failed to migrate legacy config %s -> %s",
                    legacy_path,
                    destination,
                )
            break

    return destination
