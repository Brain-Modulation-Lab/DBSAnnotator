"""
DBS Annotator - A tool for annotating DBS clinical programming sessions.

This package provides a GUI for recording and managing
clinical data during Deep Brain Stimulation programming sessions.
"""

__version__ = "0.4.0b1"
__app_name__ = "DBS Annotator"

from .config import APP_LEAD_AUTHOR

__author__ = APP_LEAD_AUTHOR

from .models import ClinicalScale, SessionData, SessionScale, StimulationParameters
from .views import WizardWindow

__all__ = [
    "ClinicalScale",
    "SessionData",
    "SessionScale",
    "StimulationParameters",
    "WizardWindow",
    "__version__",
]
