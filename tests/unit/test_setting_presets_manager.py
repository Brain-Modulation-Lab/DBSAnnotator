"""Tests for SettingPresetsManager."""

from __future__ import annotations

import json

import pytest

from dbs_annotator.utils.setting_presets_manager import (
    SettingPresetsManager,
    reset_setting_presets_manager,
)


@pytest.fixture(autouse=True)
def _reset_singleton():
    reset_setting_presets_manager()
    yield
    reset_setting_presets_manager()


def test_loads_bundled_defaults_when_no_user_file(tmp_path):
    manager = SettingPresetsManager(config_dir=str(tmp_path))
    assert manager.get_frequencies() == [25, 55, 100, 125]
    assert manager.get_amplitudes() == [0.0, 1.5, 3.0, 5.0, 7.0, 10.0]
    assert manager.get_pulse_widths() == [40, 60, 90, 120]


def test_save_and_reload_round_trip(tmp_path):
    manager = SettingPresetsManager(config_dir=str(tmp_path))
    manager.save_presets([130, 140], [2.5, 4.0], [50, 80])

    reloaded = SettingPresetsManager(config_dir=str(tmp_path))
    assert reloaded.get_frequencies() == [130, 140]
    assert reloaded.get_amplitudes() == [2.5, 4.0]
    assert reloaded.get_pulse_widths() == [50, 80]


def test_normalizes_sorts_and_dedupes(tmp_path):
    manager = SettingPresetsManager(config_dir=str(tmp_path))
    manager.save_presets([100, 25, 100, 55], [10.0, 3.0, 3.0], [90, 40, 90])

    assert manager.get_frequencies() == [25, 55, 100]
    assert manager.get_amplitudes() == [3.0, 10.0]
    assert manager.get_pulse_widths() == [40, 90]


def test_rejects_empty_list_on_save(tmp_path):
    manager = SettingPresetsManager(config_dir=str(tmp_path))
    with pytest.raises(ValueError):
        manager.save_presets([], [3.0], [60])


def test_invalid_user_file_falls_back_to_bundled(tmp_path):
    config_file = tmp_path / "setting_presets.json"
    config_file.write_text("{not json", encoding="utf-8")
    manager = SettingPresetsManager(config_dir=str(tmp_path))
    assert manager.get_frequencies() == [25, 55, 100, 125]


def test_user_file_persisted_as_json(tmp_path):
    manager = SettingPresetsManager(config_dir=str(tmp_path))
    manager.save_presets([60], [1.5], [30])
    data = json.loads((tmp_path / "setting_presets.json").read_text(encoding="utf-8"))
    assert data == {
        "frequencies": [60],
        "amplitudes": [1.5],
        "pulse_widths": [30],
    }
