"""
Base view class for wizard steps.

This module provides the base class that all step views inherit from,
containing common functionality and UI elements.
"""

from PyQt5.QtWidgets import QVBoxLayout, QWidget


class BaseStepView(QWidget):
    """
    Base class for all wizard step views.

    This class provides common functionality for step views including:
    - Common UI patterns
    - Header title provision for global header

    Subclasses should implement their specific UI in their setup methods.
    """

    def __init__(self):
        """
        Initialize the base step view.
        """
        super().__init__()
        self.main_layout = QVBoxLayout(self)

    def get_header_title(self) -> str:
        """Return the title displayed in the wizard header for this step."""
        return ""
