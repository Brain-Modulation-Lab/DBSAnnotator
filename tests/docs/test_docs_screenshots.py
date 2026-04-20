"""Generate UI screenshots for documentation artifacts.

These tests are opt-in and intended for a dedicated workflow. They do not run
in normal unit/integration test jobs.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest
from PySide6.QtTest import QTest

from dbs_annotator.models.electrode_viewer import ElectrodeCanvas
from dbs_annotator.views.annotation_only_view import AnnotationsFileView


def _screenshot_dir() -> Path:
    out_dir = os.environ.get("DOCS_SCREENSHOT_DIR")
    if not out_dir:
        pytest.skip("DOCS_SCREENSHOT_DIR is not set; skipping screenshot generation.")
    path = Path(out_dir)
    path.mkdir(parents=True, exist_ok=True)
    return path


@pytest.mark.docs_screenshot
@pytest.mark.gui
def test_capture_wizard_window(wizard) -> None:
    out = _screenshot_dir()
    wizard.resize(1400, 900)
    wizard.show()
    QTest.qWait(250)
    assert wizard.grab().save(str(out / "wizard-window.png"))


@pytest.mark.docs_screenshot
@pytest.mark.gui
def test_capture_annotation_view(qtbot, qapp) -> None:
    out = _screenshot_dir()
    view = AnnotationsFileView()
    qtbot.addWidget(view)
    view.resize(1200, 800)
    view.show()
    QTest.qWait(250)
    assert view.grab().save(str(out / "annotation-only-view.png"))


@pytest.mark.docs_screenshot
@pytest.mark.gui
def test_capture_electrode_canvas(qtbot) -> None:
    out = _screenshot_dir()
    canvas = ElectrodeCanvas()
    qtbot.addWidget(canvas)
    canvas.resize(420, 760)
    canvas.show()
    QTest.qWait(250)
    assert canvas.grab().save(str(out / "electrode-canvas.png"))
