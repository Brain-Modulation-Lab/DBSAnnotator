#!/usr/bin/env python3
"""
Unit tests for Wizard Controller.

Tests the main application logic and workflow management.
"""

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

# Add src directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))

from PyQt5.QtWidgets import QMessageBox

from dbs_annotator.controllers.wizard_controller import WizardController
from dbs_annotator.models import SessionData, StimulationParameters


class TestWizardController(unittest.TestCase):
    """Test wizard controller functionality."""

    def setUp(self):
        """Set up test environment."""
        self.controller = WizardController()

    def test_initialization(self):
        """Test controller initialization."""
        self.assertIsNotNone(self.controller.session_data)
        self.assertIsNotNone(self.controller.current_stimulation)
        self.assertIsInstance(self.controller.session_scales_names, list)
        self.assertIsNone(self.controller.workflow_mode)

    def test_session_data_initialization(self):
        """Test session data is properly initialized."""
        self.assertIsInstance(self.controller.session_data, SessionData)
        self.assertFalse(self.controller.session_data.is_file_open())

    def test_stimulation_parameters_initialization(self):
        """Test stimulation parameters initialization."""
        self.assertIsInstance(
            self.controller.current_stimulation, StimulationParameters
        )

    def test_add_clinical_scale(self):
        """Test adding clinical scales."""
        initial_count = len(self.controller.session_scales_names)
        self.controller.add_clinical_scale("YBOCS")
        self.assertEqual(len(self.controller.session_scales_names), initial_count + 1)
        self.assertIn("YBOCS", self.controller.session_scales_names)

    def test_remove_clinical_scale(self):
        """Test removing clinical scales."""
        self.controller.add_clinical_scale("YBOCS")
        initial_count = len(self.controller.session_scales_names)

        self.controller.remove_clinical_scale("YBOCS")
        self.assertEqual(len(self.controller.session_scales_names), initial_count - 1)
        self.assertNotIn("YBOCS", self.controller.session_scales_names)

    def test_validate_stimulation_parameters_valid(self):
        """Test validation of valid stimulation parameters."""
        params = {
            "left_frequency": "130",
            "left_cathode": "e1",
            "left_anode": "e3",
            "left_amplitude": "3.5",
            "left_pulse_width": "60",
            "right_frequency": "130",
            "right_cathode": "e2",
            "right_anode": "e4",
            "right_amplitude": "4.0",
            "right_pulse_width": "60",
        }

        result = self.controller.validate_stimulation_parameters(params)
        self.assertTrue(result["valid"])
        self.assertEqual(len(result["errors"]), 0)

    def test_validate_stimulation_parameters_invalid(self):
        """Test validation of invalid stimulation parameters."""
        params = {
            "left_frequency": "999",  # Invalid frequency
            "left_cathode": "e1",
            "left_anode": "e3",
            "left_amplitude": "15.0",  # Invalid amplitude
            "left_pulse_width": "60",
            "right_frequency": "130",
            "right_cathode": "e2",
            "right_anode": "e4",
            "right_amplitude": "4.0",
            "right_pulse_width": "60",
        }

        result = self.controller.validate_stimulation_parameters(params)
        self.assertFalse(result["valid"])
        self.assertGreater(len(result["errors"]), 0)

    @patch("PyQt5.QtWidgets.QMessageBox.question")
    def test_close_session_confirmation(self, mock_question):
        """Test session close confirmation."""
        mock_question.return_value = QMessageBox.Yes

        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".tsv", delete=False
        ) as temp_file:
            # Setup session with file
            self.controller.session_data.file_path = temp_file.name
            self.controller.session_data.data = [{"test": "data"}]

            self.controller.close_session(MagicMock())

            mock_question.assert_called_once()

    def test_workflow_mode_setting(self):
        """Test workflow mode setting."""
        self.controller.set_workflow_mode("full")
        self.assertEqual(self.controller.workflow_mode, "full")

        self.controller.set_workflow_mode("annotations_only")
        self.assertEqual(self.controller.workflow_mode, "annotations_only")

    def test_prepare_step3(self):
        """Test Step 3 preparation."""
        mock_view = MagicMock()

        # Setup some data
        self.controller.session_scales_names = ["YBOCS", "HAM-D"]
        self.controller.current_stimulation.left_frequency = "130"
        self.controller.current_stimulation.left_amplitude = "3.5"

        self.controller.prepare_step3(mock_view)

        # Verify view was updated
        mock_view.update_session_scales.assert_called_once_with(["YBOCS", "HAM-D"])
        mock_view.set_initial_stimulation_params.assert_called_once()


class TestWizardControllerDataManagement(unittest.TestCase):
    """Test data management in wizard controller."""

    def setUp(self):
        """Set up data management test environment."""
        self.controller = WizardController()

    def test_insert_session_row(self):
        """Test inserting session data row."""
        mock_view = MagicMock()
        mock_view.get_session_data.return_value = {
            "date": "2024-01-15",
            "time": "09:30:00",
            "scale_name": "YBOCS",
            "scale_value": "20",
            "notes": "Test note",
        }

        initial_count = len(self.controller.session_data.data)
        self.controller.insert_session_row(mock_view)

        self.assertEqual(len(self.controller.session_data.data), initial_count + 1)

    def test_validate_scale_values(self):
        """Test scale value validation."""
        # Valid values
        valid_values = ["10", "20.5", "30"]
        for value in valid_values:
            result = self.controller.validate_scale_value(value)
            self.assertTrue(result["valid"])

        # Invalid values
        invalid_values = ["-5", "abc", "1000"]
        for value in invalid_values:
            result = self.controller.validate_scale_value(value)
            self.assertFalse(result["valid"])

    def test_get_session_statistics(self):
        """Test session statistics calculation."""
        # Setup test data
        self.controller.session_data.data = [
            {"scale_name": "YBOCS", "scale_value": "20"},
            {"scale_name": "YBOCS", "scale_value": "18"},
            {"scale_name": "HAM-D", "scale_value": "15"},
        ]

        stats = self.controller.get_session_statistics()

        self.assertIn("total_records", stats)
        self.assertIn("scales", stats)
        self.assertIn("value_ranges", stats)
        self.assertEqual(stats["total_records"], 3)


if __name__ == "__main__":
    unittest.main()
