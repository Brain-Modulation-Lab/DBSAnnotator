"""Program configuration manager for custom program names.

This module handles loading, saving, and managing custom program names
used in the DBS clinical programming interface. Config is persisted under
the platform's per-user application data directory so it survives app
reinstalls and upgrades.
"""

from __future__ import annotations

from .user_data import read_json, resolve_config_file, write_json


class ProgramConfigManager:
    """Manages program name configuration with persistence."""

    DEFAULT_PROGRAMS = ["None", "A", "B", "C", "D"]
    CONFIG_FILENAME = "program_names.json"

    def __init__(self, config_dir: str | None = None):
        """Initialize the program config manager.

        Args:
            config_dir: Directory for config files. If None, uses the
                platform-appropriate per-user data directory (upgrade-safe).
                Explicit paths are primarily for tests.
        """
        self.config_dir, self.config_file = resolve_config_file(
            self.CONFIG_FILENAME, config_dir
        )

        self._custom_programs: list[str] = []
        self._load_custom_programs()

    def _load_custom_programs(self) -> None:
        """Load custom program names from config file."""
        data = read_json(self.config_file)
        self._custom_programs = data.get("custom_programs", []) if data else []

    def save_custom_programs(self, programs: list[str]) -> None:
        """Save custom program names to config file.

        Args:
            programs: List of custom program names to save.
        """
        self._custom_programs = programs
        try:
            write_json(self.config_file, {"custom_programs": programs})
        except OSError:
            pass

    def get_all_programs(self) -> list[str]:
        """Get all available programs (default + custom).

        Returns:
            List of program names.
        """
        return self.DEFAULT_PROGRAMS + self._custom_programs

    def get_custom_programs(self) -> list[str]:
        """Get only custom program names.

        Returns:
            List of custom program names.
        """
        return self._custom_programs.copy()

    def add_program(self, program_name: str) -> bool:
        """Add a new custom program name.

        Args:
            program_name: Name of the program to add.

        Returns:
            True if added, False if already exists or invalid.
        """
        if (
            not program_name
            or program_name in self.DEFAULT_PROGRAMS
            or program_name in self._custom_programs
        ):
            return False

        self._custom_programs.append(program_name)
        self.save_custom_programs(self._custom_programs)
        return True

    def remove_program(self, program_name: str) -> bool:
        """Remove a custom program name.

        Args:
            program_name: Name of the program to remove.

        Returns:
            True if removed, False if not found or is a default program.
        """
        if program_name in self.DEFAULT_PROGRAMS:
            return False

        if program_name in self._custom_programs:
            self._custom_programs.remove(program_name)
            self.save_custom_programs(self._custom_programs)
            return True
        return False

    def update_program(self, old_name: str, new_name: str) -> bool:
        """Update an existing custom program name.

        Args:
            old_name: Current name of the program.
            new_name: New name for the program.

        Returns:
            True if updated, False if old_name not found or new_name invalid.
        """
        if old_name in self.DEFAULT_PROGRAMS:
            return False

        if (
            not new_name
            or new_name in self.DEFAULT_PROGRAMS
            or new_name in self._custom_programs
        ):
            return False

        if old_name in self._custom_programs:
            idx = self._custom_programs.index(old_name)
            self._custom_programs[idx] = new_name
            self.save_custom_programs(self._custom_programs)
            return True
        return False


# Singleton instance
_instance: ProgramConfigManager | None = None


def get_program_config_manager() -> ProgramConfigManager:
    """Get the singleton ProgramConfigManager instance.

    Returns:
        The singleton instance.
    """
    global _instance
    if _instance is None:
        _instance = ProgramConfigManager()
    return _instance
