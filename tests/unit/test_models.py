"""
Unit tests for data models.

Tests the clinical scales, stimulation parameters, and session data models.
"""

import os
import tempfile

from clinical_dbs_annotator.models import (
    ClinicalScale,
    SessionData,
    SessionScale,
    StimulationParameters,
)


class TestClinicalScale:
    """Test cases for ClinicalScale model."""

    def test_creation(self):
        """Test creating a clinical scale."""
        scale = ClinicalScale(name="YBOCS", value="25")
        assert scale.name == "YBOCS"
        assert scale.value == "25"

    def test_is_valid_with_both_fields(self):
        """Test validation with both name and value."""
        scale = ClinicalScale(name="MADRS", value="10")
        assert scale.is_valid() is True

    def test_is_valid_without_value(self):
        """Test validation without value."""
        scale = ClinicalScale(name="UPDRS", value=None)
        assert scale.is_valid() is False

    def test_is_valid_with_empty_strings(self):
        """Test validation with empty strings."""
        scale = ClinicalScale(name="", value="")
        assert scale.is_valid() is False

    def test_repr(self):
        """Test string representation."""
        scale = ClinicalScale(name="FTM", value="8")
        assert "FTM" in repr(scale)
        assert "8" in repr(scale)


class TestSessionScale:
    """Test cases for SessionScale model."""

    def test_creation(self):
        """Test creating a session scale."""
        scale = SessionScale(name="Mood", min_value="0", max_value="10")
        assert scale.name == "Mood"
        assert scale.min_value == "0"
        assert scale.max_value == "10"
        assert scale.current_value is None

    def test_creation_with_current_value(self):
        """Test creating a session scale with current value."""
        scale = SessionScale(
            name="Anxiety", min_value="0", max_value="10", current_value="7"
        )
        assert scale.current_value == "7"

    def test_is_valid(self):
        """Test validation."""
        scale = SessionScale(name="Energy")
        assert scale.is_valid() is True

        empty_scale = SessionScale(name="")
        assert empty_scale.is_valid() is False

    def test_has_value(self):
        """Test checking for current value."""
        scale = SessionScale(name="OCD", current_value="5")
        assert scale.has_value() is True

        scale_no_value = SessionScale(name="Tremor")
        assert scale_no_value.has_value() is False


class TestStimulationParameters:
    """Test cases for StimulationParameters model."""

    def test_creation(self):
        """Test creating stimulation parameters."""
        params = StimulationParameters(
            frequency="130",
            left_contact="e1",
            left_amplitude="3.5",
            left_pulse_width="60",
            right_contact="e2",
            right_amplitude="4.0",
            right_pulse_width="60",
        )
        assert params.frequency == "130"
        assert params.left_contact == "e1"
        assert params.right_amplitude == "4.0"

    def test_to_dict(self):
        """Test conversion to dictionary."""
        params = StimulationParameters(
            frequency="130", left_contact="e1", left_amplitude="3.5"
        )
        result = params.to_dict()

        assert result["stim_freq"] == "130"
        assert result["left_contact"] == "e1"
        assert result["left_amplitude"] == "3.5"
        assert "right_contact" in result

    def test_from_dict(self):
        """Test creation from dictionary."""
        data = {
            "stim_freq": "130",
            "left_contact": "e1",
            "left_amplitude": "3.5",
            "left_pulse_width": "60",
            "right_contact": "e2",
            "right_amplitude": "4.0",
            "right_pulse_width": "60",
        }
        params = StimulationParameters.from_dict(data)

        assert params.frequency == "130"
        assert params.left_contact == "e1"
        assert params.right_pulse_width == "60"

    def test_copy(self):
        """Test copying parameters."""
        original = StimulationParameters(frequency="130", left_contact="e1")
        copy = original.copy()

        assert copy.frequency == original.frequency
        assert copy.left_contact == original.left_contact
        assert copy is not original


class TestSessionData:
    """Test cases for SessionData model."""

    def test_creation(self):
        """Test creating session data."""
        session = SessionData()
        assert session.file_path is None
        assert session.tsv_file is None
        assert session.block_id == 0

    def test_open_and_close_file(self):
        """Test opening and closing a TSV file."""
        with tempfile.NamedTemporaryFile(
            mode="w", delete=False, suffix=".tsv"
        ) as tmp:
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
        """Test writing clinical scales to file."""
        with tempfile.NamedTemporaryFile(
            mode="w", delete=False, suffix=".tsv"
        ) as tmp:
            tmp_path = tmp.name

        try:
            session = SessionData(tmp_path)

            scales = [
                ClinicalScale(name="YBOCS", value="25"),
                ClinicalScale(name="MADRS", value="10"),
            ]
            stimulation = StimulationParameters(frequency="130", left_contact="e1")

            session.write_clinical_scales(scales, stimulation, "Test notes")

            assert session.block_id == 1

            session.close_file()

            # Verify file content
            with open(tmp_path, encoding="utf-8") as f:
                lines = f.readlines()
                assert len(lines) == 3  # header + 2 scale rows
                assert "YBOCS" in lines[1]
                assert "MADRS" in lines[2]
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

    def test_write_session_scales(self):
        """Test writing session scales to file."""
        with tempfile.NamedTemporaryFile(
            mode="w", delete=False, suffix=".tsv"
        ) as tmp:
            tmp_path = tmp.name

        try:
            session = SessionData(tmp_path)

            scales = [
                SessionScale(name="Mood", current_value="7"),
                SessionScale(name="Anxiety", current_value="5"),
            ]
            stimulation = StimulationParameters(frequency="130")

            session.write_session_scales(scales, stimulation, "Session notes")

            assert session.block_id == 1

            session.close_file()

            # Verify file content
            with open(tmp_path, encoding="utf-8") as f:
                lines = f.readlines()
                assert len(lines) == 3  # header + 2 scale rows
                assert "Mood" in lines[1]
                assert "Anxiety" in lines[2]
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

    def test_context_manager(self):
        """Test using SessionData as context manager."""
        with tempfile.NamedTemporaryFile(
            mode="w", delete=False, suffix=".tsv"
        ) as tmp:
            tmp_path = tmp.name

        try:
            with SessionData(tmp_path) as session:
                assert session.is_file_open() is True

            # File should be closed after exiting context
            assert session.is_file_open() is False
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
