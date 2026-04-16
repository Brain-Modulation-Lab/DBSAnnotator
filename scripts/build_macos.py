"""
Build script for macOS application using PyInstaller.

This script builds a standalone macOS .app bundle with all necessary resources.
"""

import argparse
import re
import shutil
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
PLATFORM = "macOS"


def _read_version() -> str:
    init_path = SRC_DIR / "dbs_annotator" / "__init__.py"
    text = init_path.read_text(encoding="utf-8")
    m = re.search(
        r'^__version__\s*=\s*["\']([^"\']+)["\']\s*$', text, flags=re.MULTILINE
    )
    if not m:
        raise RuntimeError(f"Could not determine version from {init_path}")
    return m.group(1)


VERSION = _read_version()


def update_macos_logo(png_path: Path) -> bool:
    """Update logoneutral.png from the provided file and regenerate logoneutral.icns."""
    logo_script = PROJECT_ROOT / "scripts" / "make_macOS_logo.sh"
    target_png = ICONS_DIR / "logoneutral.png"

    if not png_path.exists():
        print(f"Error: PNG file not found at {png_path}")
        return False

    if png_path.suffix.lower() != ".png":
        print(f"Error: Icon source must be a .png file, got: {png_path}")
        return False

    if not logo_script.exists():
        print(f"Error: macOS logo script not found at {logo_script}")
        return False

    try:
        shutil.copy2(png_path, target_png)
        print(f"Updated base icon PNG: {target_png}")
        subprocess.run(["bash", str(logo_script)], check=True, cwd=PROJECT_ROOT)
        print(f"Regenerated macOS icon: {ICONS_DIR / 'logoneutral.icns'}")
    except (OSError, subprocess.CalledProcessError) as e:
        print(f"Error: Failed to update macOS icon: {e}")
        return False

    return True


def build_macos_app(*, console: bool, onefile: bool):
    """Build macOS application using PyInstaller."""
    print(f"Building {APP_NAME} {VERSION} for macOS...")

    name = f"{APP_NAME}_{PLATFORM}_{VERSION.replace('.', '_')}"
    entrypoint = PROJECT_ROOT / "run.py"
    styles_dir = PROJECT_ROOT / "styles"
    config_dir = SRC_DIR / "dbs_annotator" / "config"

    icon_icns = ICONS_DIR / "logoneutral.icns"
    icon_fallback = ICONS_DIR / "logoneutral.ico"
    icon_path = icon_icns if icon_icns.exists() else icon_fallback

    if icon_path.suffix.lower() != ".icns":
        print(f"Warning: macOS icon should be .icns, using fallback: {icon_path}")

    # PyInstaller command
    cmd = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--noconfirm",
        "--clean",
        f"--name={name}",
        f"--paths={SRC_DIR}",
        f"--distpath={DIST_DIR}",
        f"--workpath={BUILD_DIR / 'pyinstaller'}",
        f"--specpath={BUILD_DIR / 'pyinstaller'}",
        f"--icon={icon_path}",
        "--hidden-import=tzdata",
        "--hidden-import=pandas",
        "--hidden-import=openpyxl",
        "--hidden-import=xlrd",
        "--hidden-import=dbs_annotator",
        "--collect-all=PySide6",
        "--exclude-module=PySide6.QtWebEngineWidgets",
        "--exclude-module=PySide6.QtWebEngineCore",
        "--osx-bundle-identifier=com.bml.dbs-annotator",
        # Add data files (macOS uses : separator)
        f"--add-data={ICONS_DIR / 'logoneutral.ico'}:icons",
        f"--add-data={ICONS_DIR / 'logoneutral.png'}:icons",
        f"--add-data={styles_dir / 'dark_theme.qss'}:styles",
        f"--add-data={styles_dir / 'light_theme.qss'}:styles",
        f"--add-data={config_dir / 'clinical_presets.json'}:config",
        f"--add-data={config_dir / 'session_scales_presets.json'}:config",
        # Entry point
        str(entrypoint),
    ]

    if onefile:
        cmd.append("--onefile")
    else:
        cmd.append("--onedir")

    if console:
        cmd.append("--console")
    else:
        cmd.append("--windowed")

    # Add package metadata for version detection (macOS venv layout)
    venv_lib = PROJECT_ROOT / ".venv" / "lib"
    if venv_lib.exists():
        # macOS: .venv/lib/pythonX.Y/site-packages
        dist_info_dirs = list(
            venv_lib.glob("python*/site-packages/dbs_annotator*.dist-info")
        )
        if dist_info_dirs:
            cmd.append(f"--add-data={dist_info_dirs[0]}:.")

    # Run PyInstaller
    try:
        subprocess.run(cmd, check=True, cwd=PROJECT_ROOT)
        print("\n✓ Build successful!")
        if onefile:
            artifact_path = DIST_DIR / f"{name}.app"
            print(f"  Expected app bundle: {artifact_path}")
        else:
            artifact_dir = DIST_DIR / name
            print(f"  Expected output directory: {artifact_dir}")
    except subprocess.CalledProcessError as e:
        print(f"\n✗ Build failed: {e}")
        return False

    return True


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--console", action="store_true", help="Build with console window"
    )
    parser.add_argument(
        "--onedir",
        action="store_true",
        help="Build as a folder (onedir) instead of a single bundle (onefile)",
    )
    parser.add_argument(
        "--mac-logo-png",
        type=Path,
        help="Optional PNG path: copy it to icons/logoneutral.png and regenerate icons/logoneutral.icns before build",
    )
    args = parser.parse_args()

    if args.mac_logo_png is not None:
        if not update_macos_logo(args.mac_logo_png.resolve()):
            return 1

    required_files = [
        ICONS_DIR / "logoneutral.ico",
        ICONS_DIR / "logoneutral.png",
        PROJECT_ROOT / "styles" / "dark_theme.qss",
        PROJECT_ROOT / "styles" / "light_theme.qss",
        SRC_DIR / "dbs_annotator" / "config" / "clinical_presets.json",
        SRC_DIR / "dbs_annotator" / "config" / "session_scales_presets.json",
    ]

    for path in required_files:
        if not path.exists():
            print(f"Error: Required file not found at {path}")
            return 1

    if not build_macos_app(console=args.console, onefile=not args.onedir):
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
