"""
Scale preset manager for loading and saving user-modified scale presets.

This module handles loading and saving clinical and session scale presets
to a user config file in the application log directory.
"""

import json
import sys
from pathlib import Path

from ..config import CLINICAL_SCALES_PRESETS, SESSION_SCALES_PRESETS


class ScalePresetManager:
    """Manager for scale presets with user customization support."""

    def __init__(self, config_dir: str | None = None):
        """Initialize the scale preset manager.

        Args:
            config_dir: Directory for config files. If None, uses logs in app installation directory.
        """
        if config_dir is None:
            # Default to logs folder in the application installation directory
            # For deployed app: C:\Program Files\BML\Clinical DBS Annotator\logs
            # For development: uses the source directory
            if getattr(sys, "frozen", False):
                # Running as deployed executable (PyInstaller/Nuitka)
                app_root = Path(sys.executable).parent
            else:
                # Running in development mode
                app_root = Path(__file__).parent.parent.parent
            self.config_dir = app_root / "logs"
        else:
            self.config_dir = Path(config_dir)

        self.config_dir.mkdir(parents=True, exist_ok=True)
        self.config_file = self.config_dir / "scale_presets.json"

    def get_clinical_presets(self) -> dict[str, list[str]]:
        """Get clinical scale presets, loading user modifications if available.

        Returns:
            Dictionary of clinical scale presets (preset name -> list of scale names)
        """
        user_presets = self._load_user_presets()
        if user_presets and "clinical" in user_presets:
            return user_presets["clinical"]
        return CLINICAL_SCALES_PRESETS

    def get_session_presets(self) -> dict[str, list[tuple[str, str, str]]]:
        """Get session scale presets, loading user modifications if available.

        Returns:
            Dictionary of session scale presets (preset name -> list of (name, min, max) tuples)
        """
        user_presets = self._load_user_presets()
        if user_presets and "session" in user_presets:
            return user_presets["session"]
        return SESSION_SCALES_PRESETS

    def save_clinical_presets(self, presets: dict[str, list[str]]) -> None:
        """Save clinical scale presets to user config file.

        Args:
            presets: Dictionary of clinical scale presets (preset name -> list of scale names)
        """
        user_presets = self._load_user_presets() or {}
        user_presets["clinical"] = presets
        self._save_user_presets(user_presets)

    def save_session_presets(
        self, presets: dict[str, list[tuple[str, str, str]]]
    ) -> None:
        """Save session scale presets to user config file.

        Args:
            presets: Dictionary of session scale presets (preset name -> list of (name, min, max) tuples)
        """
        user_presets = self._load_user_presets() or {}
        user_presets["session"] = presets
        self._save_user_presets(user_presets)

    def _load_user_presets(self) -> dict | None:
        """Load user presets from config file.

        Returns:
            Dictionary with 'clinical' and 'session' keys, or None if file doesn't exist.
        """
        if not self.config_file.exists():
            return None

        try:
            with open(self.config_file, encoding="utf-8") as f:
                return json.load(f)
        except OSError, json.JSONDecodeError:
            return None

    def _save_user_presets(self, presets: dict) -> None:
        """Save user presets to config file.

        Args:
            presets: Dictionary with 'clinical' and 'session' keys
        """
        with open(self.config_file, "w", encoding="utf-8") as f:
            json.dump(presets, f, indent=4)


# Global instance
_preset_manager: ScalePresetManager | None = None


def get_scale_preset_manager() -> ScalePresetManager:
    """Get the global scale preset manager instance.

    Returns:
        The global ScalePresetManager instance
    """
    global _preset_manager
    if _preset_manager is None:
        _preset_manager = ScalePresetManager()
    return _preset_manager
