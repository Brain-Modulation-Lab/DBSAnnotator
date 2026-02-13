#!/usr/bin/env python3
"""
Integration tests for full application workflow.

Tests complete user journeys from start to finish.
"""

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

# Add src directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))

from PyQt5.QtWidgets import QApplication
from PyQt5.QtTest import QTest
from PyQt5.QtCore import Qt

from clinical_dbs_annotator.views.wizard_window import WizardWindow
from clinical_dbs_annotator.controllers.wizard_controller import WizardController


class TestFullWorkflow(unittest.TestCase):
    """Test complete application workflows."""
    
    def setUp(self):
        """Set up test environment."""
        self.app = QApplication(sys.argv)
        self.wizard = WizardWindow()
    
    def test_full_workflow_new_session(self):
        """Test complete workflow for new session."""
        # Step 0: Start new session
        QTest.mouseClick(self.wizard.step0_view.start_button, Qt.LeftButton)
        self.assertEqual(self.wizard.current_step, 1)
        
        # Step 1: Enter patient data and stimulation parameters
        self.wizard.step1_view.patient_id_edit.setText("TEST001")
        self.wizard.step1_view.left_freq_edit.setText("130")
        self.wizard.step1_view.left_amp_edit.setText("3.5")
        self.wizard.step1_view.right_freq_edit.setText("130")
        self.wizard.step1_view.right_amp_edit.setText("4.0")
        
        QTest.mouseClick(self.wizard.step1_view.next_button, Qt.LeftButton)
        self.assertEqual(self.wizard.current_step, 2)
        
        # Step 2: Select clinical scales
        # Mock scale selection
        mock_scale = MagicMock()
        mock_scale.text = "YBOCS"
        self.wizard.step2_view.clinical_scales_list.selectedItems.return_value = [mock_scale]
        
        QTest.mouseClick(self.wizard.step2_view.next_button, Qt.LeftButton)
        self.assertEqual(self.wizard.current_step, 3)
        
        # Verify Step 3 is prepared
        self.wizard.step3_view.update_session_scales.assert_called_with(["YBOCS"])
    
    def test_annotations_only_workflow(self):
        """Test annotations-only workflow."""
        # Step 0: Start annotations
        QTest.mouseClick(self.wizard.step0_view.annotations_button, Qt.LeftButton)
        self.assertEqual(self.wizard.controller.workflow_mode, "annotations_only")
        self.assertEqual(self.wizard.current_step, 3)
        
        # Verify Step 3 is shown directly
        self.assertTrue(self.wizard.step3_view.isVisible())
        self.assertFalse(self.wizard.step1_view.isVisible())
    
    @patch('PyQt5.QtWidgets.QFileDialog.getSaveFileName')
    def test_session_data_persistence(self, mock_file_dialog):
        """Test session data is properly saved and loaded."""
        mock_file_dialog.return_value = ("test_session.tsv", "TSV Files (*.tsv)")
        
        # Create temporary file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.tsv', delete=False) as temp_file:
            temp_path = temp_file.name
        
        # Mock file dialog to return our temp file
        mock_file_dialog.return_value = (temp_path, "TSV Files (*.tsv)")
        
        # Start session and add data
        self.wizard.controller.session_data.file_path = temp_path
        self.wizard.controller.session_data.data = []
        
        # Insert test data
        mock_view = MagicMock()
        mock_view.get_session_data.return_value = {
            'date': '2024-01-15',
            'time': '09:30:00',
            'scale_name': 'YBOCS',
            'scale_value': '20',
            'notes': 'Test measurement'
        }
        
        self.wizard.controller.insert_session_row(mock_view)
        
        # Verify data was saved
        self.assertEqual(len(self.wizard.controller.session_data.data), 1)
        self.assertEqual(self.wizard.controller.session_data.data[0]['scale_name'], 'YBOCS')
    
    def test_navigation_backward_forward(self):
        """Test backward and forward navigation."""
        # Navigate forward
        QTest.mouseClick(self.wizard.step0_view.start_button, Qt.LeftButton)
        self.assertEqual(self.wizard.current_step, 1)
        
        QTest.mouseClick(self.wizard.step1_view.next_button, Qt.LeftButton)
        self.assertEqual(self.wizard.current_step, 2)
        
        # Navigate backward
        QTest.mouseClick(self.wizard.step2_view.back_button, Qt.LeftButton)
        self.assertEqual(self.wizard.current_step, 1)
        
        # Navigate forward again
        QTest.mouseClick(self.wizard.step1_view.next_button, Qt.LeftButton)
        self.assertEqual(self.wizard.current_step, 2)
    
    def test_workflow_state_persistence(self):
        """Test workflow state is maintained across steps."""
        # Set up data in Step 1
        self.wizard.step1_view.patient_id_edit.setText("TEST001")
        self.wizard.step1_view.left_amp_edit.setText("3.5")
        
        # Navigate to Step 2
        QTest.mouseClick(self.wizard.step1_view.next_button, Qt.LeftButton)
        
        # Navigate back to Step 1
        QTest.mouseClick(self.wizard.step2_view.back_button, Qt.LeftButton)
        
        # Verify data is preserved
        self.assertEqual(self.wizard.step1_view.patient_id_edit.text(), "TEST001")
        self.assertEqual(self.wizard.step1_view.left_amp_edit.text(), "3.5")


