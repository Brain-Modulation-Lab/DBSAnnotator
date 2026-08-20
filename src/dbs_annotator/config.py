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

# Publisher (UI, About, docs). Not used for on-disk paths.
ORGANIZATION_PUBLISHER = "Wyss Center for Bio and Neuroengineering"

# Copyright holders shown in Help, documentation, and license notices.
COPYRIGHT_HOLDERS = (
    "Wyss Center for Bio and Neuroengineering, "
    "Massachusetts General Hospital, "
    "and Charité Universitätsmedizin Berlin"
)

# SPDX-style license name (see LICENSE in the repository root).
APP_LICENSE_NAME = "MIT License"

# Lead author (About; list same person first in package metadata).
APP_LEAD_AUTHOR = "Lucia Poma"
APP_MAINTAINER = "Richard Köhler"

# Qt application identity for :func:`QStandardPaths` and :class:`QSettings`.
# Use ASCII without spaces so per-user directories never contain spaces
# (``%LOCALAPPDATA%\\<org>\\<app>\\``, Application Support on macOS, etc.).
FS_ORG_NAME = "WyssGeneva"
FS_APP_NAME = "DBSAnnotator"

# Canonical upstream (releases + issue tracker; keep aligned with updater repo slug).
APP_REPOSITORY_URL = "https://github.com/Brain-Modulation-Lab/DBSAnnotator"
APP_ISSUES_URL = f"{APP_REPOSITORY_URL}/issues"


def github_repository_slug(repository_url: str) -> str:
    """Return ``owner/repo`` from a ``https://github.com/owner/repo`` URL."""
    prefix = "https://github.com/"
    if not repository_url.startswith(prefix):
        raise ValueError(
            f"Expected a GitHub repository URL starting with {prefix!r}, "
            f"got {repository_url!r}"
        )
    rest = repository_url.removeprefix(prefix).strip("/")
    owner, sep, repo = rest.partition("/")
    if not sep or not owner or not repo:
        raise ValueError(
            f"Could not parse owner/repo from GitHub URL {repository_url!r}"
        )
    return f"{owner}/{repo.split('/')[0]}"


# GitHub Releases API slug for :mod:`dbs_annotator.utils.updater`.
RELEASES_GITHUB_REPO = github_repository_slug(APP_REPOSITORY_URL)
# Primary contact for feedback (same person as APP_LEAD_AUTHOR).
UPDATE_FEEDBACK_EMAIL = "lucia.poma@wysscenter.ch"

# File paths (relative to executable)
ICON_FILENAME = "logosimple.png"
ICO_FILENAME = "logosimple.ico"
STYLE_FILENAME = "style.qss"
ICONS_DIR = "icons/logosimple"

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
    "width": 1000,
    "height": 700,
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
    "block_ID",
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
    "notes",
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

# Session scale presets: (name, min, max, optimization_mode).
#
# `optimization_mode` is the default direction the report's block ranking uses
# for this scale, and is one of "min" (lower is better), "max" (higher is
# better), "custom" (closest to a target value) or "ignore" (excluded).
# It seeds the export dialog's radio buttons and is carried to the tablet app
# through schema/scale_presets.json, so both apps rank blocks identically.
#
# Note that "custom" is only half-specifiable here: this table has no field for
# the target value, so a "custom" default preselects the Custom button and still
# needs the number typed in at export time. Prefer "min"/"max" for defaults.
#
# Every entry is "min" here, which is exactly what the export dialog defaulted
# to before this field existed — adding it changes no behaviour.
#
# CLINICAL REVIEW NEEDED: several of these are almost certainly the wrong
# direction. "Mood", "Energy" and "Control over tics" are worded so that a
# HIGHER rating is a better outcome, and "Gait / balance" is ambiguous (it
# depends on whether the rater scores impairment or ability). Ranking them as
# "min" tells the report that lower mood is an improvement. Flip them to "max"
# once the intended rating direction is confirmed.
SESSION_SCALES_PRESETS: dict[str, list[tuple[str, str, str, str]]] = {
    "OCD": [
        ("Obsessions", "0", "10", "min"),
        ("Compulsions", "0", "10", "min"),
        ("Anxiety", "0", "10", "min"),
        ("Mood", "0", "10", "min"),  # review: likely "max"
        ("Energy", "0", "10", "min"),  # review: likely "max"
    ],
    "MDD": [
        ("Rumination", "0", "10", "min"),
        ("Anxiety", "0", "10", "min"),
        ("Mood", "0", "10", "min"),  # review: likely "max"
        ("Energy", "0", "10", "min"),  # review: likely "max"
    ],
    "PD": [
        ("Tremor", "0", "10", "min"),
        ("Rigidity", "0", "10", "min"),
        ("Bradykinesia", "0", "10", "min"),
        ("Dyskinesia", "0", "10", "min"),
        ("Gait / balance", "0", "10", "min"),  # review: ambiguous wording
        ("Paresthesia", "0", "10", "min"),
        ("Speech difficulty", "0", "10", "min"),
    ],
    "ET": [
        ("Action tremor", "0", "10", "min"),
        ("Resting tremor", "0", "10", "min"),
        ("Paresthesia", "0", "10", "min"),
        ("Speech difficulty", "0", "10", "min"),
    ],
    "Dystonia": [
        ("Muscle contractions", "0", "10", "min"),
        ("Abnormal posture", "0", "10", "min"),
        ("Pain", "0", "10", "min"),
    ],
    "TS": [
        ("Tic severity", "0", "10", "min"),
        ("Premonitory urge", "0", "10", "min"),
        ("Control over tics", "0", "10", "min"),  # review: likely "max"
        ("Anxiety", "0", "10", "min"),
        ("Impulsivity", "0", "10", "min"),
    ],
}

# Fallback when a preset row predates the optimization_mode field.
DEFAULT_SCALE_OPTIMIZATION_MODE = "min"

SCALE_OPTIMIZATION_MODES = ("min", "max", "custom", "ignore")


def normalize_session_scale_row(row) -> tuple[str, str, str, str]:
    """Coerce a session-scale preset row to ``(name, min, max, mode)``.

    Accepts the legacy 3-element ``(name, min, max)`` form — used by rows that
    come from the Step-2 UI and by user preset files written before the mode
    field existed — and fills in
    :data:`DEFAULT_SCALE_OPTIMIZATION_MODE`. Unknown mode strings also fall back
    to the default rather than propagating into the ranking.
    """
    cells = list(row)
    name = str(cells[0]) if cells else ""
    minimum = str(cells[1]) if len(cells) > 1 else "0"
    maximum = str(cells[2]) if len(cells) > 2 else "10"
    mode = str(cells[3]).strip().lower() if len(cells) > 3 else ""
    if mode not in SCALE_OPTIMIZATION_MODES:
        mode = DEFAULT_SCALE_OPTIMIZATION_MODE
    return name, minimum, maximum, mode


def session_scale_modes() -> dict[str, str]:
    """Map lowercased scale name -> default optimization mode.

    Flattened across every disease preset so the export dialog can seed a
    scale's mode by name, without the mode having to survive a round trip
    through the Step-2 widgets (which only carry name/min/max).

    A name appearing in several presets keeps the first mode encountered; the
    presets agree today, and a conflict would mean the same scale is meant to
    be optimised in opposite directions, which needs a clinical decision rather
    than a silent winner.
    """
    modes: dict[str, str] = {}
    for rows in SESSION_SCALES_PRESETS.values():
        for row in rows:
            name, _, _, mode = normalize_session_scale_row(row)
            modes.setdefault(name.strip().lower(), mode)
    return modes


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
