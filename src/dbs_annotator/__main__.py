"""
Main entry point for DBS Annotator application.

This module handles application initialization, theme loading,
and main window creation.
"""

import logging
import os
import sys

import PySide6.QtSvg  # noqa: F401 - required to enable SVG rendering in QSS
from PySide6.QtGui import QIcon
from PySide6.QtWidgets import QApplication

from .config import FS_APP_NAME, FS_ORG_NAME, ICO_FILENAME, ICON_FILENAME, ICONS_DIR
from .logging_config import setup_bootstrap_logging, setup_logging
from .utils import get_theme_manager
from .utils.resources import resource_path
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

        app.setApplicationName(FS_APP_NAME)
        app.setOrganizationName(FS_ORG_NAME)

        # Windows taskbar / Alt+Tab: prefer .ico, then PNG (see icons/ at repo root).
        for name in (ICO_FILENAME, ICON_FILENAME):
            icon_path = resource_path(os.path.join(ICONS_DIR, name))
            if os.path.isfile(icon_path):
                app.setWindowIcon(QIcon(icon_path))
                break

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
