"""
Main entry point for Clinical DBS Annotator application.

This module handles application initialization, theme loading,
and main window creation.
"""

import os
import sys
import tempfile
import traceback

from PySide6.QtWidgets import QApplication

from .utils import get_theme_manager
from .views import WizardWindow


def main() -> int:
    """
    Main application entry point.

    Returns:
        Exit code (0 for success)
    """
    try:
        # Check for required dependencies
        try:
            import pytz  # noqa: F401
        except ImportError:
            print("Error: pytz is required. Install with: pip install pytz")
            return 1

        # Create application
        app = QApplication(sys.argv)

        # Set application metadata
        app.setApplicationName("Clinical DBS Annotator")
        app.setOrganizationName("BML")

        # Load and apply theme
        theme_manager = get_theme_manager()
        try:
            theme_manager.apply_theme(theme_manager.get_current_theme(), app)
        except Exception as e:
            print(f"Warning: Could not load theme: {e}")
            print("Continuing with default styling...")

        # Create and show main window
        window = WizardWindow(app)
        window.show()

        # Run application
        return app.exec()

    except Exception:
        print("FATAL ERROR:")
        traceback.print_exc()
        try:
            log_path = os.path.join(tempfile.gettempdir(), "ClinicalDBSAnnot_crash.log")
            with open(log_path, "w", encoding="utf-8") as f:
                f.write(traceback.format_exc())
        except Exception:
            pass
        return 1


if __name__ == "__main__":
    sys.exit(main())
