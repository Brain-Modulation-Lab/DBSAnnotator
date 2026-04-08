from __future__ import annotations

from datetime import datetime
from importlib import metadata

_DIST_NAME = "clinical-dbs-annotator"

project = "Clinical DBS Annotator"
author = "Lucia Poma"
release = metadata.version(_DIST_NAME)
copyright = f"2025-{datetime.now().year}, {author}"

extensions = [
    "sphinx.ext.autodoc",
    "sphinx.ext.napoleon",
    "sphinx.ext.viewcode",
]

templates_path = ["_templates"]
exclude_patterns = ["_build", "Thumbs.db", ".DS_Store"]

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
