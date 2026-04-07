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

# --- Build configuration ----------------------------------------------------
NAME = "ClinicalDBSAnnot"
ENTRYPOINT = PROJECT_ROOT / "run.py"

# Data files to include (src_path:dest_path)
DATA_FILES = [
    (ICONS_DIR / "logoneutral.ico", "icons"),
    (ICONS_DIR / "logoneutral.png", "icons"),
    (STYLES_DIR / "dark_theme.qss", "styles"),
    (STYLES_DIR / "light_theme.qss", "styles"),
    (CONFIG_DIR / "clinical_presets.json", "config"),
    (CONFIG_DIR / "session_scales_presets.json", "config"),
]

# Hidden imports (modules that are imported dynamically)
HIDDEN_IMPORTS = [
    "pytz",
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

# Qt plugins to include
QT_PLUGINS = [
    "platforms",
    "imageformats",
]

# --- Main build function --------------------------------------------------
def build_nuitka(console: bool = False, onefile: bool = False) -> None:
    """Build the executable with Nuitka."""
    # Ensure directories exist
    DIST_DIR.mkdir(exist_ok=True)
    BUILD_DIR.mkdir(exist_ok=True)

    # Base command
    cmd = [
        sys.executable,
        "-m",
        "nuitka",
        "--standalone",
        "--assume-yes-for-downloads",
        f"--output-dir={DIST_DIR}",
        f"--output-filename={NAME}.exe",
    ]

    # Console vs windowed
    if console:
        cmd.append("--console")
    else:
        cmd.append("--windows-disable-console")

    # Onefile vs onedir
    if onefile:
        cmd.append("--onefile")
    # Note: --remove-output is not needed, Nuitka handles cleanup

    # Include data files
    for src_path, dest_path in DATA_FILES:
        if src_path.exists():
            cmd.append(f"--include-data-file={src_path}={dest_path}")
        else:
            print(f"Warning: Data file not found: {src_path}")

    # Hidden imports
    for module in HIDDEN_IMPORTS:
        cmd.append(f"--include-module={module}")

    # Include Qt plugins
    for plugin in QT_PLUGINS:
        cmd.append(f"--include-qt-plugin={plugin}")

    # Include PySide6 completely
    cmd.append("--follow-imports")

    # Optimization flags
    cmd.extend([
        "--enable-plugin=pyside6",
    ])

    # Icon
    icon_path = ICONS_DIR / "logoneutral.ico"
    if icon_path.exists():
        cmd.append(f"--windows-icon-from-ico={icon_path}")

    # Windows metadata
    cmd.extend([
        "--windows-company-name=Brain Modulation Lab",
        "--windows-product-name=Clinical DBS Annotator",
        "--windows-file-version=0.3.0",
        "--windows-product-version=0.3.0",
    ])

    # Entry point
    cmd.append(str(ENTRYPOINT))

    # Print command for debugging
    print("Nuitka command:")
    print(" ".join(f'"{arg}"' if " " in str(arg) else str(arg) for arg in cmd))
    print("\nBuilding... (this may take several minutes)")

    # Execute
    try:
        import subprocess
        result = subprocess.run(cmd, check=True, cwd=PROJECT_ROOT)
        print("\n✅ Build completed successfully!")

        # Show output location
        if onefile:
            exe_path = DIST_DIR / f"{NAME}.exe"
        else:
            exe_path = DIST_DIR / f"{NAME}.dist" / f"{NAME}.exe"

        if exe_path.exists():
            print(f"📦 Executable: {exe_path}")
            print(f"📊 Size: {exe_path.stat().st_size / (1024*1024):.1f} MB")
        else:
            print("⚠️  Executable not found at expected location")

    except subprocess.CalledProcessError as e:
        print(f"\n❌ Build failed with exit code {e.returncode}")
        sys.exit(1)
    except FileNotFoundError:
        print("\n❌ Nuitka not found. Install it with: pip install nuitka")
        sys.exit(1)

# -------------------------------------------------------------------------
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Build Windows executable with Nuitka")
    parser.add_argument("--console", action="store_true",
                       help="Include console window (useful for debugging)")
    parser.add_argument("--onefile", action="store_true",
                       help="Create single .exe file (default: directory bundle)")

    args = parser.parse_args()

    print("=== Clinical DBS Annotator Nuitka Build ===")
    print(f"Console: {'Yes' if args.console else 'No'}")
    print(f"Onefile: {'Yes' if args.onefile else 'No'}")
    print()

    build_nuitka(console=args.console, onefile=args.onefile)
