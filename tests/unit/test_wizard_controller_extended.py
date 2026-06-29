"""More WizardController branches (mocks)."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from dbs_annotator.controllers.wizard_controller import WizardController


@pytest.fixture
def c():
    return WizardController()


def test_browse_save_location_simple_sets_path(c, tmp_path):
    view = MagicMock()
    view.file_path_edit.text.return_value = ""
    parent = MagicMock()
    out = tmp_path / "annot.tsv"
    with patch(
        "PySide6.QtWidgets.QFileDialog.getSaveFileName",
        return_value=(str(out), "TSV"),
    ):
        c.browse_save_location_simple(view, parent)
    view.file_path_edit.setText.assert_called()


def test_validate_annotations_file_empty_path_warns(c):
    view = MagicMock()
    view.file_path_edit.text.return_value = "  "
    parent = MagicMock()
    with patch("dbs_annotator.controllers.wizard_controller.QMessageBox.warning") as w:
        assert c.validate_annotations_file(view, parent) is False
        w.assert_called()


def test_validate_annotations_file_new_mode(c, tmp_path):
    p = tmp_path / "n.tsv"
    view = MagicMock()
    view.file_path_edit.text.return_value = str(p)
    view.current_file_mode = "new"
    assert c.validate_annotations_file(view, MagicMock()) is True
    c.session_data.close_file()


def test_validate_annotations_file_existing_mode(c, tmp_path):
    p = tmp_path / "e.tsv"
    p.write_text("date\ttime\ttimezone\tnotes\n", encoding="utf-8")
    view = MagicMock()
    view.file_path_edit.text.return_value = str(p)
    view.current_file_mode = "existing"
    assert c.validate_annotations_file(view, MagicMock()) is True
    c.session_data.close_file()


def test_validate_annotations_file_fallback_create(c, tmp_path):
    p = tmp_path / "newfile.tsv"
    view = MagicMock()
    view.file_path_edit.text.return_value = str(p)
    view.current_file_mode = None
    assert c.validate_annotations_file(view, MagicMock()) is True
    c.session_data.close_file()


def test_validate_annotations_file_init_error(c, tmp_path):
    p = tmp_path / "x.tsv"
    view = MagicMock()
    view.file_path_edit.text.return_value = str(p)
    view.current_file_mode = "new"
    with (
        patch.object(
            c.session_data,
            "initialize_simple_file",
            side_effect=OSError("fail"),
        ),
        patch("dbs_annotator.controllers.wizard_controller.QMessageBox.critical") as cr,
    ):
        assert c.validate_annotations_file(view, MagicMock()) is False
        cr.assert_called()


def test_insert_simple_annotation_skips_empty(c):
    view = MagicMock()
    view.get_annotation.return_value = "   "
    c.insert_simple_annotation(view)
    view.clear_annotation.assert_not_called()


def test_insert_simple_annotation_writes(c, tmp_path, monkeypatch):
    p = tmp_path / "a.tsv"
    c.session_data.initialize_simple_file(str(p))
    try:
        view = MagicMock()
        view.get_annotation.return_value = "note"
        monkeypatch.setattr(
            "dbs_annotator.controllers.wizard_controller.animate_button",
            lambda *a, **k: None,
        )
        c.insert_simple_annotation(view)
        view.clear_annotation.assert_called_once()
    finally:
        c.session_data.close_file()


def test_export_session_word_delegates(c, monkeypatch):
    called = {}

    def cap(*a, **k):
        called["ok"] = True

    monkeypatch.setattr(c.session_exporter, "export_to_word", cap)
    c.export_session_word(MagicMock())
    assert called["ok"]


def test_export_session_pdf_delegates(c, monkeypatch):
    called = {}

    def cap(*a, **k):
        called["ok"] = True

    monkeypatch.setattr(c.session_exporter, "export_to_pdf", cap)
    c.export_session_pdf(MagicMock())
    assert called["ok"]


def test_apply_clinical_preset_invokes_view(c):
    view = MagicMock()
    with patch.object(
        c,
        "on_add_clinical_scale",
        wraps=c.on_add_clinical_scale,
    ):
        c.apply_clinical_preset("OCD", view)
    view.apply_clinical_preset.assert_called_once_with("OCD")


def test_apply_session_preset_invokes_view(c):
    view = MagicMock()
    view.get_preset_button.return_value = None
    c.apply_session_preset("OCD", view)
    view.update_session_scales.assert_called()
