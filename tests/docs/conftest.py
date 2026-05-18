"""Fixtures for documentation screenshot generation."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from dbs_annotator.views.wizard_window import WizardWindow
from tests.docs.screenshot_helpers import prepare_qt_for_docs


def pytest_collection_modifyitems(items) -> None:
    """Docs screenshot walkthrough needs more than the default 3s test timeout."""
    for item in items:
        if item.get_closest_marker("docs_screenshot") is not None:
            item.add_marker(pytest.mark.timeout(300))


@pytest.fixture
def wizard(qtbot, qapp):
    """Wizard with production theme/fonts applied (readable text in PNGs)."""
    prepare_qt_for_docs(qapp)
    # Avoid background update checks (network/COM) during screenshot capture.
    with (
        patch("dbs_annotator.views.wizard_window.UpdateChecker") as checker_cls,
        patch("dbs_annotator.views.wizard_window.QTimer.singleShot"),
    ):
        checker_cls.return_value = MagicMock()
        window = WizardWindow(qapp)
    qtbot.addWidget(window)
    window.show()
    return window
