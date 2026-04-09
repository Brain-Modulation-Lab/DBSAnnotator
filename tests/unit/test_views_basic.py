#!/usr/bin/env python3
"""
Basic unit tests for Views.

Simple tests without complex mocking to verify UI components work.
"""

import sys
import unittest
from pathlib import Path

# Add src directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))

from PyQt5.QtWidgets import QApplication, QPushButton

from clinical_dbs_annotator.views import (
    Step0View,
    Step1View,
    Step2View,
    Step3View,
    WizardWindow,
)


class TestStep0View(unittest.TestCase):
    """Test Step 0 view functionality."""

    def setUp(self):
        """Set up test environment."""
        self.app = QApplication(sys.argv)
        self.view = Step0View()

    def test_view_creates_successfully(self):
        """Test that Step0View creates without errors."""
        # This should not raise any exceptions
        self.assertIsNotNone(self.view)
        self.assertIsNotNone(self.view.full_mode_button)
        self.assertIsNotNone(self.view.annotations_only_button)

    def test_buttons_are_push_buttons(self):
        """Test that buttons are QPushButton instances."""
        self.assertIsInstance(self.view.full_mode_button, QPushButton)
        self.assertIsInstance(self.view.annotations_only_button, QPushButton)


class TestStep1View(unittest.TestCase):
    """Test Step 1 view functionality."""

    def setUp(self):
        """Set up test environment."""
        self.app = QApplication(sys.argv)
        self.view = Step1View()

    def test_view_creates_successfully(self):
        """Test that Step1View creates without errors."""
        self.assertIsNotNone(self.view)
        self.assertIsNotNone(self.view.next_button)
        self.assertIsNotNone(self.view.back_button)


class TestStep2View(unittest.TestCase):
    """Test Step 2 view functionality."""

    def setUp(self):
        """Set up test environment."""
        self.app = QApplication(sys.argv)
        self.view = Step2View()

    def test_view_creates_successfully(self):
        """Test that Step2View creates without errors."""
        self.assertIsNotNone(self.view)
        self.assertIsNotNone(self.view.next_button)
        self.assertIsNotNone(self.view.back_button)


class TestStep3View(unittest.TestCase):
    """Test Step 3 view functionality."""

    def setUp(self):
        """Set up test environment."""
        self.app = QApplication(sys.argv)
        self.view = Step3View()

    def test_view_creates_successfully(self):
        """Test that Step3View creates without errors."""
        self.assertIsNotNone(self.view)
        self.assertIsNotNone(self.view.insert_button)
        self.assertIsNotNone(self.view.close_button)
        self.assertIsNotNone(self.view.export_button)

    def test_export_menu_exists(self):
        """Test that export menu exists."""
        self.assertIsNotNone(self.view.export_menu)
        # Menu should have 3 actions (Excel, Word, PDF)
        self.assertEqual(len(self.view.export_menu.actions()), 3)


class TestWizardWindow(unittest.TestCase):
    """Test main wizard window."""

    def setUp(self):
        """Set up test environment."""
        self.app = QApplication(sys.argv)
        self.window = WizardWindow()

    def test_window_creates_successfully(self):
        """Test that WizardWindow creates without errors."""
        self.assertIsNotNone(self.window)
        self.assertIsNotNone(self.window.controller)
        self.assertIsNotNone(self.window.step0_view)
        self.assertIsNotNone(self.window.step1_view)
        self.assertIsNotNone(self.window.step2_view)
        self.assertIsNotNone(self.window.step3_view)


class TestViewBasicFunctionality(unittest.TestCase):
    """Test basic view functionality across all views."""

    def test_all_views_import_successfully(self):
        """Test that all views can be imported."""
        # This tests that our imports work correctly
        try:
            Step0View()
            Step1View()
            Step2View()
            Step3View()
            WizardWindow()
            self.assertTrue(True)  # All imports successful
        except Exception as e:
            self.fail(f"Failed to import views: {e}")


if __name__ == "__main__":
    unittest.main()
