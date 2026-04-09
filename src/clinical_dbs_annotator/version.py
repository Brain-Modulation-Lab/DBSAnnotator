"""
Version helpers.

The only hardcoded version string should live in `clinical_dbs_annotator/__init__.py`.
Everything else should derive the version dynamically.
"""

from __future__ import annotations

import re
from importlib import metadata
from pathlib import Path

_DIST_NAME = "clinical-dbs-annotator"


def get_version() -> str:
    """
    Return the package version.

    Prefers installed distribution metadata (works in packaged apps),
    falling back to parsing `__init__.py` when running from a source checkout.
    """
    try:
        return metadata.version(_DIST_NAME)
    except Exception as e:
        init_path = Path(__file__).with_name("__init__.py")
        text = init_path.read_text(encoding="utf-8")
        m = re.search(
            r'^__version__\s*=\s*["\']([^"\']+)["\']\s*$', text, flags=re.MULTILINE
        )
        if not m:
            raise RuntimeError(f"Could not determine version from {init_path}") from e
        return m.group(1)


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
