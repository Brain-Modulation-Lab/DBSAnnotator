"""SessionExporter unit tests (PySide6 dialogs, mocked heavy paths)."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

from dbs_annotator.models.session_data import SessionData
from dbs_annotator.utils.session_exporter import SessionExporter


def test_init():
    mock_sd = MagicMock(spec=SessionData)
    exporter = SessionExporter(mock_sd)
    assert exporter.session_data is mock_sd


def test_export_to_word_no_file_open():
    mock_sd = MagicMock(spec=SessionData)
    mock_sd.is_file_open.return_value = False
    exporter = SessionExporter(mock_sd)
    with patch("dbs_annotator.utils.session_exporter.QMessageBox.warning") as w:
        assert exporter.export_to_word() is False
        w.assert_called_once()


def test_export_to_word_user_cancels_dialog():
    mock_sd = MagicMock(spec=SessionData)
    mock_sd.is_file_open.return_value = True
    mock_sd.file_path = r"C:\data\sub-01_task-x_events.tsv"
    exporter = SessionExporter(mock_sd)
    with (
        patch(
            "PySide6.QtWidgets.QFileDialog.getSaveFileName",
            return_value=("", ""),
        ),
    ):
        assert exporter.export_to_word() is False


def test_export_to_word_success(monkeypatch, tmp_path):
    mock_sd = MagicMock(spec=SessionData)
    mock_sd.is_file_open.return_value = True
    mock_sd.file_path = str(tmp_path / "sub-01_task-prog_events.tsv")

    out = tmp_path / "out.docx"
    exporter = SessionExporter(mock_sd)
    monkeypatch.setattr(
        exporter,
        "_export_to_word_path",
        lambda path, sections=None: True,
    )
    with (
        patch(
            "PySide6.QtWidgets.QFileDialog.getSaveFileName",
            return_value=(str(out), "Word"),
        ),
        patch(
            "dbs_annotator.utils.session_exporter.SessionExporter._show_transient_message"
        ),
    ):
        assert exporter.export_to_word() is True


def test_export_to_pdf_success(monkeypatch, tmp_path):
    tsv = tmp_path / "sub-01_task-prog_events.tsv"
    tsv.write_text(
        "date\tblock_ID\tis_initial\tscale_name\tscale_value\n"
        "2024-01-15\t0\t1\tYBOCS\t20\n",
        encoding="utf-8",
    )
    mock_sd = MagicMock(spec=SessionData)
    mock_sd.is_file_open.return_value = True
    mock_sd.file_path = str(tsv)

    pdf = tmp_path / "out.pdf"
    exporter = SessionExporter(mock_sd)
    monkeypatch.setattr(exporter, "_export_to_word_path", lambda *a, **k: True)
    monkeypatch.setattr(exporter, "_convert_docx_to_pdf", lambda *a, **k: None)
    monkeypatch.setattr(exporter, "_open_file", lambda *a, **k: None)
    with (
        patch(
            "PySide6.QtWidgets.QFileDialog.getSaveFileName",
            return_value=(str(pdf), "PDF"),
        ),
        patch(
            "dbs_annotator.utils.session_exporter.SessionExporter._show_transient_message"
        ),
    ):
        assert exporter.export_to_pdf() is True


def test_export_to_pdf_conversion_error_shows_critical(monkeypatch, tmp_path):
    tsv = tmp_path / "sub-01_task-prog_events.tsv"
    tsv.write_text(
        "date\tblock_ID\tis_initial\tscale_name\tscale_value\n"
        "2024-01-15\t0\t1\tYBOCS\t20\n",
        encoding="utf-8",
    )
    mock_sd = MagicMock(spec=SessionData)
    mock_sd.is_file_open.return_value = True
    mock_sd.file_path = str(tsv)
    exporter = SessionExporter(mock_sd)
    monkeypatch.setattr(exporter, "_export_to_word_path", lambda *a, **k: True)

    def boom(*_a, **_k):
        raise RuntimeError("no converter")

    monkeypatch.setattr(exporter, "_convert_docx_to_pdf", boom)
    with (
        patch(
            "PySide6.QtWidgets.QFileDialog.getSaveFileName",
            return_value=(str(tmp_path / "out.pdf"), "PDF"),
        ),
        patch("dbs_annotator.utils.session_exporter.QMessageBox.critical") as crit,
    ):
        assert exporter.export_to_pdf() is False
        crit.assert_called_once()


def test_set_scale_optimization_prefs():
    exporter = SessionExporter(MagicMock(spec=SessionData))
    exporter.set_scale_optimization_prefs([("Mood", "0", "10", "low", "")])
    assert len(exporter.scale_optimization_prefs) == 1
