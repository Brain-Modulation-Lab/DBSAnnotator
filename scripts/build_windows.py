"""
Build script for Windows executable using PyInstaller.

This script builds a standalone Windows executable with all necessary resources.
"""

import subprocess
import sys
from pathlib import Path
import argparse

# Get project root directory
PROJECT_ROOT = Path(__file__).parent.parent
DIST_DIR = PROJECT_ROOT / "dist"
BUILD_DIR = PROJECT_ROOT / "build"
ICONS_DIR = PROJECT_ROOT / "icons"
SRC_DIR = PROJECT_ROOT / "src"

APP_NAME = "ClinicalDBSAnnot"
VERSION = "v0.3_testing"


def build_windows_exe(*, console: bool, onefile: bool) -> bool:
    """Build Windows executable using PyInstaller."""
    print(f"Building {APP_NAME} {VERSION} for Windows...")

    name = f"{APP_NAME}_{VERSION.replace('.', '_')}"
    # Use run.py as entrypoint
    entrypoint = PROJECT_ROOT / "run.py"
    styles_dir = PROJECT_ROOT / "styles"
    config_dir = SRC_DIR / "clinical_dbs_annotator" / "config"

    cmd = [
        sys.executable, "-m", "PyInstaller",
        "--noconfirm",
        "--clean",
        f"--name={name}",
        f"--paths={SRC_DIR}",
        f"--distpath={DIST_DIR}",
        f"--workpath={BUILD_DIR / 'pyinstaller'}",
        f"--specpath={BUILD_DIR / 'pyinstaller'}",
        # "--exclude-module=pythoncom",
        # "--exclude-module=pywintypes",
        # "--exclude-module=win32com",
        "--hidden-import=pytz",
        "--hidden-import=pandas",
        "--hidden-import=openpyxl",
        "--hidden-import=xlrd",
    ]

    if onefile:
        cmd.append("--onefile")
    else:
        cmd.append("--onedir")

    if console:
        cmd.append("--console")
    else:
        cmd.append("--windowed")

    cmd.extend(
        [
            f"--icon={ICONS_DIR / 'logobml.ico'}",
            f"--add-data={ICONS_DIR / 'logobml.ico'};icons",
            f"--add-data={ICONS_DIR / 'logobml.png'};icons",
            f"--add-data={styles_dir / 'dark_theme.qss'};styles",
            f"--add-data={styles_dir / 'light_theme.qss'};styles",
            f"--add-data={config_dir / 'clinical_presets.json'};config",
            f"--add-data={config_dir / 'session_scales_presets.json'};config",
            "--collect-all=PyQt5",
            str(entrypoint),
        ]
    )

    # Run PyInstaller
    try:
        subprocess.run(cmd, check=True, cwd=PROJECT_ROOT)
        print(f"\n✓ Build successful!")
        if onefile:
            exe_path = DIST_DIR / f"{name}.exe"
        else:
            exe_path = DIST_DIR / name / f"{name}.exe"
        print(f"  Executable location: {exe_path}")
    except subprocess.CalledProcessError as e:
        print(f"\n✗ Build failed: {e}")
        return False

    return True


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--console", action="store_true", help="Build with console window")
    parser.add_argument("--onedir", action="store_true", help="Build as a folder (onedir) instead of a single exe (onefile)")
    args = parser.parse_args()

    if not (ICONS_DIR / "logobml.ico").exists():
        print(f"Error: Icon file not found at {ICONS_DIR / 'logobml.ico'}")
        return 1

    if not (ICONS_DIR / "logobml.png").exists():
        print(f"Error: Logo file not found at {ICONS_DIR / 'logobml.png'}")
        return 1

    if not build_windows_exe(console=args.console, onefile=not args.onedir):
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
