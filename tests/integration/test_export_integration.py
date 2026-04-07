#!/usr/bin/env python3
"""
Integration tests for export functionality.

Tests the complete export workflow from UI to file generation.
"""

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

# Add src directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))

from PyQt5.QtWidgets import QApplication

from clinical_dbs_annotator.controllers.wizard_controller import WizardController
from clinical_dbs_annotator.models.session_data import SessionData
from clinical_dbs_annotator.utils.session_exporter import SessionExporter
from clinical_dbs_annotator.views.step3_view import Step3View


class TestExportIntegration(unittest.TestCase):
    """Test export functionality integration."""

    def setUp(self):
        """Set up test environment."""
        self.app = QApplication(sys.argv)

        # Create sample data
        self.sample_data = [
            {
                'date': '2024-01-15',
                'time': '09:30:00',
                'block_id': '1',
                'scale_name': 'YBOCS',
                'scale_value': '20',
                'stim_freq': '130',
                'left_contact': 'e1-e3',
                'left_amplitude': '3.5',
                'left_pulse_width': '60',
                'right_contact': 'e2-e4',
                'right_amplitude': '4.0',
                'right_pulse_width': '60',
                'notes': 'Baseline measurement'
            },
            {
                'date': '2024-01-15',
                'time': '10:30:00',
                'block_id': '2',
                'scale_name': 'YBOCS',
                'scale_value': '18',
                'stim_freq': '130',
                'left_contact': 'e1-e3',
                'left_amplitude': '4.0',
                'left_pulse_width': '60',
                'right_contact': 'e2-e4',
                'right_amplitude': '4.5',
                'right_pulse_width': '60',
                'notes': 'After stimulation'
            }
        ]

        # Create temporary TSV file
        self.temp_file = tempfile.NamedTemporaryFile(mode='w', suffix='.tsv', delete=False)
        df = pd.DataFrame(self.sample_data)
        df.to_csv(self.temp_file.name, sep='\t', index=False)
        self.temp_file.close()

        # Create session data with temporary file
        self.session_data = SessionData()
        self.session_data.file_path = self.temp_file.name

        # Create exporter
        self.exporter = SessionExporter(self.session_data)

    def tearDown(self):
        """Clean up test environment."""
        Path(self.temp_file.name).unlink(missing_ok=True)

    @patch('PyQt5.QtWidgets.QFileDialog.getSaveFileName')
    @patch('PyQt5.QtWidgets.QMessageBox.information')
    def test_excel_export_integration(self, mock_msgbox, mock_file_dialog):
        """Test Excel export integration."""
        with tempfile.NamedTemporaryFile(suffix='.xlsx', delete=False) as excel_file:
            excel_path = excel_file.name

        mock_file_dialog.return_value = (excel_path, "Excel Files (*.xlsx)")

        result = self.exporter.export_to_excel()

        self.assertTrue(result)
        self.assertTrue(Path(excel_path).exists())
        mock_msgbox.assert_called_once()

    @patch('PyQt5.QtWidgets.QFileDialog.getSaveFileName')
    @patch('PyQt5.QtWidgets.QMessageBox.information')
    def test_word_export_integration(self, mock_msgbox, mock_file_dialog):
        """Test Word export integration."""
        with tempfile.NamedTemporaryFile(suffix='.docx', delete=False) as word_file:
            word_path = word_file.name

        mock_file_dialog.return_value = (word_path, "Word Files (*.docx)")

        result = self.exporter.export_to_word()

        self.assertTrue(result)
        self.assertTrue(Path(word_path).exists())
        mock_msgbox.assert_called_once()

    @patch('PyQt5.QtWidgets.QFileDialog.getSaveFileName')
    @patch('PyQt5.QtWidgets.QMessageBox.information')
    def test_pdf_export_integration(self, mock_msgbox, mock_file_dialog):
        """Test PDF export integration."""
        with tempfile.NamedTemporaryFile(suffix='.pdf', delete=False) as pdf_file:
            pdf_path = pdf_file.name

        mock_file_dialog.return_value = (pdf_path, "PDF Files (*.pdf)")

        result = self.exporter.export_to_pdf()

        self.assertTrue(result)
        self.assertTrue(Path(pdf_path).exists())
        mock_msgbox.assert_called_once()

    def test_export_with_no_data(self):
        """Test export behavior with no data."""
        # Create empty session data
        empty_session = SessionData()
        empty_exporter = SessionExporter(empty_session)

        with patch('PyQt5.QtWidgets.QMessageBox.warning') as mock_warning:
            result = empty_exporter.export_to_excel()
            self.assertFalse(result)
            mock_warning.assert_called_once()

    def test_export_with_no_file_open(self):
        """Test export behavior with no file open."""
        # Create session data without file
        no_file_session = SessionData()
        no_file_session.file_path = None
        no_file_exporter = SessionExporter(no_file_session)

        with patch('PyQt5.QtWidgets.QMessageBox.warning') as mock_warning:
            result = no_file_exporter.export_to_excel()
            self.assertFalse(result)
            mock_warning.assert_called_once()


class TestExportUIIntegration(unittest.TestCase):
    """Test export UI integration."""

    def setUp(self):
        """Set up UI test environment."""
        self.app = QApplication(sys.argv)
        self.controller = WizardController()
        self.step3_view = Step3View()

    def test_export_menu_creation(self):
        """Test export menu is created correctly."""
        self.assertIsNotNone(self.step3_view.export_button)
        self.assertIsNotNone(self.step3_view.export_menu)
        self.assertEqual(len(self.step3_view.export_menu.actions()), 3)

    def test_export_actions_exist(self):
        """Test all export actions exist."""
        self.assertIsNotNone(self.step3_view.export_excel_action)
        self.assertIsNotNone(self.step3_view.export_word_action)
        self.assertIsNotNone(self.step3_view.export_pdf_action)


if __name__ == '__main__':
    unittest.main()
