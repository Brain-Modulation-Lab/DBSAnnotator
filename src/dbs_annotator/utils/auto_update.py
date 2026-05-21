"""Launch platform install scripts to upgrade a packaged DBS Annotator build."""

from __future__ import annotations

import logging
import os
import ssl
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

import certifi

from ..config import RELEASES_GITHUB_REPO

logger = logging.getLogger(__name__)

_INSTALL_SCRIPT_BRANCH = "main"
_USER_AGENT = "DBSAnnotator-AutoUpdate/1.0"
# Windows-only; absent on Linux/macOS (CI runs unit tests there too).
_WINDOWS_NEW_CONSOLE = getattr(subprocess, "CREATE_NEW_CONSOLE", 0)


def _install_script_url(filename: str) -> str:
    return (
        f"https://raw.githubusercontent.com/{RELEASES_GITHUB_REPO}/"
        f"{_INSTALL_SCRIPT_BRANCH}/scripts/{filename}"
    )


def _download_install_script(filename: str) -> Path:
    url = _install_script_url(filename)
    request = urllib.request.Request(
        url,
        headers={"User-Agent": _USER_AGENT},
    )
    ctx = ssl.create_default_context(cafile=certifi.where())
    with urllib.request.urlopen(request, timeout=60, context=ctx) as response:
        data = response.read()
    suffix = ".ps1" if filename.endswith(".ps1") else ".sh"
    fd, path_str = tempfile.mkstemp(prefix="dbs_annotator_install_", suffix=suffix)
    os.close(fd)
    path = Path(path_str)
    path.write_bytes(data)
    if suffix == ".sh":
        path.chmod(0o755)
    return path


def automatic_update_supported() -> bool:
    """True on platforms where ``scripts/install.*`` can be launched."""
    return (
        sys.platform == "win32"
        or sys.platform == "darwin"
        or sys.platform.startswith("linux")
    )


def automatic_update_targets_packaged_install() -> bool:
    """True when the updater installs into the standard Briefcase location."""
    return bool(getattr(sys, "frozen", False))


def launch_automatic_update(
    tag_name: str,
    *,
    dry_run: bool = False,
) -> tuple[bool, str]:
    """Start the GitHub release installer for *tag_name* (e.g. ``v0.4.0b2``).

    Args:
        dry_run: If True, run the platform install script in preview mode only
            (PowerShell ``-WhatIf`` / ``install.sh --dry-run``). No files are
            written.

    Returns:
        ``(True, user_message)`` on success, ``(False, error_message)`` otherwise.
        The installer runs in a separate process; the user must restart the app.
    """
    tag = tag_name.strip()
    if not tag:
        return False, "Release tag is missing."

    try:
        if sys.platform == "win32":
            return _launch_windows(tag, dry_run=dry_run)
        if sys.platform == "darwin":
            return _launch_unix(tag, "install.sh", dry_run=dry_run)
        if sys.platform.startswith("linux"):
            return _launch_unix(tag, "install.sh", dry_run=dry_run)
        return False, f"Automatic update is not supported on {sys.platform!r}."
    except OSError as exc:
        logger.info("Automatic update failed: %s", exc)
        return False, str(exc)
    except urllib.error.URLError as exc:
        logger.info("Could not download install script: %s", exc)
        return False, f"Could not download the installer script:\n\n{exc}"


def _launch_windows(tag: str, *, dry_run: bool = False) -> tuple[bool, str]:
    script = _download_install_script("install.ps1")
    try:
        cmd = [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(script),
            "-VersionTag",
            tag,
            "-GitHubRepository",
            RELEASES_GITHUB_REPO,
        ]
        if dry_run:
            cmd.append("-WhatIf")
        subprocess.Popen(
            cmd,
            creationflags=_WINDOWS_NEW_CONSOLE,
            close_fds=True,
        )
    finally:
        if not dry_run:
            try:
                script.unlink(missing_ok=True)
            except OSError:
                pass

    if dry_run:
        return True, (
            "Dry run: a PowerShell window will show what the installer would do "
            "(no files are changed). Check that window for errors before running "
            "a real update."
        )
    return True, (
        "The updater is running in a new window. When it finishes, close this "
        "application and open DBS Annotator again from the Start menu."
    )


def _launch_unix(tag: str, filename: str, *, dry_run: bool = False) -> tuple[bool, str]:
    script = _download_install_script(filename)
    args = "--dry-run" if dry_run else ""
    wrapper = script.with_name(f"run_{script.name}")
    wrapper.write_text(
        "#!/bin/sh\n"
        f'export DBS_ANNOTATOR_INSTALL_REPO="{RELEASES_GITHUB_REPO}"\n'
        f'export DBS_ANNOTATOR_VERSION="{tag}"\n'
        f'exec "{script}" {args} "{tag}"\n',
        encoding="utf-8",
    )
    wrapper.chmod(0o755)

    if sys.platform == "darwin":
        cmd = [
            "osascript",
            "-e",
            f'tell application "Terminal" to do script "{wrapper}"',
        ]
        subprocess.Popen(cmd, start_new_session=True, close_fds=True)
    else:
        launched = False
        for term_cmd in (
            ["x-terminal-emulator", "-e", str(wrapper)],
            ["konsole", "-e", str(wrapper)],
            ["gnome-terminal", "--", str(wrapper)],
        ):
            if _which(term_cmd[0]):
                subprocess.Popen(
                    term_cmd,
                    start_new_session=True,
                    close_fds=True,
                )
                launched = True
                break
        if not launched:
            env = os.environ.copy()
            env["DBS_ANNOTATOR_INSTALL_REPO"] = RELEASES_GITHUB_REPO
            env["DBS_ANNOTATOR_VERSION"] = tag
            cmd = [str(script)]
            if dry_run:
                cmd.append("--dry-run")
            cmd.append(tag)
            subprocess.Popen(
                cmd,
                env=env,
                start_new_session=True,
                close_fds=True,
            )

    if dry_run:
        return True, (
            "Dry run: a terminal window will show what the installer would do "
            "(no files are changed). Check that window for errors before running "
            "a real update."
        )
    return True, (
        "The updater is running. When it finishes, quit this application and "
        "reopen DBS Annotator from your applications menu."
    )


def _which(name: str) -> str | None:
    from shutil import which

    return which(name)
