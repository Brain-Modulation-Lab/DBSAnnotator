"""
Configuration module for DBS Annotator.

This module contains all constants, presets, and configuration values used
throughout the application.
"""

from __future__ import annotations

from .version import get_version

# Human-facing product name (window titles, dialogs, documentation).
APP_NAME = "DBS Annotator"
APP_VERSION = get_version()

# Legal / marketing organization label (not used for on-disk paths).
ORGANIZATION_NAME = "Wyss Center"

# Qt application identity for :func:`QStandardPaths` and :class:`QSettings`.
# Use ASCII without spaces so per-user directories never contain spaces
# (``%LOCALAPPDATA%\\<org>\\<app>\\``, Application Support on macOS, etc.).
FS_ORG_NAME = "WyssCenter"
FS_APP_NAME = "DBSAnnotator"

# File paths (relative to executable)
ICON_FILENAME = "logoneutral.png"
ICO_FILENAME = "logoneutral.ico"
STYLE_FILENAME = "style.qss"
ICONS_DIR = "icons"

# Window size ratios for responsive design
WINDOW_SIZE_RATIO = {
    "width": 0.95,
    "height": 0.95,
}

# Responsive window size ratios based on screen size
RESPONSIVE_WINDOW_RATIOS = {
    "small": {"width": 0.9, "height": 0.85},  # < 1400px width
    "medium": {"width": 0.85, "height": 0.8},  # 1400-1919px width
    "large": {"width": 0.75, "height": 0.75},  # >= 1920px width
}

# Screen size thresholds
SCREEN_SIZE_THRESHOLDS = {
    "small": 1400,
    "medium": 1920,
}

# Minimum window size (in pixels) for usability
WINDOW_MIN_SIZE = {
    "width": 1000,  # Increased from 600 for better usability
    "height": 700,  # Increased from 400 for better usability
}

# Maximum window size ratio (prevents window from being too large on big screens)
WINDOW_MAX_SIZE_RATIO = {
    "width": 0.98,
    "height": 0.98,
}

# Responsive font scaling based on DPI
FONT_SCALE_ENABLED = False  # Disabilitato per schermi piccoli
BASE_DPI = 96  # Standard DPI

# TSV file configuration
TSV_COLUMNS = [
    "date",
    "time",
    "timezone",
    "block_id",
    "session_ID",
    "is_initial",
    "scale_name",
    "scale_value",
    "electrode_model",
    "program_ID",
    "left_stim_freq",
    "left_anode",
    "left_cathode",
    "left_amplitude",
    "left_pulse_width",
    "right_stim_freq",
    "right_anode",
    "right_cathode",
    "right_amplitude",
    "right_pulse_width",
    "notes",
]

# Annotations-only TSV file configuration.
ANNOTATION_TSV_COLUMNS = [
    "date",
    "time",
    "timezone",
    "annotation",
]

# Timezone configuration
TIMEZONE = "local"

# Validation limits
STIMULATION_LIMITS = {
    "frequency": {"min": 10, "max": 200, "step1": 10, "step2": 5},
    "amplitude": {"min": 0.0, "max": 15.0, "decimals": 2, "step1": 1, "step2": 0.5},
    "pulse_width": {"min": 10, "max": 200, "step1": 10, "step2": 5},
}

SESSION_SCALE_LIMITS = {
    "min": 0,
    "max": 10,
    "decimals": 2,
    "step1": 1,
    "step2": 0.5,
}

