"""Shared pytest fixtures for Qt and the main wizard."""

from __future__ import annotations

import os
import sys

# Docs screenshots need real fonts and native styling. When DOCS_SCREENSHOT_DIR is
# set, prefer the platform GUI plugin on desktop OSes; unit tests stay offscreen.
if os.environ.get("DOCS_SCREENSHOT_DIR"):
    if sys.platform == "win32":
        os.environ["QT_QPA_PLATFORM"] = "windows"
    elif sys.platform == "darwin":
        os.environ["QT_QPA_PLATFORM"] = "cocoa"
    elif not os.environ.get("QT_QPA_PLATFORM"):
        os.environ["QT_QPA_PLATFORM"] = "offscreen"
else:
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

import pytest

from dbs_annotator.views.wizard_window import WizardWindow


@pytest.fixture
def wizard(qtbot, qapp):
    """Main wizard window bound to the session QApplication."""
    w = WizardWindow(qapp)
    qtbot.addWidget(w)
    w.show()
    return w


@pytest.fixture
def bids_like_tsv(tmp_path):
    """Minimal TSV path suitable for SessionData.open_file (new file)."""
    path = tmp_path / "sub-01_ses-20250101_task-prog_run-01_events.tsv"
    path.write_text("", encoding="utf-8")
    return path