class TestErrorHandling(unittest.TestCase):
    """Test error handling in workflows."""
    
    def setUp(self):
        """Set up test environment."""
        self.app = QApplication(sys.argv)
        self.wizard = WizardWindow()
    
    def test_validation_errors_block_navigation(self):
        """Test that validation errors block navigation."""
        # Step 1: Leave required fields empty
        self.wizard.step1_view.patient_id_edit.setText("")
        
        with patch('PyQt5.QtWidgets.QMessageBox.warning') as mock_warning:
            QTest.mouseClick(self.wizard.step1_view.next_button, Qt.LeftButton)
            
            # Should show warning and not navigate
            mock_warning.assert_called()
            self.assertEqual(self.wizard.current_step, 1)
    
    def test_file_operation_errors(self):
        """Test file operation error handling."""
        # Test with invalid file path
        self.wizard.controller.session_data.file_path = "/invalid/path/file.tsv"
        
        with patch('PyQt5.QtWidgets.QMessageBox.critical') as mock_critical:
            result = self.wizard.controller.session_data.save_data()
            
            self.assertFalse(result)
            mock_critical.assert_called()
    
    @patch('PyQt5.QtWidgets.QMessageBox.question')
    def test_session_close_with_unsaved_data(self, mock_question):
        """Test session close with unsaved data."""
        mock_question.return_value = QMessageBox.Cancel
        
        # Setup unsaved data
        self.wizard.controller.session_data.data = [{'test': 'data'}]
        self.wizard.controller.session_data.modified = True
        
        self.wizard.controller.close_session(self.wizard)
        
        # Should ask for confirmation
        mock_question.assert_called()
        # Should not close if cancelled
        self.assertTrue(self.wizard.isVisible())


class TestUIResponsiveness(unittest.TestCase):
    """Test UI responsiveness during workflows."""
    
    def setUp(self):
        """Set up test environment."""
        self.app = QApplication(sys.argv)
        self.wizard = WizardWindow()
    
    def test_window_resizing(self):
        """Test window resizing behavior."""
        # Test minimum size
        self.wizard.resize(300, 200)
        self.assertGreaterEqual(self.wizard.width(), 800)
        self.assertGreaterEqual(self.wizard.height(), 600)
        
        # Test normal resizing
        self.wizard.resize(1200, 800)
        self.assertEqual(self.wizard.width(), 1200)
        self.assertEqual(self.wizard.height(), 800)
    
    def test_theme_switching(self):
        """Test theme switching during workflow."""
        # Test light theme
        self.wizard.apply_theme('light')
        self.assertIsNotNone(self.wizard.styleSheet())
        
        # Test dark theme
        self.wizard.apply_theme('dark')
        self.assertIsNotNone(self.wizard.styleSheet())
        
        # Verify theme is applied to all views
        self.assertIsNotNone(self.wizard.step1_view.styleSheet())
        self.assertIsNotNone(self.wizard.step2_view.styleSheet())
        self.assertIsNotNone(self.wizard.step3_view.styleSheet())


class TestAccessibility(unittest.TestCase):
    """Test accessibility features."""
    
    def setUp(self):
        """Set up test environment."""
        self.app = QApplication(sys.argv)
        self.wizard = WizardWindow()
    
    def test_keyboard_navigation(self):
        """Test keyboard navigation between fields."""
        # Test Tab navigation in Step 1
        self.wizard.step1_view.patient_id_edit.setFocus()
        QTest.keyClick(self.wizard.step1_view.patient_id_edit, Qt.Key_Tab)
        
        # Should move to next field
        self.assertTrue(self.wizard.step1_view.left_freq_edit.hasFocus())
    
    def test_button_tooltips(self):
        """Test buttons have tooltips."""
        buttons_with_tooltips = [
            (self.wizard.step0_view.start_button, "Start new DBS session"),
            (self.wizard.step1_view.next_button, "Proceed to clinical scales selection"),
            (self.wizard.step2_view.next_button, "Proceed to session recording"),
            (self.wizard.step3_view.insert_button, "Insert session data")
        ]
        
        for button, expected_tooltip in buttons_with_tooltips:
            if hasattr(button, 'toolTip'):
                self.assertIn(expected_tooltip.lower(), button.toolTip().lower())
    
    def test_high_contrast_mode(self):
        """Test high contrast mode support."""
        # Enable high contrast
        self.wizard.enable_high_contrast_mode(True)
        
        # Verify high contrast styles are applied
        stylesheet = self.wizard.styleSheet()
        self.assertIn('high-contrast', stylesheet.lower())


if __name__ == '__main__':
    unittest.main()
