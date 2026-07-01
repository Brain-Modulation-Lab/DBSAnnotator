"""Unit tests for WizardWindow screen geometry clamping."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest
from PySide6.QtCore import QRect, QSize

from dbs_annotator.config import WINDOW_MIN_SIZE


def _mock_screen(*, x: int, y: int, width: int, height: int) -> MagicMock:
    screen = MagicMock()
    screen.availableGeometry.return_value = QRect(x, y, width, height)
    return screen


@pytest.mark.gui
def test_effective_min_size_caps_to_screen(wizard):
    screen = _mock_screen(x=0, y=0, width=1280, height=600)
    effective = wizard._effective_min_size(screen)
    assert effective == QSize(1000, 600)


@pytest.mark.gui
def test_clamp_to_screen_lowers_minimum_on_small_display(wizard):
    wizard.current_step = 1
    wizard.setMinimumSize(WINDOW_MIN_SIZE["width"], WINDOW_MIN_SIZE["height"])
    wizard.setGeometry(0, -80, 1000, 700)

    screen = _mock_screen(x=0, y=0, width=1280, height=600)
    with (
        patch.object(wizard.app, "screenAt", return_value=screen),
        patch.object(wizard.app, "primaryScreen", return_value=screen),
    ):
        wizard._clamp_to_screen()

    geo = wizard.geometry()
    rect = screen.availableGeometry()
    assert geo.height() == 600
    assert geo.y() >= rect.y()
    assert geo.y() + geo.height() <= rect.bottom() + 1
    assert wizard.minimumSize().height() <= 600


@pytest.mark.gui
def test_fit_geometry_to_rect_shrinks_tall_window(wizard):
    wizard.current_step = 1
    wizard.setMinimumSize(WINDOW_MIN_SIZE["width"], WINDOW_MIN_SIZE["height"])
    wizard.setGeometry(0, -120, 1000, 700)

    rect = QRect(0, 0, 1280, 600)
    wizard._fit_geometry_to_rect(rect)

    geo = wizard.geometry()
    assert geo.height() == 600
    assert geo.y() == 0


@pytest.mark.gui
def test_schedule_clamp_starts_timer(wizard):
    wizard.current_step = 1
    wizard._schedule_clamp_to_screen()
    assert wizard._clamp_timer.isActive()


@pytest.mark.gui
def test_clamp_to_screen_skips_dynamic_minimum_on_step0(wizard):
    wizard.current_step = 0
    wizard.setMinimumSize(620, 340)
    wizard.setGeometry(0, -40, 620, 340)

    screen = _mock_screen(x=0, y=0, width=1280, height=600)
    with (
        patch.object(wizard.app, "screenAt", return_value=screen),
        patch.object(wizard.app, "primaryScreen", return_value=screen),
    ):
        wizard._clamp_to_screen()

    assert wizard.minimumSize() == QSize(620, 340)


@pytest.mark.gui
def test_on_screen_changed_reclamps_main_workflow(wizard):
    wizard.current_step = 1
    wizard.setMinimumSize(WINDOW_MIN_SIZE["width"], WINDOW_MIN_SIZE["height"])
    wizard.setGeometry(0, -80, 1000, 700)

    screen = _mock_screen(x=0, y=0, width=1280, height=600)
    with (
        patch.object(wizard.app, "screenAt", return_value=screen),
        patch.object(wizard.app, "primaryScreen", return_value=screen),
        patch.object(wizard, "_clamp_to_screen") as clamp_mock,
    ):
        wizard._on_screen_changed(screen)

    clamp_mock.assert_called_once()


@pytest.mark.gui
def test_on_screen_changed_ignored_on_step0(wizard):
    wizard.current_step = 0
    with patch.object(wizard, "_clamp_to_screen") as clamp_mock:
        wizard._on_screen_changed(None)
    clamp_mock.assert_not_called()
