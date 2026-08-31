"""Targeted QMessageBox paths on step1 / step3."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest
from PySide6.QtWidgets import QListWidget, QMessageBox

from dbs_annotator.views.step1_view import Step1View
from dbs_annotator.views.step3_view import Step3View


@pytest.mark.gui
def test_step1_add_program_empty_name_warns(qtbot, qapp):
    view = Step1View()
    qtbot.addWidget(view)
    lw = QListWidget()
    pc = MagicMock()
    with patch.object(QMessageBox, "warning") as w:
        view._add_program_to_list("", lw, pc)
        w.assert_called()


@pytest.mark.gui
def test_step1_remove_program_none_selected_warns(qtbot, qapp):
    view = Step1View()
    qtbot.addWidget(view)
    lw = QListWidget()
    pc = MagicMock()
    with patch.object(QMessageBox, "warning") as w:
        view._remove_selected_program(lw, pc, [])
        w.assert_called()


@pytest.mark.gui
def test_step3_undo_last_entry_user_declines(qtbot, qapp):
    view = Step3View()
    qtbot.addWidget(view)
    with patch.object(
        QMessageBox,
        "question",
        return_value=QMessageBox.StandardButton.No,
    ) as q:
        view._undo_last_entry()
        q.assert_called()
