"""
Version helpers.

The only hardcoded version string should live in `dbs_annotator/__init__.py`.
Everything else should derive the version dynamically.
"""

from __future__ import annotations

import re
import sys
from importlib import metadata
from pathlib import Path

_DIST_NAME = "dbs-annotator"


def get_version() -> str:
    """
    Return the package version.

    Prefers installed distribution metadata (works in packaged apps),
    falling back to parsing `__init__.py` when running from a source checkout.
    In a PyInstaller frozen bundle, source files are not available on disk,
    so we fall back to the already-loaded ``__version__`` attribute.
    """
    # 1. Try installed metadata (normal pip/uv install)
    try:
        return metadata.version(_DIST_NAME)
    except Exception:
        pass

    # 2. Try reading __init__.py from source (development mode)
    if not getattr(sys, "frozen", False):
        try:
            init_path = Path(__file__).with_name("__init__.py")
            text = init_path.read_text(encoding="utf-8")
            m = re.search(
                r'^__version__\s*=\s*["\']([^"\']+)["\']\s*$',
                text,
                flags=re.MULTILINE,
            )
            if m:
                return m.group(1)
        except Exception:
            pass

    # 3. PyInstaller frozen: __init__.py is compiled, not on disk.
    #    Check if the package module is already loaded.
    pkg = sys.modules.get("dbs_annotator")
    if pkg is not None:
        v = getattr(pkg, "__version__", None)
        if v is not None:
            return v

    raise RuntimeError("Could not determine version for dbs-annotator")


def get_pep440_base_version() -> str:
    """
    Return the numeric x.y.z portion of the version.

    Useful for Windows file/product version fields that must be strictly numeric.
    """
    v = get_version()
    m = re.search(r"(\d+\.\d+\.\d+)", v)
    if not m:
        raise RuntimeError(f"Could not extract base version from {v!r}")
    return m.group(1)
