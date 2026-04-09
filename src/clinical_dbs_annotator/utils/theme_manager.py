"""
Theme manager for handling dark/light mode switching.

This module provides a centralized theme management system that allows
switching between dark and light themes at runtime.
"""

import os
from enum import Enum

from PySide6.QtWidgets import QApplication

from .resources import resource_path


class Theme(Enum):
    """Available application themes."""

    DARK = "dark"
    LIGHT = "light"


class ThemeManager:
    """
    Manages application theme switching.

    This singleton class handles loading and applying themes,
    and persisting theme preferences.
    """

    _instance: ThemeManager | None = None
    _current_theme: Theme = Theme.LIGHT

    def __new__(cls):
        """Ensure singleton instance."""
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self):
        """Initialize theme manager."""
        # Only initialize once
        if not hasattr(self, "_initialized"):
            self._initialized = True
            self._load_saved_theme()

    def _load_saved_theme(self) -> None:
        """Load saved theme preference from settings."""
        # TODO: Load from QSettings or config file
        # For now, default to light theme
        self._current_theme = Theme.LIGHT

    def _save_theme(self) -> None:
        """Save current theme preference to settings."""
        # TODO: Save to QSettings or config file
        pass

    def get_current_theme(self) -> Theme:
        """
        Get the currently active theme.

        Returns:
            Theme: Current theme enum value
        """
        return self._current_theme

    def get_theme_stylesheet_path(self, theme: Theme) -> str:
        """
        Get the filesystem path to a theme's stylesheet.

        Args:
            theme: The theme to get the path for

        Returns:
            str: Absolute path to the theme's QSS file
        """
        if theme == Theme.DARK:
            filename = "dark_theme.qss"
        else:
            filename = "light_theme.qss"

        return resource_path(os.path.join("styles", filename))

    def load_stylesheet(self, theme: Theme) -> str:
        """
        Load a theme's stylesheet content.

        Args:
            theme: The theme to load

        Returns:
            str: QSS stylesheet content

        Raises:
            FileNotFoundError: If stylesheet file doesn't exist
        """
        path = self.get_theme_stylesheet_path(theme)

        if not os.path.exists(path):
            raise FileNotFoundError(f"Theme stylesheet not found: {path}")

        with open(path, encoding="utf-8") as f:
            return f.read()

    def apply_theme(self, theme: Theme, app: QApplication = None) -> None:
        """
        Apply a theme to the application.

        Args:
            theme: The theme to apply
            app: QApplication instance. If None, uses QApplication.instance()

        Raises:
            ValueError: If app is None and no QApplication instance exists
        """
        if app is None:
            app = QApplication.instance()

        if app is None:
            raise ValueError("No QApplication instance available")

        try:
            stylesheet = self.load_stylesheet(theme)
            app.setStyleSheet(stylesheet)
            self._current_theme = theme
            self._save_theme()
        except FileNotFoundError as e:
            print(f"Warning: Could not load theme: {e}")
            # Fallback to no stylesheet
            app.setStyleSheet("")

    def toggle_theme(self, app: QApplication = None) -> Theme:
        """
        Toggle between dark and light themes.

        Args:
            app: QApplication instance. If None, uses QApplication.instance()

        Returns:
            Theme: The newly activated theme
        """
        new_theme = Theme.LIGHT if self._current_theme == Theme.DARK else Theme.DARK
        self.apply_theme(new_theme, app)
        return new_theme

    def is_dark_mode(self) -> bool:
        """
        Check if dark mode is currently active.

        Returns:
            bool: True if dark mode, False if light mode
        """
        return self._current_theme == Theme.DARK

    def get_theme_color(self, color_name: str) -> str:
        """
        Get a named color from the current theme's QSS file comments.

        Parses the 'Base Colors' comment block for lines like:
            Icon: #64748b (Slate 500 - for settings icon)

        Args:
            color_name: Name of the color (e.g. 'Icon', 'Primary', 'Text')

        Returns:
            str: Hex color string, or '#888888' as fallback
        """
        import re

        try:
            qss_content = self.load_stylesheet(self._current_theme)
            pattern = rf"{color_name}\s*:\s*(#[0-9a-fA-F]{{6}})"
            match = re.search(pattern, qss_content)
            if match:
                return match.group(1)
        except Exception:
            pass
        return "#888888"

    def get_theme_icon(self, theme: Theme) -> str:
        """
        Get the icon character for a theme toggle button.

        Args:
            theme: The theme to get icon for

        Returns:
            str: Unicode character for the theme icon
        """
        # Return icon for the OTHER theme (what clicking will switch TO)
        if theme == Theme.DARK:
            return "☀"  # Sun icon (currently in light mode, will switch to dark)
        else:
            return "🌙"  # Moon icon (currently in dark mode, will switch to light)


# Global theme manager instance
_theme_manager = ThemeManager()


def get_theme_manager() -> ThemeManager:
    """
    Get the global theme manager instance.

    Returns:
        ThemeManager: The singleton theme manager
    """
    return _theme_manager
