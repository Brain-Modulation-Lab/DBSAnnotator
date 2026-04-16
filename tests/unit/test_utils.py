#!/usr/bin/env python3
"""
Unit tests for Utils.

Tests utility functions and helper classes.
"""

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

# Add src directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))

from PyQt5.QtWidgets import QApplication

from dbs_annotator.utils import (
    animate_button,
    graphics,
    resources,
    responsive,
    theme_manager,
)


class TestAnimateButton(unittest.TestCase):
    """Test button animation utility."""

    def setUp(self):
        """Set up test environment."""
        self.app = QApplication(sys.argv)

    @patch("PyQt5.QtCore.QTimer.singleShot")
    def test_animate_button_success(self, mock_timer):
        """Test successful button animation."""
        mock_button = MagicMock()

        animate_button(mock_button, success=True)

        mock_timer.assert_called()
        mock_button.setStyleSheet.assert_called()

    @patch("PyQt5.QtCore.QTimer.singleShot")
    def test_animate_button_error(self, mock_timer):
        """Test error button animation."""
        mock_button = MagicMock()

        animate_button(mock_button, success=False)

        mock_timer.assert_called()
        mock_button.setStyleSheet.assert_called()


class TestThemeManager(unittest.TestCase):
    """Test theme manager functionality."""

    def setUp(self):
        """Set up test environment."""
        self.app = QApplication(sys.argv)

    def test_get_available_themes(self):
        """Test getting available themes."""
        themes = theme_manager.get_available_themes()
        self.assertIsInstance(themes, list)
        self.assertIn("light", themes)
        self.assertIn("dark", themes)

    def test_apply_theme(self):
        """Test applying themes."""
        mock_app = MagicMock()

        # Test light theme
        theme_manager.apply_theme(mock_app, "light")
        mock_app.setStyleSheet.assert_called()

        # Test dark theme
        theme_manager.apply_theme(mock_app, "dark")
        mock_app.setStyleSheet.assert_called()

    def test_get_current_theme(self):
        """Test getting current theme."""
        mock_app = MagicMock()

        # Test default theme
        current = theme_manager.get_current_theme(mock_app)
        self.assertIn(current, ["light", "dark"])

    def test_save_theme_preference(self):
        """Test saving theme preference."""
        with patch("builtins.open", create=True) as mock_open:
            mock_file = MagicMock()
            mock_open.return_value.__enter__.return_value = mock_file

            theme_manager.save_theme_preference("dark")
            mock_file.write.assert_called_with("dark")

    def test_load_theme_preference(self):
        """Test loading theme preference."""
        with patch("builtins.open", create=True) as mock_open:
            mock_file = MagicMock()
            mock_file.read.return_value = "light"
            mock_open.return_value.__enter__.return_value = mock_file

            theme = theme_manager.load_theme_preference()
            self.assertEqual(theme, "light")


class TestResponsive(unittest.TestCase):
    """Test responsive design utilities."""

    def test_calculate_scale_factor(self):
        """Test scale factor calculation."""
        # Test normal DPI
        scale = responsive.calculate_scale_factor(96)
        self.assertEqual(scale, 1.0)

        # Test high DPI
        scale = responsive.calculate_scale_factor(144)
        self.assertEqual(scale, 1.5)

        # Test low DPI
        scale = responsive.calculate_scale_factor(72)
        self.assertEqual(scale, 0.75)

    def test_scale_font_size(self):
        """Test font size scaling."""
        scaled_size = responsive.scale_font_size(12, 1.5)
        self.assertEqual(scaled_size, 18)

        scaled_size = responsive.scale_font_size(12, 0.75)
        self.assertEqual(scaled_size, 9)

    def test_scale_widget_size(self):
        """Test widget size scaling."""
        original_size = (400, 300)
        scaled_size = responsive.scale_widget_size(original_size, 1.5)
        self.assertEqual(scaled_size, (600, 450))

    def test_is_mobile_screen(self):
        """Test mobile screen detection."""
        # Test desktop
        self.assertFalse(responsive.is_mobile_screen(1920, 1080))

        # Test mobile
        self.assertTrue(responsive.is_mobile_screen(768, 1024))

        # Test tablet
        self.assertTrue(responsive.is_mobile_screen(1024, 768))


