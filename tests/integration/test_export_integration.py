"""Integration tests for SessionExporter (PySide6, small fixtures)."""

from __future__ import annotations

from unittest.mock import patch

import pandas as pd
import pytest

from dbs_annotator.models.session_data import SessionData
from dbs_annotator.utils.session_exporter import SessionExporter


@pytest.fixture
def sample_tsv(tmp_path):
    rows = [
        {
            "date": "2024-01-15",
            "time": "09:30:00",
            "block_ID": "1",
            "is_initial": "1",
            "scale_name": "YBOCS",
            "scale_value": "20",
            "notes": "n",
        },
        {
            "date": "2024-01-15",
            "time": "10:30:00",
            "block_ID": "2",
            "is_initial": "0",
            "scale_name": "YBOCS",
            "scale_value": "18",
            "notes": "n2",
        },
    ]
    p = tmp_path / "sub-01_task-prog_run-01_events.tsv"
    pd.DataFrame(rows).to_csv(p, sep="\t", index=False)
    return p


def test_export_to_word_integration(monkeypatch, tmp_path, sample_tsv):
    sd = SessionData()
    sd.open_file_append(str(sample_tsv))
    try:
        exporter = SessionExporter(sd)
        out = tmp_path / "report.docx"
        monkeypatch.setattr(exporter, "_export_to_word_path", lambda *a, **k: True)
        with (
            patch(
                "PySide6.QtWidgets.QFileDialog.getSaveFileName",
                return_value=(str(out), "Word"),
            ),
            patch(
                "dbs_annotator.utils.session_exporter.SessionExporter._show_transient_message",
            ),
        ):
            assert exporter.export_to_word() is True
    finally:
        sd.close_file()


def test_export_to_pdf_integration(monkeypatch, tmp_path, sample_tsv):
    sd = SessionData()
    sd.open_file_append(str(sample_tsv))
    try:
        exporter = SessionExporter(sd)
        pdf = tmp_path / "report.pdf"
        monkeypatch.setattr(exporter, "_export_to_word_path", lambda *a, **k: True)
        monkeypatch.setattr(exporter, "_convert_docx_to_pdf", lambda *a, **k: None)
        monkeypatch.setattr(exporter, "_open_file", lambda *a, **k: None)
        with (
            patch(
                "PySide6.QtWidgets.QFileDialog.getSaveFileName",
                return_value=(str(pdf), "PDF"),
            ),
            patch(
                "dbs_annotator.utils.session_exporter.SessionExporter._show_transient_message",
            ),
        ):
            assert exporter.export_to_pdf() is True
    finally:
        sd.close_file()


def test_export_word_no_data_warns():
    empty = SessionData()
    ex = SessionExporter(empty)
    with patch("dbs_annotator.utils.session_exporter.QMessageBox.warning") as w:
        assert ex.export_to_word() is False
        w.assert_called()


def test_export_word_no_file_warns():
    sd = SessionData()
    sd.file_path = None
    ex = SessionExporter(sd)
    with patch("dbs_annotator.utils.session_exporter.QMessageBox.warning") as w:
        assert ex.export_to_word() is False
        w.assert_called()


@pytest.mark.gui
def test_step3_export_actions_exist(qtbot, qapp):
    from dbs_annotator.views.step3_view import Step3View

    v = Step3View()
    qtbot.addWidget(v)
    assert v.export_word_action is not None
    assert v.export_pdf_action is not None
    assert len(v.export_menu.actions()) == 2
