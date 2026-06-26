"""Extra WizardWindow navigation and chrome (pytest-qt)."""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest
from PySide6.QtCore import Qt

pytestmark = [pytest.mark.gui, pytest.mark.slow]


def test_theme_toggle_invokes_theme_manager(wizard, qtbot, monkeypatch):
    mock_tm = MagicMock()
    mock_tm.is_dark_mode.return_value = False
    mock_tm.get_current_theme.return_value = "light"
    mock_tm.load_stylesheet.return_value = ""
    monkeypatch.setattr(
        "dbs_annotator.views.wizard_window.get_theme_manager",
        lambda: mock_tm,
    )
    qtbot.mouseClick(wizard.theme_toggle_btn, Qt.MouseButton.LeftButton)
    mock_tm.toggle_theme.assert_called_once_with(wizard.app)


def test_go_back_from_step2_to_step1_full_workflow(wizard, qtbot):
    wizard.workflow_mode = "full"
    wizard._load_full_workflow_views()
    wizard.current_step = 2
    wizard.stack.setCurrentWidget(wizard.step2_view)
    wizard._go_back()
    assert wizard.current_step == 1
    assert wizard.stack.currentWidget() is wizard.step1_view


def test_go_back_from_step1_to_step0_full_workflow(wizard, qtbot):
    wizard.workflow_mode = "full"
    wizard._load_full_workflow_views()
    wizard.current_step = 1
    wizard.stack.setCurrentWidget(wizard.step1_view)
    wizard._go_back()
    assert wizard.current_step == 0
    assert wizard.stack.currentWidget() is wizard.step0_view


def test_go_back_annotations_only_step1_to_step0(wizard, qtbot):
    wizard.workflow_mode = "annotations_only"
    wizard._load_annotations_only_views()
    wizard.current_step = 1
    wizard.stack.setCurrentWidget(wizard.annotations_file_view)
    wizard._go_back()
    assert wizard.current_step == 0
    assert wizard.stack.currentWidget() is wizard.step0_view


def test_main_workflow_window_allows_maximize(wizard, qtbot):
    qtbot.mouseClick(wizard.step0_view.full_mode_button, Qt.MouseButton.LeftButton)
    max_size = wizard.maximumSize()
    min_size = wizard.minimumSize()
    assert max_size.width() > min_size.width()
    assert max_size.height() > min_size.height()
    flags = wizard.windowFlags()
    assert flags & Qt.WindowType.WindowMaximizeButtonHint
    assert flags & Qt.WindowType.WindowSystemMenuHint
    assert flags & Qt.WindowType.WindowCloseButtonHint
    assert flags & Qt.WindowType.WindowMinimizeButtonHint


def test_longitudinal_mode_sets_workflow_and_loads_view(wizard, qtbot):
    assert wizard.longitudinal_file_view is None
    wizard._select_longitudinal_report()
    assert wizard.workflow_mode == "longitudinal"
    assert wizard.longitudinal_file_view is not None
    assert wizard.stack.currentWidget() is wizard.longitudinal_file_view


def test_clinical_preset_dystonia_button_not_pinched(wizard, qtbot):
    """Preset pills must be wide enough for longer labels such as Dystonia."""
    qtbot.mouseClick(wizard.step0_view.full_mode_button, Qt.MouseButton.LeftButton)
    step1 = wizard.step1_view
    assert step1 is not None

    def dystonia_ready() -> bool:
        btn = step1.get_preset_button("Dystonia")
        return btn is not None and btn.minimumWidth() >= 72

    qtbot.waitUntil(dystonia_ready, timeout=2000)


def test_clinical_preset_buttons_survive_settings_refresh(wizard, qtbot):
    """Adding a preset in settings must not collapse the horizontal button strip."""
    qtbot.mouseClick(wizard.step0_view.full_mode_button, Qt.MouseButton.LeftButton)
    step1 = wizard.step1_view
    assert step1 is not None
    initial_count = len(step1.preset_buttons)
    assert initial_count > 0

    preset_name = "LongClinicalPreset"
    updated = dict(step1.clinical_presets)
    updated[preset_name] = ["MDS-UPDRS", "Y-BOCS-o"]
    step1._on_presets_changed(updated)

    def strip_ready() -> bool:
        btn = step1.get_preset_button(preset_name)
        return (
            btn is not None
            and btn.text() == preset_name
            and step1.preset_scroll_content.width() > 20
            and step1.preset_scroll_area.height() > 10
        )

    qtbot.waitUntil(strip_ready, timeout=2000)
