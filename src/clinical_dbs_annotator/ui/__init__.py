"""
UI components for Clinical DBS Annotator.

This package contains reusable UI components and widgets used throughout
the application.
"""

from .amplitude_split_widget import AmplitudeSplitWidget, get_cathode_labels
from .file_loader import FileDropLineEdit
from .widgets import (
    IncrementWidget,
    ScaleProgressWidget,
    create_horizontal_line,
    create_section_label,
)

__all__ = [
    "IncrementWidget",
    "ScaleProgressWidget",
    "create_horizontal_line",
    "create_section_label",
    "FileDropLineEdit",
    "AmplitudeSplitWidget",
    "get_cathode_labels",
]
