"""
Clinical DBS Annotator - A tool for annotating DBS clinical programming sessions.

This package provides a GUI for recording and managing
clinical data during Deep Brain Stimulation programming sessions.
"""

__version__ = "0.3.0-beta"
__app_name__ = "Clinical DBS Annotator"
__author__ = "BML"

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