class TestGraphics(unittest.TestCase):
    """Test graphics utilities."""

    def setUp(self):
        """Set up test environment."""
        self.app = QApplication(sys.argv)

    def test_get_icon(self):
        """Test icon loading."""
        # Test existing icon
        icon = graphics.get_icon("save")
        self.assertIsNotNone(icon)

        # Test non-existing icon
        icon = graphics.get_icon("nonexistent")
        self.assertIsNone(icon)

    def test_create_colored_icon(self):
        """Test colored icon creation."""
        icon = graphics.create_colored_icon("#FF0000", 16, 16)
        self.assertIsNotNone(icon)
        self.assertEqual(icon.size().width(), 16)
        self.assertEqual(icon.size().height(), 16)

    def test_resize_icon(self):
        """Test icon resizing."""
        mock_icon = MagicMock()
        mock_icon.size.return_value = MagicMock()
        mock_icon.size.return_value.width.return_value = 32
        mock_icon.size.return_value.height.return_value = 32

        resized = graphics.resize_icon(mock_icon, 16, 16)
        self.assertIsNotNone(resized)


class TestResources(unittest.TestCase):
    """Test resource management."""

    def test_get_stylesheet(self):
        """Test stylesheet loading."""
        # Test existing stylesheet
        css = resources.get_stylesheet("main")
        self.assertIsInstance(css, str)
        self.assertGreater(len(css), 0)

        # Test non-existing stylesheet
        css = resources.get_stylesheet("nonexistent")
        self.assertEqual(css, "")

    def test_get_resource_path(self):
        """Test resource path resolution."""
        path = resources.get_resource_path("icons", "save.png")
        self.assertIsInstance(path, Path)
        self.assertTrue(path.exists())

    def test_load_json_resource(self):
        """Test JSON resource loading."""
        mock_data = {"test": "data"}

        with patch("builtins.open", create=True) as mock_open:
            mock_file = MagicMock()
            mock_file.read.return_value = '{"test": "data"}'
            mock_open.return_value.__enter__.return_value = mock_file

            data = resources.load_json_resource("test.json")
            self.assertEqual(data, mock_data)


class TestUtilityFunctions(unittest.TestCase):
    """Test general utility functions."""

    def test_format_clinical_scale_name(self):
        """Test clinical scale name formatting."""
        from dbs_annotator.utils import format_clinical_scale_name

        # Test normal formatting
        formatted = format_clinical_scale_name("ybocs")
        self.assertEqual(formatted, "YBOCS")

        # Test already formatted
        formatted = format_clinical_scale_name("HAM-D")
        self.assertEqual(formatted, "HAM-D")

    def test_validate_amplitude_value(self):
        """Test amplitude value validation."""
        from dbs_annotator.utils import validate_amplitude_value

        # Test valid values
        valid_values = ["0.5", "3.5", "10.0"]
        for value in valid_values:
            result = validate_amplitude_value(value)
            self.assertTrue(result["valid"])

        # Test invalid values
        invalid_values = ["-1.0", "15.0", "abc", ""]
        for value in invalid_values:
            result = validate_amplitude_value(value)
            self.assertFalse(result["valid"])

    def test_format_frequency_value(self):
        """Test frequency value formatting."""
        from dbs_annotator.utils import format_frequency_value

        # Test normal formatting
        formatted = format_frequency_value("130")
        self.assertEqual(formatted, "130 Hz")

        # Test with existing Hz
        formatted = format_frequency_value("130 Hz")
        self.assertEqual(formatted, "130 Hz")

    def test_generate_session_id(self):
        """Test session ID generation."""
        from dbs_annotator.utils import generate_session_id

        session_id = generate_session_id()
        self.assertIsInstance(session_id, str)
        self.assertGreater(len(session_id), 8)

        # Test uniqueness
        session_id2 = generate_session_id()
        self.assertNotEqual(session_id, session_id2)


if __name__ == "__main__":
    unittest.main()
