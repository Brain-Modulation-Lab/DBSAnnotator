"""Setting presets manager for stimulation parameter quick-picks."""

from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import cast

from ..config import STIMULATION_LIMITS
from .resources import resource_path
from .user_data import user_config_file, user_data_dir

BUNDLED_PRESETS_PATH = "config/setting_presets.json"
CONFIG_FILENAME = "setting_presets.json"


class SettingPresetsManager:
    """Load and save frequency, amplitude, and pulse-width preset lists."""

    def __init__(self, config_dir: str | None = None) -> None:
        if config_dir is None:
            self.config_dir = user_data_dir()
            self.config_file = user_config_file(CONFIG_FILENAME)
        else:
            self.config_dir = Path(config_dir)
            self.config_dir.mkdir(parents=True, exist_ok=True)
            self.config_file = self.config_dir / CONFIG_FILENAME
        self._data = self._load()

    def _load_bundled(self) -> dict[str, list]:
        path = resource_path(BUNDLED_PRESETS_PATH)
        with open(path, encoding="utf-8") as f:
            return json.load(f)

    def _load(self) -> dict[str, list]:
        if self.config_file.exists():
            try:
                with open(self.config_file, encoding="utf-8") as f:
                    data = json.load(f)
                if self._is_valid_data(data):
                    return data
            except (OSError, json.JSONDecodeError):
                pass
        return copy.deepcopy(self._load_bundled())

    @staticmethod
    def _is_valid_data(data: object) -> bool:
        if not isinstance(data, dict):
            return False
        payload = cast(dict[str, object], data)
        for key in ("frequencies", "amplitudes", "pulse_widths"):
            values = payload.get(key)
            if not isinstance(values, list) or not values:
                return False
        return True

    def get_frequencies(self) -> list[int]:
        return self._normalize_ints(self._data["frequencies"], "frequency")

    def get_amplitudes(self) -> list[float]:
        return self._normalize_floats(self._data["amplitudes"], "amplitude")

    def get_pulse_widths(self) -> list[int]:
        return self._normalize_ints(self._data["pulse_widths"], "pulse_width")

    def save_presets(
        self,
        frequencies: list,
        amplitudes: list,
        pulse_widths: list,
    ) -> None:
        """Persist preset lists after validation."""
        freq = self._normalize_ints(frequencies, "frequency")
        amps = self._normalize_floats(amplitudes, "amplitude")
        pws = self._normalize_ints(pulse_widths, "pulse_width")
        if not freq or not amps or not pws:
            raise ValueError("Each preset list must contain at least one valid value")
        self._data = {
            "frequencies": freq,
            "amplitudes": amps,
            "pulse_widths": pws,
        }
        try:
            with open(self.config_file, "w", encoding="utf-8") as f:
                json.dump(self._data, f, indent=2, ensure_ascii=False)
        except OSError:
            pass

    def _normalize_ints(self, values: list, kind: str) -> list[int]:
        limits = STIMULATION_LIMITS[kind]
        lo, hi = int(limits["min"]), int(limits["max"])
        seen: set[int] = set()
        result: list[int] = []
        for value in values:
            try:
                number = int(round(float(value)))
            except (TypeError, ValueError):
                continue
            number = max(lo, min(hi, number))
            if number not in seen:
                seen.add(number)
                result.append(number)
        result.sort()
        return result

    def _normalize_floats(self, values: list, kind: str) -> list[float]:
        limits = STIMULATION_LIMITS[kind]
        lo, hi = float(limits["min"]), float(limits["max"])
        seen: set[float] = set()
        result: list[float] = []
        for value in values:
            try:
                number = round(float(value), int(limits["decimals"]))
            except (TypeError, ValueError):
                continue
            number = max(lo, min(hi, number))
            if number not in seen:
                seen.add(number)
                result.append(number)
        result.sort()
        return result


_instance: SettingPresetsManager | None = None


def get_setting_presets_manager() -> SettingPresetsManager:
    """Return the singleton SettingPresetsManager instance."""
    global _instance
    if _instance is None:
        _instance = SettingPresetsManager()
    return _instance


def reset_setting_presets_manager() -> None:
    """Reset the singleton (for tests)."""
    global _instance
    _instance = None
