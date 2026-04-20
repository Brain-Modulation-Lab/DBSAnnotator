"""
Resource path management utilities.

This module provides functions for locating resources (icons, styles, etc.)
whether running from source or from a frozen/bundled application layout.
"""

import os
import sys

# Cache the package directory for faster lookups
_PACKAGE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def resource_path(relative_path: str) -> str:
    """
    Get the absolute path to a resource file.

    This function works both when running from source and when running
    from a frozen bundle that exposes resources via ``sys._MEIPASS``.

    Args:
        relative_path: Relative path to the resource file

    Returns:
        Absolute path to the resource file
    """
    if hasattr(sys, "_MEIPASS"):
        # Running as a frozen bundle exposing an extraction directory
        return os.path.join(sys._MEIPASS, relative_path)

    # First try package-relative path (for config, styles, and vendored icons under
    # src/dbs_annotator/).
    pkg_path = os.path.join(_PACKAGE_DIR, relative_path)
    if os.path.exists(pkg_path):
        return pkg_path

    # BeeWare Briefcase Windows layout: sibling `icons/` next to the
    # package under `src/`.
    src_dir = os.path.dirname(_PACKAGE_DIR)
    sibling_path = os.path.join(src_dir, relative_path)
    if os.path.exists(sibling_path):
        return sibling_path

    # Editable / source checkout: repo-root `icons/` (two levels above the package dir).
    repo_root = os.path.abspath(os.path.join(_PACKAGE_DIR, os.pardir, os.pardir))
    repo_path = os.path.join(repo_root, relative_path)
    if os.path.exists(repo_path):
        return repo_path

    # Fallback to cwd-relative path (legacy)
    return os.path.join(os.path.abspath("."), relative_path)
