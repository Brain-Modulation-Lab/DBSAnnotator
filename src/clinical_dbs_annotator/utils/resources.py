"""
Resource path management utilities.

This module provides functions for locating resources (icons, styles, etc.)
whether running from source or as a PyInstaller bundle.
"""

import os
import sys


# Cache the package directory for faster lookups
_PACKAGE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def resource_path(relative_path: str) -> str:
    """
    Get the absolute path to a resource file.

    This function works both when running from source and when running
    as a PyInstaller bundle. PyInstaller creates a temp folder and stores
    path in _MEIPASS.

    Args:
        relative_path: Relative path to the resource file

    Returns:
        Absolute path to the resource file
    """
    if hasattr(sys, "_MEIPASS"):
        # Running as PyInstaller bundle
        return os.path.join(sys._MEIPASS, relative_path)
    
    # First try package-relative path (for config inside src/clinical_dbs_annotator/)
    pkg_path = os.path.join(_PACKAGE_DIR, relative_path)
    if os.path.exists(pkg_path):
        return pkg_path
    
    # Fallback to cwd-relative path (legacy)
    return os.path.join(os.path.abspath("."), relative_path)
