"""Unit tests for WizardController (aligned with current API)."""

from __future__ import annotations

import csv
import tempfile
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest
from PySide6.QtWidgets import QMessageBox

from dbs_annotator.controllers.wizard_controller import WizardController
from dbs_annotator.models import SessionData, StimulationParameters


@pytest.fixture
def controller():
    return WizardController()


class TestWizardController:
    def test_initialization(self, controller):
        assert controller.session_data is not None
        assert controller.current_stimulation is not None
        assert isinstance(controller.session_scales_names, list)
        assert controller.workflow_mode is None

    def test_session_data_initialization(self, controller):
        assert isinstance(controller.session_data, SessionData)
        assert not controller.session_data.is_file_open()

    def test_stimulation_parameters_initialization(self, controller):
        assert isinstance(controller.current_stimulation, StimulationParameters)

    @patch("dbs_annotator.controllers.wizard_controller.QMessageBox.question")
    def test_close_session_confirmation(self, mock_question, controller):
        mock_question.return_value = QMessageBox.StandardButton.Ok
        with tempfile.NamedTemporaryFile(mode="w", suffix=".tsv", delete=False) as f:
            controller.session_data.file_path = f.name
            controller.session_data.data = [{"test": "data"}]
            parent = MagicMock()
            controller.close_session(parent)
            mock_question.assert_called_once()
            parent.close.assert_called_once()

    def test_prepare_step3_passes_session_scales_data(self, controller):
        mock_view = MagicMock()
        controller.session_scales_data = [("YBOCS", "0", "10")]
        controller.current_stimulation.left_frequency = "130"
        controller.current_stimulation.left_amplitude = "3.5"
        controller.prepare_step3(mock_view)
        mock_view.update_session_scales.assert_called_once_with([("YBOCS", "0", "10")])
        mock_view.set_initial_stimulation_params.assert_called_once()


class TestWizardControllerInsertRow:
    def test_insert_session_row(self, tmp_path, monkeypatch):
        controller = WizardController()
        tsv = tmp_path / "session.tsv"
        controller.session_data.open_file(str(tsv))

        value_w = SimpleNamespace()
        value_w.isDisabled = lambda: False
        value_w.value = lambda: 4.0

        view = MagicMock()
        view.session_scale_value_edits = [("YBOCS", value_w)]
        view.session_left_stim_freq_edit.text.return_value = "130"
        view.session_right_stim_freq_edit.text.return_value = "130"
        view.session_left_amp_edit = MagicMock()
        view.session_right_amp_edit = MagicMock()
        view.session_left_amp_edit.text.return_value = "3.0"
        view.session_right_amp_edit.text.return_value = "3.0"
        view.get_left_cathode_text.return_value = "e1"
        view.get_left_anode_text.return_value = "e3"
        view.get_right_cathode_text.return_value = "e2"
        view.get_right_anode_text.return_value = "e4"
        view.session_left_pw_edit.text.return_value = "60"
        view.session_right_pw_edit.text.return_value = "60"
        view.session_notes_edit.toPlainText.return_value = ""
        monkeypatch.setattr(
            "dbs_annotator.controllers.wizard_controller.animate_button",
            lambda *a, **k: None,
        )

        before = controller.session_data.block_id
        controller.insert_session_row(view)
        assert controller.session_data.block_id == before + 1

    def test_insert_session_row_deactivated_scale_writes_nan_token(
        self, tmp_path, monkeypatch
    ):
        from dbs_annotator.models.clinical_scale import SESSION_SCALE_OMITTED_TSV

        controller = WizardController()
        tsv = tmp_path / "session.tsv"
        controller.session_data.open_file(str(tsv))

        value_w = SimpleNamespace()
        value_w.isDisabled = lambda: True
        value_w.value = lambda: 0

        view = MagicMock()
        view.session_scale_value_edits = [("Mood", value_w)]
        view.session_left_stim_freq_edit.text.return_value = "130"
        view.session_right_stim_freq_edit.text.return_value = "130"
        view.session_left_amp_edit = MagicMock()
        view.session_right_amp_edit = MagicMock()
        view.session_left_amp_edit.text.return_value = "3.0"
        view.session_right_amp_edit.text.return_value = "3.0"
        view.get_left_cathode_text.return_value = "e1"
        view.get_left_anode_text.return_value = "e3"
        view.get_right_cathode_text.return_value = "e2"
        view.get_right_anode_text.return_value = "e4"
        view.session_left_pw_edit.text.return_value = "60"
        view.session_right_pw_edit.text.return_value = "60"
        view.session_notes_edit.toPlainText.return_value = ""
        monkeypatch.setattr(
            "dbs_annotator.controllers.wizard_controller.animate_button",
            lambda *a, **k: None,
        )

        controller.insert_session_row(view)

        with open(tsv, newline="", encoding="utf-8") as f:
            rows = list(csv.DictReader(f, delimiter="\t"))
        assert len(rows) == 1
        assert rows[0]["scale_name"] == "Mood"
        assert rows[0]["scale_value"] == SESSION_SCALE_OMITTED_TSV


class TestValidateStep2Filtering:
    def test_validate_step2_skips_incomplete_rows(self):
        c = WizardController()
        view = MagicMock()
        row_full = (MagicMock(), MagicMock(), MagicMock())
        row_full[0].text.return_value = "Mood"
        row_full[1].text.return_value = "0"
        row_full[2].text.return_value = "10"
        row_partial = (MagicMock(), MagicMock(), MagicMock())
        row_partial[0].text.return_value = "Anxiety"
        row_partial[1].text.return_value = ""
        row_partial[2].text.return_value = "10"
        view.session_scales_rows = [row_full, row_partial]
        c.validate_step2(view)
        assert c.session_scales_names == ["Mood"]
        assert c.session_scales_data == [("Mood", "0", "10")]
