"""
Scale preset manager for loading and saving user-modified scale presets.

This module persists clinical and session scale presets under the platform's
per-user application data directory so the file survives reinstalls and
upgrades.
"""

from __future__ import annotations

from ..config import CLINICAL_SCALES_PRESETS, SESSION_SCALES_PRESETS
from .user_data import read_json, resolve_config_file, write_json


class ScalePresetManager:
    """Manager for scale presets with user customization support."""

    CONFIG_FILENAME = "scale_presets.json"

    def __init__(self, config_dir: str | None = None):
        """Initialize the scale preset manager.

        Args:
            config_dir: Directory for config files. If None, uses the
                platform-appropriate per-user data directory (upgrade-safe).
                Explicit paths are primarily for tests.
        """
        self.config_dir, self.config_file = resolve_config_file(
            self.CONFIG_FILENAME, config_dir
        )

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
            Dictionary of session scale presets (preset name -> list of
            ``(name, min, max)`` tuples).
        """
        user_presets = self._load_user_presets()
        if user_presets and "session" in user_presets:
            return user_presets["session"]
        return SESSION_SCALES_PRESETS

    def save_clinical_presets(self, presets: dict[str, list[str]]) -> None:
        """Save clinical scale presets to user config file.

        Args:
            presets: Dictionary of clinical scale presets (preset name ->
                list of scale names).
        """
        user_presets = self._load_user_presets() or {}
        user_presets["clinical"] = presets
        self._save_user_presets(user_presets)

    def save_session_presets(
        self, presets: dict[str, list[tuple[str, str, str]]]
    ) -> None:
        """Save session scale presets to user config file.

        Args:
            presets: Dictionary of session scale presets (preset name ->
                list of ``(name, min, max)`` tuples).
        """
        user_presets = self._load_user_presets() or {}
        user_presets["session"] = presets
        self._save_user_presets(user_presets)

    def _load_user_presets(self) -> dict | None:
        """Load user presets ('clinical'/'session' keys), or None if absent."""
        return read_json(self.config_file)

    def _save_user_presets(self, presets: dict) -> None:
        """Save user presets ('clinical'/'session' keys) to the config file."""
        write_json(self.config_file, presets, indent=4)


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