CLINICAL_SCALES_PRESETS: dict[str, list[str]] = {
    "OCD": [
        "Y-BOCS",  # Yale–Brown Obsessive–Compulsive Scale
        "Y-BOCS-o",  # Yale–Brown Obsessive–Compulsive Scale - obsessions
        "Y-BOCS-c",  # Yale–Brown Obsessive–Compulsive Scale - compulsions
        "MADRS",  # Montgomery–Åsberg Depression Rating Scale
        "OCI-R",  # Obsessive–Compulsive Inventory – Revised
    ],
    "MDD": [
        "MADRS",  # Montgomery–Åsberg Depression Rating Scale
        "HAM-D",  # Hamilton Depression Rating Scale
        "BDI-II",  # Beck Depression Inventory – Second Edition
    ],
    "PD": [
        # Movement Disorder Society – Unified Parkinson’s Disease Rating Scale
        "MDS-UPDRS",
        "UPDRS-III",  # Unified Parkinson’s Disease Rating Scale part III
        "PDQ-39",  # Parkinson’s Disease Questionnaire (39-item)
        "UDysRS",  # Unified Dyskinesia Rating Scale
    ],
    "ET": [
        "FTM-TRS",  # Fahn–Tolosa–Marin Tremor Rating Scale
        "TETRAS",  # The Essential Tremor Rating Assessment Scale
    ],
    "Dystonia": [
        "BFMDRS",  # Burke–Fahn–Marsden Dystonia Rating Scale
        "TWSTRS",  # Toronto Western Spasmodic Torticollis Rating Scale
    ],
    "TS": [
        "YGTSS",  # Yale Global Tic Severity Scale
        "PUTS",  # Premonitory Urge for Tics Scale
        "TS-CGI",  # Tourette Syndrome Clinical Global Impression
        "Y-BOCS",  # Yale–Brown Obsessive–Compulsive Scale
    ],
}

SESSION_SCALES_PRESETS: dict[str, list[tuple[str, str, str]]] = {
    "OCD": [
        ("Obsessions", "0", "10"),
        ("Compulsions", "0", "10"),
        ("Anxiety", "0", "10"),
        ("Mood", "0", "10"),
        ("Energy", "0", "10"),
    ],
    "MDD": [
        ("Rumination", "0", "10"),
        ("Anxiety", "0", "10"),
        ("Mood", "0", "10"),
        ("Energy", "0", "10"),
    ],
    "PD": [
        ("Tremor", "0", "10"),
        ("Rigidity", "0", "10"),
        ("Bradykinesia", "0", "10"),
        ("Dyskinesia", "0", "10"),
        ("Gait / balance", "0", "10"),
        ("Paresthesia", "0", "10"),
        ("Speech difficulty", "0", "10"),
    ],
    "ET": [
        ("Action tremor", "0", "10"),
        ("Resting tremor", "0", "10"),
        ("Paresthesia", "0", "10"),
        ("Speech difficulty", "0", "10"),
    ],
    "Dystonia": [
        ("Muscle contractions", "0", "10"),
        ("Abnormal posture", "0", "10"),
        ("Pain", "0", "10"),
    ],
    "TS": [
        ("Tic severity", "0", "10"),
        ("Premonitory urge", "0", "10"),
        ("Control over tics", "0", "10"),
        ("Anxiety", "0", "10"),
        ("Impulsivity", "0", "10"),
    ],
}
PRESET_BUTTONS = ["OCD", "MDD", "PD", "ET", "Dystonia", "TS"]

COLORS = {
    "primary": "#ff8800",
    "background": "#23272f",
    "text": "#e0e0e0",
    "button_pressed": "#ff6600",
    "separator": "#3a3a3a",
}

FONTS = {
    "default": ("Segoe UI", 12),
    "section": ("Segoe UI", 16),
    "title": ("Segoe UI", 20),
}

# Animation settings
BUTTON_PULSE_COUNT = 3
BUTTON_PULSE_DURATION = 120  # milliseconds

# UI Component sizes
ICON_SIZES = {
    "logo_step1": 90,
    "logo_other": 70,
    "arrow": (22, 22),
    "increment": (16, 16),
}

BUTTON_SIZES = {
    "browse": 40,
    "navigation": 150,
    "preset": {"min_width": 30, "max_width": 40, "min_height": 18, "max_height": 24},
    "increment": {"width": 20, "height": 14},
}

PLACEHOLDERS = {
    "frequency": "Hz",
    "contact": "E#",
    "amplitude": "mA",
    "pulse_width": "µs",
    "scale_value": "Value",
    "scale_name": "Scale",
    "scale_score": "Score",
    "scale_min": "Min",
    "scale_max": "Max",
}
