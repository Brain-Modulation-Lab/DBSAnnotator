"""
Build script for macOS application using PyInstaller.

This script builds a standalone macOS .app bundle with all necessary resources.
"""

import os
import subprocess
import sys
from pathlib import Path

# Get project root directory
PROJECT_ROOT = Path(__file__).parent.parent
DIST_DIR = PROJECT_ROOT / "dist"
BUILD_DIR = PROJECT_ROOT / "build"
ICONS_DIR = PROJECT_ROOT / "icons"
SRC_DIR = PROJECT_ROOT / "src"

APP_NAME = "ClinicalDBSAnnot"
VERSION = "v0.1"


def build_macos_app():
    """Build macOS application using PyInstaller."""
    print(f"Building {APP_NAME} {VERSION} for macOS...")

    # PyInstaller command
    cmd = [
        "pyinstaller",
        "--onefile",  # Single file executable
        "--windowed",  # No console window
        f"--name={APP_NAME}_{VERSION.replace('.', '_')}",
        f"--icon={ICONS_DIR / 'logobml.ico'}",
        # Add data files (macOS uses : separator)
        f"--add-data={ICONS_DIR / 'logobml.ico'}:icons",
        f"--add-data={ICONS_DIR / 'logobml.png'}:icons",
        f"--add-data={PROJECT_ROOT / 'style.qss'}:.",
        # Collect all PyQt5 plugins
        "--collect-all=PyQt5",
        # Entry point
        f"{SRC_DIR / 'clinical_dbs_annotator' / '__main__.py'}",
    ]

    # Run PyInstaller
    try:
        subprocess.run(cmd, check=True, cwd=PROJECT_ROOT)
        print(f"\n✓ Build successful!")
        print(f"  Application location: {DIST_DIR / f'{APP_NAME}_{VERSION.replace('.', '_')}.app'}")
    except subprocess.CalledProcessError as e:
        print(f"\n✗ Build failed: {e}")
        return False

    return True


def main():
    """Main entry point."""
    if not (ICONS_DIR / "logobml.ico").exists():
        print(f"Error: Icon file not found at {ICONS_DIR / 'logobml.ico'}")
        return 1

    if not (ICONS_DIR / "logobml.png").exists():
        print(f"Error: Logo file not found at {ICONS_DIR / 'logobml.png'}")
        return 1

    if not build_macos_app():
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
