"""
Configuration module for Clinical DBS Annotator.

This module contains all constants, presets, and configuration values used
throughout the application.
"""

from typing import Dict, List, Tuple

# Application metadata
APP_NAME = "BML Annotator for DBS clinical programming sessions"
APP_VERSION = "v0.3_testing"
ORGANIZATION_NAME = "BML"

# File paths (relative to executable)
ICON_FILENAME = "logobml.png"
ICO_FILENAME = "logobml.ico"
STYLE_FILENAME = "style.qss"
ICONS_DIR = "icons"

# Window size ratios for responsive design
WINDOW_SIZE_RATIO = {
    "width": 0.95,
    "height": 0.95,
}

# Responsive window size ratios based on screen size
RESPONSIVE_WINDOW_RATIOS = {
    "small": {"width": 0.9, "height": 0.85},   # < 1400px width
    "medium": {"width": 0.85, "height": 0.8}, # 1400-1919px width  
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
    "block_id",
    "group_ID",
    "session_ID",
    "is_initial",
    "scale_name",
    "scale_value",
    "electrode_model",
    "left_stim_freq",
    "left_cathode",
    "left_anode",
    "left_amplitude",
    "left_pulse_width",
    "right_stim_freq",
    "right_cathode",
    "right_anode",
    "right_amplitude",
    "right_pulse_width",
    "notes",
]

# Timezone configuration
TIMEZONE = "US/Eastern"

# Validation limits
STIMULATION_LIMITS = {
    "frequency": {"min": 10, "max": 200, "step1": 5, "step2": 10},
    "amplitude": {"min": 0.0, "max": 15.0, "decimals": 2, "step1": 1.0, "step2": 0.5},
    "pulse_width": {"min": 10, "max": 200, "step1": 5, "step2": 10},
}

SESSION_SCALE_LIMITS = {
    "min": 0,
    "max": 10,
    "decimals": 2,
    "step1": 1,
    "step2": 0.5,
}

# Clinical scales presets
CLINICAL_SCALES_PRESETS: Dict[str, List[str]] = {
    "OCD": ["YBOCS", "YBOCS-o", "YBOCS-c", "MADRS"],
    "MDD": ["MADRS"],
    "PD": ["UPDRS", "PDQ"],
    "ET": ["FTM"],
}

# Session scales presets (name, min, max)
SESSION_SCALES_PRESETS: Dict[str, List[Tuple[str, str, str]]] = {
    "OCD": [
        ("Mood", "0", "10"),
        ("Anxiety", "0", "10"),
        ("Energy", "0", "10"),
        ("OCD", "0", "10"),
    ],
    "MDD": [
        ("Mood", "0", "10"),
        ("Anxiety", "0", "10"),
        ("Energy", "0", "10"),
        ("Rumination", "0", "10"),
    ],
    "PD": [
        ("Tremor", "0", "10"),
        ("Rigidity", "0", "10"),
    ],
    "ET": [
        ("Tremor", "0", "10"),
        ("Rigidity", "0", "10"),
    ],
}

# Available preset buttons
PRESET_BUTTONS = ["OCD", "MDD", "PD", "ET"]

# UI Style constants
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

# Placeholders
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
