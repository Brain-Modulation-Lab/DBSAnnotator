"""GUI integration tests for the main wizard (PySide6, pytest-qt)."""

from __future__ import annotations

from unittest.mock import patch

import pytest
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication

from dbs_annotator.views.annotation_only_view import AnnotationsFileView


@pytest.mark.gui
@pytest.mark.integration
def test_full_workflow_reaches_step3(wizard, qtbot, bids_like_tsv):
    qtbot.mouseClick(wizard.step0_view.full_mode_button, Qt.MouseButton.LeftButton)
    QApplication.processEvents()
    assert wizard.workflow_mode == "full"
    assert wizard.current_step == 1

    s1 = wizard.step1_view
    assert s1 is not None
    s1.file_path_edit.setText(str(bids_like_tsv))

    if s1.clinical_scales_rows:
        ne, se, _ = s1.clinical_scales_rows[0]
        ne.setText("YBOCS")
        se.setText("12")

    s1.left_stim_freq_edit.setText("130")
    s1.right_stim_freq_edit.setText("130")

    qtbot.mouseClick(s1.next_button, Qt.MouseButton.LeftButton)
    QApplication.processEvents()
    assert wizard.current_step == 2

    s2 = wizard.step2_view
    assert s2 is not None
    if s2.session_scales_rows:
        name_e, min_e, max_e, *_rest = s2.session_scales_rows[0]
        name_e.setText("Mood")
        min_e.setText("0")
        max_e.setText("10")

    qtbot.mouseClick(s2.next_button, Qt.MouseButton.LeftButton)
    QApplication.processEvents()
    assert wizard.current_step == 3
    assert wizard.stack.currentWidget() is wizard.step3_view
    assert "Mood" in wizard.controller.session_scales_names


@pytest.mark.gui
@pytest.mark.integration
def test_annotations_only_opens_file_view(wizard, qtbot):
    qtbot.mouseClick(
        wizard.step0_view.annotations_only_button,
        Qt.MouseButton.LeftButton,
    )
    QApplication.processEvents()
    assert wizard.workflow_mode == "annotations_only"
    assert isinstance(wizard.stack.currentWidget(), AnnotationsFileView)


@pytest.mark.gui
@pytest.mark.integration
def test_step1_next_blocked_without_file_path(wizard, qtbot):
    qtbot.mouseClick(wizard.step0_view.full_mode_button, Qt.MouseButton.LeftButton)
    QApplication.processEvents()
    s1 = wizard.step1_view
    s1.file_path_edit.setText("")
    with patch("dbs_annotator.controllers.wizard_controller.QMessageBox.warning") as w:
        qtbot.mouseClick(s1.next_button, Qt.MouseButton.LeftButton)
        w.assert_called()
    assert wizard.current_step == 1


@pytest.mark.gui
@pytest.mark.integration
def test_navigation_back_from_step2(wizard, qtbot, bids_like_tsv):
    qtbot.mouseClick(wizard.step0_view.full_mode_button, Qt.MouseButton.LeftButton)
    QApplication.processEvents()
    s1 = wizard.step1_view
    s1.file_path_edit.setText(str(bids_like_tsv))
    qtbot.mouseClick(s1.next_button, Qt.MouseButton.LeftButton)
    QApplication.processEvents()
    assert wizard.current_step == 2
    qtbot.mouseClick(wizard.back_button, Qt.MouseButton.LeftButton)
    QApplication.processEvents()
    assert wizard.current_step == 1
