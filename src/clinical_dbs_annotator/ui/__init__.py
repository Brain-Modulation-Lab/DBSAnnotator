"""
UI components for Clinical DBS Annotator.

This package contains reusable UI components and widgets used throughout
the application.
"""

from .widgets import IncrementWidget, ScaleProgressWidget, create_horizontal_line, create_section_label
from .file_loader import FileDropLineEdit

__all__ = [
    "IncrementWidget",
    "ScaleProgressWidget",
    "create_horizontal_line",
    "create_section_label",
    "FileDropLineEdit",
]
