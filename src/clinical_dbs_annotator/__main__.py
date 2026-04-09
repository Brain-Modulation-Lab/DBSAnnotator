"""
Main entry point for Clinical DBS Annotator application.

This module handles application initialization, theme loading,
and main window creation.
"""

import logging
import sys

import PySide6.QtSvg  # noqa: F401 - required to enable SVG rendering in QSS
from PySide6.QtWidgets import QApplication

from .logging_config import setup_logging
from .utils import get_theme_manager
from .views import WizardWindow


def main() -> int:
    """
    Main application entry point.

    Returns:
        Exit code (0 for success)
    """
    app = QApplication(sys.argv)

    app.setApplicationName("Clinical DBS Annotator")
    app.setOrganizationName("BML")

    setup_logging(app)

    theme_manager = get_theme_manager()
    try:
        theme_manager.apply_theme(theme_manager.get_current_theme(), app)
    except Exception as e:
        logging.warning("Could not load theme: %s", e)

    window = WizardWindow(app)
    window.show()

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
