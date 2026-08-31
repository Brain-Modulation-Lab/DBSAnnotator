"""Sphinx configuration for the DBS Annotator documentation.

The application is written in Dart, so — unlike the frozen Qt app's docs, which
this replaced — nothing here imports the software. Two consequences:

* Read the Docs installs only ``docs/requirements.txt``. No Python project, no
  ``uv``, and no Qt system libraries (the old config pulled in ``libegl1`` and
  friends purely because autosummary imported PySide6 transitively).
* ``autodoc``, ``autosummary``, ``napoleon`` and ``viewcode`` are gone. They had
  no target. A Dart API reference via ``dartdoc`` is a separate decision.
"""

from __future__ import annotations

import re
from datetime import datetime
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent

# -- Identity ----------------------------------------------------------------
# Literals on purpose. The upstream values live in lib/app_info.dart, and
# regex-scraping three strings that change approximately never out of Dart
# source is more machinery than one duplicated line. Only the VERSION is
# derived, because only the version changes every release.
project = "DBS Annotator"
author = "Lucia Poma"
_HOLDERS = (
    "Wyss Center for Bio and Neuroengineering, Massachusetts General Hospital, "
    "and Charité Universitätsmedizin Berlin"
)
copyright = f"2025-{datetime.now().year}, {_HOLDERS}"  # noqa: A001
html_context = {"contact_email": "lucia.poma@wysscenter.ch"}


def _flutter_version() -> str:
    """``version: 0.1.0+1`` in pubspec.yaml -> ``0.1.0``.

    A regex rather than a YAML parser, because PyYAML is not in the standard
    library and this is the only field needed — a pubspec ``version`` is always
    a top-level scalar.

    Raises rather than defaulting: a silent ``0.0.0`` in the footer of a
    clinical tool's documentation is worse than a red build.
    """
    text = (_ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"^version:\s*([0-9][^\s+#]*)", text, re.MULTILINE)
    if match is None:
        raise RuntimeError("no `version:` found in pubspec.yaml")
    return match.group(1)


release = _flutter_version()
version = ".".join(release.split(".")[:2])

# -- General -----------------------------------------------------------------
extensions = [
    "sphinx_copybutton",
    "myst_parser",
]

# `intersphinx` is deliberately absent. With fail_on_warning enabled, a
# transient failure fetching a remote objects.inv emits a warning and therefore
# breaks publishing. Re-add it only when something actually cross-references
# another project's API.

exclude_patterns = ["_build", "Thumbs.db", ".DS_Store", "requirements.txt"]

source_suffix = {".rst": "restructuredtext", ".md": "markdown"}

# -- HTML --------------------------------------------------------------------
html_theme = "sphinx_rtd_theme"
html_static_path = ["_static"]
html_css_files = ["custom.css"]
html_favicon = "_static/favicon-32.png"

html_theme_options = {
    "logo_only": False,
    "prev_next_buttons_location": "bottom",
    "style_external_links": True,
    "collapse_navigation": False,
    "sticky_navigation": True,
    "navigation_depth": 3,
}

# No `suppress_warnings`. The old config silenced `image.not_readable` because
# screenshots were regenerated from a running Qt app and could legitimately be
# missing mid-build. Here every screenshot is committed, so a missing image is a
# real error and should fail the build.

# -- MyST --------------------------------------------------------------------
myst_enable_extensions = ["colon_fence", "deflist", "smartquotes"]
myst_heading_anchors = 3

# -- linkcheck ---------------------------------------------------------------
linkcheck_timeout = 15
linkcheck_retries = 2
linkcheck_anchors = False
