"""Qt behavior for export_dialog (pytest-qt)."""

from __future__ import annotations

import pytest
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QDialog, QDialogButtonBox

from dbs_annotator.views.export_dialog import (
    ReportSectionsDialog,
    ScaleTargetValuesDialog,
)


@pytest.mark.gui
def test_scale_target_dialog_prefs_default_min(qtbot, qapp):
    d = ScaleTargetValuesDialog(
        [("Mood", "0", "10")],
        clinical_scales=[("YBOCS", "0", "40")],
    )
    qtbot.addWidget(d)
    prefs = d.get_scale_prefs()
    assert prefs[0][0] == "Mood"
    assert prefs[0][3] == "min"
    clinical = d.get_clinical_scale_prefs()
    assert clinical[0][0] == "YBOCS"
    assert clinical[0][3] == "min"
    d.reject()


@pytest.mark.gui
def test_scale_target_dialog_unchecked_is_ignore(qtbot, qapp):
    d = ScaleTargetValuesDialog([("Mood", "0", "10")])
    qtbot.addWidget(d)
    row = d._rows[0]
    checkbox = row[3]
    checkbox.setChecked(False)
    prefs = d.get_scale_prefs()
    assert prefs[0][3] == "ignore"
    d.close()


@pytest.mark.gui
def test_report_sections_parent_child_selection(qtbot, qapp):
    children = [
        ("session_data_graph", "Graph", True),
        ("session_data_table", "Table", False),
    ]
    sections = [
        ("a", "Section A", True, None),
        ("session_data", "Session Data", True, children),
    ]
    d = ReportSectionsDialog(sections)
    qtbot.addWidget(d)
    # Parent starts checked and forces all children checked in __init__.
    for key, cb in d._checkboxes:
        if key == "session_data_table":
            cb.setChecked(False)
            break
    sel = d.get_selected_sections()
    assert "a" in sel
    assert "session_data_graph" in sel
    assert "session_data_table" not in sel
    d.accept()


@pytest.mark.gui
def test_report_sections_cancel_button(qtbot, qapp):
    d = ReportSectionsDialog([("x", "X", True, None)])
    qtbot.addWidget(d)
    box = d.findChild(QDialogButtonBox)
    assert box is not None
    cancel = box.button(QDialogButtonBox.StandardButton.Cancel)
    qtbot.mouseClick(cancel, Qt.MouseButton.LeftButton)
    assert d.result() == QDialog.DialogCode.Rejected
