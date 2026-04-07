#!/usr/bin/env python3
"""
Quick build shortcuts for Clinical DBS Annotator.

Usage:
    python scripts/build_quick.py windows-release    # Onefile, no console
    python scripts/build_quick.py windows-debug      # Onedir, with console
    python scripts/build_quick.py mac-release       # macOS (if available)
"""

import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent

def run_command(cmd, cwd=None):
    """Run a command and handle errors."""
    print(f"Running: {' '.join(cmd)}")
    try:
        subprocess.run(cmd, check=True, cwd=cwd)
        print("✅ Success")
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed with exit code {e.returncode}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python scripts/build_quick.py <target>")
        print("Targets:")
        print("  windows-release  - Onefile, no console (for distribution)")
        print("  windows-debug    - Onedir, with console (for testing)")
        sys.exit(1)

    target = sys.argv[1]

    if target == "windows-release":
        # Nuitka: onefile, no console
        cmd = [sys.executable, "scripts/build_windows_nuitka.py", "--onefile"]
        run_command(cmd, cwd=PROJECT_ROOT)

    elif target == "windows-debug":
        # Nuitka: onedir, with console
        cmd = [sys.executable, "scripts/build_windows_nuitka.py", "--console"]
        run_command(cmd, cwd=PROJECT_ROOT)

    elif target == "windows-pyinstaller":
        # Fallback to PyInstaller
        cmd = [sys.executable, "scripts/build_windows.py"]
        run_command(cmd, cwd=PROJECT_ROOT)

    else:
        print(f"Unknown target: {target}")
        sys.exit(1)
