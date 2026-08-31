"""Unit tests for utilities."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest
from PySide6.QtWidgets import QApplication

from dbs_annotator.utils import animate_button, responsive
from dbs_annotator.utils.theme_manager import Theme, get_theme_manager


@pytest.fixture(scope="module")
def qapp_module():
    app = QApplication.instance()
    if app is None:
        app = QApplication([])
    yield app


class TestAnimateButton:
    @patch("dbs_annotator.utils.graphics.QTimer.singleShot")
    def test_animate_button_schedules_timer(self, mock_timer):
        mock_button = MagicMock()
        animate_button(mock_button, pulse_count=2)
        mock_timer.assert_called()
        mock_button.setStyleSheet.assert_called()


class TestThemeManager:
    def test_apply_theme_sets_stylesheet(self, qapp_module):
        mgr = get_theme_manager()
        mgr.apply_theme(Theme.LIGHT, qapp_module)
        assert isinstance(qapp_module.styleSheet(), str)

    def test_get_current_theme(self):
        mgr = get_theme_manager()
        assert isinstance(mgr.get_current_theme(), Theme)

    def test_toggle_theme_returns_theme(self, qapp_module):
        mgr = get_theme_manager()
        t = mgr.toggle_theme(qapp_module)
        assert isinstance(t, Theme)


class TestResponsive:
    def test_scale_value_explicit_scale(self):
        assert responsive.scale_value(100, dpi_scale=1.0) == 100
        assert responsive.scale_value(100, dpi_scale=1.5) == 150

    def test_scale_font_size_explicit_scale(self):
        assert responsive.scale_font_size(12, dpi_scale=1.0) == 12
        out = responsive.scale_font_size(20, dpi_scale=2.0)
        assert 8 <= out <= 24

    def test_get_responsive_stylesheet_variables(self):
        d = responsive.get_responsive_stylesheet_variables(dpi_scale=1.25)
        assert isinstance(d, dict)
        assert len(d) > 0
