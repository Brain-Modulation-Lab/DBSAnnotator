"""
Main entry point for Clinical DBS Annotator application.

This module handles application initialization, theme loading,
and main window creation.
"""

import logging
import sys

import PySide6.QtSvg  # noqa: F401 - required to enable SVG rendering in QSS
from PySide6.QtWidgets import QApplication

from .logging_config import setup_bootstrap_logging, setup_logging
from .utils import get_theme_manager
from .views import WizardWindow

logger = logging.getLogger(__name__)


def main() -> int:
    """
    Main application entry point.

    Returns:
        Exit code (0 for success)
    """
    setup_bootstrap_logging()
    try:
        app = QApplication(sys.argv)

        app.setApplicationName("Clinical DBS Annotator")
        app.setOrganizationName("BML")

        setup_logging(app)

        theme_manager = get_theme_manager()
        try:
            theme_manager.apply_theme(theme_manager.get_current_theme(), app)
        except Exception:
            logger.exception("Could not load current theme")

        window = WizardWindow(app)
        window.show()

        return app.exec()
    except Exception:
        logger.critical("Fatal startup failure", exc_info=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
