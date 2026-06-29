"""Smoke tests for PySide6 views."""

from __future__ import annotations

import pytest
from PySide6.QtWidgets import QPushButton

from dbs_annotator.views import (
    Step0View,
    Step1View,
    Step2View,
    Step3View,
    WizardWindow,
)


@pytest.mark.gui
def test_step0_creates(qtbot, qapp):
    view = Step0View()
    qtbot.addWidget(view)
    assert view.full_mode_button is not None
    assert view.annotations_only_button is not None
    assert isinstance(view.full_mode_button, QPushButton)


@pytest.mark.gui
def test_step1_creates(qtbot, qapp):
    view = Step1View()
    qtbot.addWidget(view)
    assert view.next_button is not None


@pytest.mark.gui
def test_step1_clinical_preset_scores_persist_across_switches(qtbot, qapp):
    view = Step1View()
    qtbot.addWidget(view)

    view.update_clinical_scales(
        [],
        on_add_callback=lambda: None,
        on_remove_callback=lambda row: None,
    )

    preset_names = list(view.clinical_presets.keys())
    if len(preset_names) < 2:
        pytest.skip("Need at least two clinical presets")

    first, second = preset_names[0], preset_names[1]
    view.apply_clinical_preset(first)

    _, score_edit, _ = view.clinical_scales_rows[0]
    score_edit.setText("42")

    view.apply_clinical_preset(second)
    view.apply_clinical_preset(first)

    _, restored_score, _ = view.clinical_scales_rows[0]
    assert restored_score.text() == "42"


@pytest.mark.gui
def test_step1_stim_preset_combo_fills_line_edit(qtbot, qapp):
    view = Step1View()
    qtbot.addWidget(view)
    combo = view.left_stim_freq_presets_combo
    edit = view.left_stim_freq_edit
    assert combo.count() > 1
    combo.setCurrentIndex(1)
    assert edit.text() == combo.itemText(1)
    assert combo.currentIndex() == 0


@pytest.mark.gui
def test_step2_creates(qtbot, qapp):
    view = Step2View()
    qtbot.addWidget(view)
    assert view.next_button is not None


@pytest.mark.gui
def test_step3_export_menu_two_actions(qtbot, qapp):
    view = Step3View()
    qtbot.addWidget(view)
    assert view.export_menu is not None
    assert len(view.export_menu.actions()) == 2
    assert view.export_word_action is not None
    assert view.export_pdf_action is not None


@pytest.mark.gui
def test_wizard_window_creates(wizard):
    assert wizard.controller is not None
    assert wizard.step0_view is not None


@pytest.mark.gui
def test_all_step_views_importable(qtbot, qapp):
    for cls in (Step0View, Step1View, Step2View, Step3View):
        w = cls()
        qtbot.addWidget(w)
    win = WizardWindow(qapp)
    qtbot.addWidget(win)
