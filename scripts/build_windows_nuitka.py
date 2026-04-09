#!/usr/bin/env python3
"""
Build Windows executable using Nuitka.

Requirements:
    pip install nuitka

Usage:
    python scripts/build_windows_nuitka.py [--console] [--onefile]

Options:
    --console    Include a console window (useful for debugging)
    --onefile    Create a single .exe file (default: directory bundle)
"""

import argparse
import re
import sys
from pathlib import Path

# --- Project paths ---------------------------------------------------------
PROJECT_ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = PROJECT_ROOT / "src"
DIST_DIR = PROJECT_ROOT / "dist"
BUILD_DIR = PROJECT_ROOT / "build"
ICONS_DIR = PROJECT_ROOT / "icons"
STYLES_DIR = PROJECT_ROOT / "styles"
CONFIG_DIR = SRC_DIR / "clinical_dbs_annotator" / "config"

NAME = "ClinicalDBSAnnotator"
ENTRYPOINT = PROJECT_ROOT / "run.py"


def _read_version() -> str:
    init_path = SRC_DIR / "clinical_dbs_annotator" / "__init__.py"
    text = init_path.read_text(encoding="utf-8")
    m = re.search(
        r'^__version__\s*=\s*["\']([^"\']+)["\']\s*$', text, flags=re.MULTILINE
    )
    if not m:
        raise RuntimeError(f"Could not determine version from {init_path}")
    return m.group(1)


def _base_version(version: str) -> str:
    m = re.search(r"(\d+\.\d+\.\d+)", version)
    if not m:
        raise RuntimeError(f"Could not extract base version from {version!r}")
    return m.group(1)


VERSION = _read_version()
BASE_VERSION = _base_version(VERSION)

DATA_FILES = [
    (ICONS_DIR / "logoneutral.ico", "icons"),
    (ICONS_DIR / "logoneutral.png", "icons"),
    (STYLES_DIR / "dark_theme.qss", "styles"),
    (STYLES_DIR / "light_theme.qss", "styles"),
    (CONFIG_DIR / "clinical_presets.json", "config"),
    (CONFIG_DIR / "session_scales_presets.json", "config"),
]

HIDDEN_IMPORTS = [
    "tzdata",
    "pandas",
    "openpyxl",
    "xlrd",
    "docx",
    "docx2pdf",
    "pydantic",
    "PySide6.QtCore",
    "PySide6.QtGui",
    "PySide6.QtWidgets",
    "PySide6.QtUiTools",
    "PIL.Image",
    "PIL.ImageDraw",
    "PIL.ImageFont",
]

QT_PLUGINS = [
    "platforms",
    "imageformats",
]


def build_nuitka(console: bool = False, onefile: bool = False) -> None:
    """Build the executable with Nuitka."""
    DIST_DIR.mkdir(exist_ok=True)
    BUILD_DIR.mkdir(exist_ok=True)

    cmd = [
        sys.executable,
        "-m",
        "nuitka",
        "--standalone",
        "--assume-yes-for-downloads",
        f"--output-dir={DIST_DIR}",
        f"--output-filename={NAME}.exe",
    ]

    if console:
        cmd.append("--console")
    else:
        cmd.append("--windows-disable-console")

    if onefile:
        cmd.append("--onefile")
    # Note: --remove-output is not needed, Nuitka handles cleanup

    for src_path, dest_path in DATA_FILES:
        if src_path.exists():
            cmd.append(f"--include-data-file={src_path}={dest_path}")
        else:
            print(f"Warning: Data file not found: {src_path}")

    for module in HIDDEN_IMPORTS:
        cmd.append(f"--include-module={module}")

    for plugin in QT_PLUGINS:
        cmd.append(f"--include-qt-plugin={plugin}")

    cmd.append("--follow-imports")

    cmd.extend(
        [
            "--enable-plugin=pyside6",
        ]
    )

    icon_path = ICONS_DIR / "logoneutral.ico"
    if icon_path.exists():
        cmd.append(f"--windows-icon-from-ico={icon_path}")

    cmd.extend(
        [
            "--windows-company-name=Brain Modulation Lab",
            "--windows-product-name=Clinical DBS Annotator",
            f"--windows-file-version={BASE_VERSION}",
            f"--windows-product-version={BASE_VERSION}",
        ]
    )

    cmd.append(str(ENTRYPOINT))

    print("Nuitka command:")
    print(" ".join(f'"{arg}"' if " " in str(arg) else str(arg) for arg in cmd))
    print("\nBuilding... (this may take several minutes)")

    try:
        import subprocess

        subprocess.run(cmd, check=True, cwd=PROJECT_ROOT)
        print("\n✅ Build completed successfully!")

        if onefile:
            exe_path = DIST_DIR / f"{NAME}.exe"
        else:
            exe_path = DIST_DIR / f"{NAME}.dist" / f"{NAME}.exe"

        if exe_path.exists():
            print(f"📦 Executable: {exe_path}")
            print(f"📊 Size: {exe_path.stat().st_size / (1024 * 1024):.1f} MB")
        else:
            print("⚠️  Executable not found at expected location")

    except subprocess.CalledProcessError as e:
        print(f"\n❌ Build failed with exit code {e.returncode}")
        sys.exit(1)
    except FileNotFoundError:
        print("\n❌ Nuitka not found. Install it with: pip install nuitka")
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Build Windows executable with Nuitka")
    parser.add_argument(
        "--console",
        action="store_true",
        help="Include console window (useful for debugging)",
    )
    parser.add_argument(
        "--onefile",
        action="store_true",
        help="Create single .exe file (default: directory bundle)",
    )

    args = parser.parse_args()

    print("=== Clinical DBS Annotator Nuitka Build ===")
    print(f"Console: {'Yes' if args.console else 'No'}")
    print(f"Onefile: {'Yes' if args.onefile else 'No'}")
    print()

    build_nuitka(console=args.console, onefile=args.onefile)
