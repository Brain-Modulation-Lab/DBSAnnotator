"""Tests for :mod:`dbs_annotator.utils.auto_update`."""

from __future__ import annotations

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

from dbs_annotator.utils import auto_update as au


def test_install_script_url() -> None:
    url = au._install_script_url("install.ps1")
    assert "Brain-Modulation-Lab/DBSAnnotator" in url
    assert url.endswith("/scripts/install.ps1")


def test_launch_windows_invokes_powershell(tmp_path: Path) -> None:
    script = tmp_path / "install.ps1"
    script.write_text("# stub", encoding="utf-8")

    with (
        patch.object(au, "_download_install_script", return_value=script),
        patch.object(au.subprocess, "Popen") as mock_popen,
    ):
        ok, msg = au._launch_windows("v0.4.0b2")

    assert ok is True
    assert "new window" in msg.lower()
    mock_popen.assert_called_once()
    cmd = mock_popen.call_args[0][0]
    assert cmd[0] == "powershell.exe"
    assert "-VersionTag" in cmd
    assert "v0.4.0b2" in cmd
    assert "-WhatIf" not in cmd


def test_launch_windows_dry_run_adds_whatif(tmp_path: Path) -> None:
    script = tmp_path / "install.ps1"
    script.write_text("# stub", encoding="utf-8")

    with (
        patch.object(au, "_download_install_script", return_value=script),
        patch.object(au.subprocess, "Popen") as mock_popen,
    ):
        ok, msg = au._launch_windows("v0.4.0b2", dry_run=True)

    assert ok is True
    assert "dry run" in msg.lower()
    cmd = mock_popen.call_args[0][0]
    assert "-WhatIf" in cmd


def test_launch_automatic_update_empty_tag() -> None:
    ok, msg = au.launch_automatic_update("")
    assert ok is False
    assert "tag" in msg.lower()


@pytest.mark.skipif(sys.platform != "win32", reason="windows-only path")
def test_launch_automatic_update_windows() -> None:
    with (
        patch.object(au, "_launch_windows", return_value=(True, "ok")) as mock_win,
        patch.object(au, "_launch_unix"),
    ):
        ok, msg = au.launch_automatic_update("v1.0.0")
    assert ok is True
    mock_win.assert_called_once_with("v1.0.0", dry_run=False)


def test_automatic_update_supported_on_windows() -> None:
    with patch.object(sys, "platform", "win32"):
        assert au.automatic_update_supported() is True
