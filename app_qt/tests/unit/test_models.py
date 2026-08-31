"""
Unit tests for data models.
"""

import os
import tempfile

from dbs_annotator.models import (
    ClinicalScale,
    SessionData,
    SessionScale,
    StimulationParameters,
)
from dbs_annotator.models.clinical_scale import (
    SESSION_SCALE_OMITTED_TSV,
    is_session_scale_value_omitted,
)


def _sample_stimulation() -> StimulationParameters:
    return StimulationParameters(
        left_frequency="130",
        left_cathode="e1",
        left_anode="e3",
        left_amplitude="3.5",
        left_pulse_width="60",
        right_frequency="130",
        right_cathode="e2",
        right_anode="e4",
        right_amplitude="4.0",
        right_pulse_width="60",
    )


class TestClinicalScale:
    def test_creation(self):
        scale = ClinicalScale(name="YBOCS", value="25")
        assert scale.name == "YBOCS"
        assert scale.value == "25"

    def test_is_valid_with_both_fields(self):
        scale = ClinicalScale(name="MADRS", value="10")
        assert scale.is_valid() is True

    def test_is_valid_without_value(self):
        scale = ClinicalScale(name="UPDRS", value=None)
        assert scale.is_valid() is False

    def test_is_valid_with_empty_strings(self):
        scale = ClinicalScale(name="", value="")
        assert scale.is_valid() is False

    def test_repr(self):
        scale = ClinicalScale(name="FTM", value="8")
        assert "FTM" in repr(scale)
        assert "8" in repr(scale)


class TestSessionScale:
    def test_creation(self):
        scale = SessionScale(name="Mood", min_value="0", max_value="10")
        assert scale.name == "Mood"
        assert scale.min_value == "0"
        assert scale.max_value == "10"
        assert scale.current_value is None

    def test_creation_with_current_value(self):
        scale = SessionScale(
            name="Anxiety", min_value="0", max_value="10", current_value="7"
        )
        assert scale.current_value == "7"

    def test_is_valid(self):
        scale = SessionScale(name="Energy")
        assert scale.is_valid() is True

        empty_scale = SessionScale(name="")
        assert empty_scale.is_valid() is False

    def test_has_value(self):
        scale = SessionScale(name="OCD", current_value="5")
        assert scale.has_value() is True

        scale_no_value = SessionScale(name="Tremor")
        assert scale_no_value.has_value() is False

        scale_nan_token = SessionScale(
            name="Mood", current_value=SESSION_SCALE_OMITTED_TSV
        )
        assert scale_nan_token.has_value() is True


def test_is_session_scale_value_omitted():
    assert is_session_scale_value_omitted(None) is True
    assert is_session_scale_value_omitted("") is True
    assert is_session_scale_value_omitted("  ") is True
    assert is_session_scale_value_omitted("NaN") is True
    assert is_session_scale_value_omitted("nan") is True
    assert is_session_scale_value_omitted(float("nan")) is True
    assert is_session_scale_value_omitted("0") is False
    assert is_session_scale_value_omitted("0.00") is False
    assert is_session_scale_value_omitted(0) is False


class TestStimulationParameters:
    def test_creation(self):
        params = _sample_stimulation()
        assert params.left_frequency == "130"
        assert params.left_cathode == "e1"
        assert params.right_amplitude == "4.0"

    def test_to_dict(self):
        params = StimulationParameters(
            left_frequency="130",
            left_cathode="e1",
            left_amplitude="3.5",
        )
        result = params.to_dict()
        assert result["left_stim_freq"] == "130"
        assert result["left_cathode"] == "e1"
        assert result["left_amplitude"] == "3.5"
        assert "right_cathode" in result

    def test_from_dict(self):
        data = {
            "left_stim_freq": "130",
            "left_cathode": "e1",
            "left_amplitude": "3.5",
            "left_pulse_width": "60",
            "right_cathode": "e2",
            "right_amplitude": "4.0",
            "right_pulse_width": "60",
        }
        params = StimulationParameters.from_dict(data)
        assert params.left_frequency == "130"
        assert params.left_cathode == "e1"
        assert params.right_pulse_width == "60"

    def test_copy(self):
        original = StimulationParameters(left_frequency="130", left_cathode="e1")
        copy = original.copy()
        assert copy.left_frequency == original.left_frequency
        assert copy.left_cathode == original.left_cathode
        assert copy is not original


class TestSessionData:
    def test_creation(self):
        session = SessionData()
        assert session.file_path is None
        assert session.tsv_file is None
        assert session.block_id == 0

    def test_open_and_close_file(self):
        with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".tsv") as tmp:
            tmp_path = tmp.name

        try:
            session = SessionData()
            session.open_file(tmp_path)
            assert session.is_file_open() is True
            assert session.file_path == tmp_path
            assert session.tsv_writer is not None
            session.close_file()
            assert session.is_file_open() is False
            assert session.tsv_file is None
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

    def test_write_clinical_scales(self):
        with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".tsv") as tmp:
            tmp_path = tmp.name

        try:
            session = SessionData(tmp_path)
            scales = [
                ClinicalScale(name="YBOCS", value="25"),
                ClinicalScale(name="MADRS", value="10"),
            ]
            stimulation = _sample_stimulation()
            session.write_clinical_scales(scales, stimulation, notes="Test notes")
            assert session.block_id == 1
            session.close_file()
            with open(tmp_path, encoding="utf-8") as f:
                lines = f.readlines()
            assert len(lines) == 3
            assert "YBOCS" in lines[1]
            assert "MADRS" in lines[2]
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

    def test_write_session_scales(self):
        with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".tsv") as tmp:
            tmp_path = tmp.name

        try:
            session = SessionData(tmp_path)
            scales = [
                SessionScale(name="Mood", current_value="7"),
                SessionScale(name="Anxiety", current_value="5"),
            ]
            stimulation = _sample_stimulation()
            session.write_session_scales(scales, stimulation, notes="Session notes")
            assert session.block_id == 1
            session.close_file()
            with open(tmp_path, encoding="utf-8") as f:
                lines = f.readlines()
            assert len(lines) == 3
            assert "Mood" in lines[1]
            assert "Anxiety" in lines[2]
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

    def test_context_manager(self):
        with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".tsv") as tmp:
            tmp_path = tmp.name

        try:
            with SessionData(tmp_path) as session:
                assert session.is_file_open() is True
            assert session.is_file_open() is False
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
