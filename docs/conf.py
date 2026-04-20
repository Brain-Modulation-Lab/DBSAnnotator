from __future__ import annotations

from datetime import datetime
from importlib import metadata

_DIST_NAME = "dbs-annotator"

project = "Clinical DBS Annotator"
author = "Lucia Poma"
release = metadata.version(_DIST_NAME)
version = ".".join(release.split(".")[:2])
copyright = f"2025-{datetime.now().year}, {author}"

extensions = [
    "sphinx.ext.autodoc",
    "sphinx.ext.napoleon",
    "sphinx.ext.viewcode",
    "sphinx.ext.intersphinx",
    "sphinx_copybutton",
]

templates_path = ["_templates"]
exclude_patterns = ["_build", "Thumbs.db", ".DS_Store"]

# Known, non-actionable warnings that would otherwise fail `-W` builds.
# `image.not_readable` covers screenshots under docs/_static/ that are
# re-generated from the running app and not committed to git (tracked in
# the documentation strategy, P3: screenshot pipeline).
suppress_warnings = [
    "image.not_readable",
]

html_theme = "sphinx_rtd_theme"
html_static_path = ["_static"]

html_theme_options = {
    "logo_only": False,
    "prev_next_buttons_location": "bottom",
    "style_external_links": True,
    "collapse_navigation": False,
    "sticky_navigation": True,
    "navigation_depth": 3,
}

intersphinx_mapping = {
    "python": ("https://docs.python.org/3", None),
}

# `linkcheck` tuning: timeout aggressive, retry transient failures, and ignore
# anchor-only link failures on sites that rewrite fragments (common on GitHub).
linkcheck_timeout = 15
linkcheck_retries = 2
linkcheck_anchors = False
linkcheck_ignore: list[str] = []
