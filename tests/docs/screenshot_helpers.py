"""Shared helpers for documentation screenshot generation."""

from __future__ import annotations

import os
import shutil
from pathlib import Path

import pandas as pd
from PySide6.QtGui import QColor, QPainter, QPixmap
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication, QLayout, QWidget

from dbs_annotator.config import CLINICAL_SCALES_PRESETS, SESSION_SCALES_PRESETS
from dbs_annotator.config_electrode_models import ELECTRODE_MODELS, ContactState
from dbs_annotator.ui.amplitude_split_widget import (
    AmplitudeSplitWidget,
    get_cathode_labels,
)

_FONT_FALLBACK_CHAIN = (
    "Segoe UI",
    "San Francisco",
    "Helvetica Neue",
    "DejaVu Sans",
    "Liberation Sans",
    "Arial",
)
_QSS_FONT_CHAIN = "'Segoe UI', 'San Francisco', 'Helvetica Neue', 'Arial', sans-serif"
_QSS_FONT_CHAIN_LINUX = (
    "'DejaVu Sans', 'Liberation Sans', 'Helvetica Neue', 'Arial', sans-serif"
)

DOCS_STATIC_DIR = Path("docs/_static")
LOGO_SOURCE = Path("icons/logosimple/logosimple-256.png")

PATIENT_ID = "01"
BIDS_FILENAME = f"sub-{PATIENT_ID}_ses-20250115_task-programming_run-01_events.tsv"

# PD clinical scales (config defaults) with demo scores in [10, 20].
PD_CLINICAL_SCALES = CLINICAL_SCALES_PRESETS["PD"]
PD_CLINICAL_VALUES = [12, 14, 16, 18]

PD_SESSION_SCALES = SESSION_SCALES_PRESETS["PD"]

STIM_FREQ_HZ = "130"
STIM_PULSE_WIDTH_US = "90"
STIM_AMPLITUDE_MA = "2"
SEGMENT_SPLIT = {"E1a": 40.0, "E1b": 60.0}
PROGRAM_NAME = "A"

STEP1_INITIAL_NOTES = (
    "Patient presents with moderate parkinsonian symptoms. "
    "Baseline clinical scales recorded before programming."
)

STEP3_ENTRY_NOTES = (
    "The patient is more fluent at rest with reduced tremor on the left side."
)
# Session-scale slider values in the 0–10 range (matches PD preset in Step 2).
STEP3_SESSION_SCALE_VALUES = [6, 8, 4, 7, 5, 9, 3]


def prepare_qt_for_docs(qapp: QApplication) -> None:
    """Apply the same theme, fonts, and SVG support as the real application."""
    import PySide6.QtSvg  # noqa: F401 - enables SVG icons referenced in QSS
    from PySide6.QtGui import QFont, QFontDatabase

    from dbs_annotator.utils import get_theme_manager
    from dbs_annotator.utils.theme_manager import Theme

    families = set(QFontDatabase.families())
    for name in _FONT_FALLBACK_CHAIN:
        if name in families:
            qapp.setFont(QFont(name, 10))
            break

    theme_manager = get_theme_manager()
    theme = Theme.LIGHT
    try:
        stylesheet = theme_manager.load_stylesheet(theme)
        if "Segoe UI" not in families:
            stylesheet = stylesheet.replace(_QSS_FONT_CHAIN, _QSS_FONT_CHAIN_LINUX)
        qapp.setStyleSheet(stylesheet)
        theme_manager._current_theme = theme  # noqa: SLF001 — match apply_theme side effect
    except FileNotFoundError:
        theme_manager.apply_theme(theme, qapp)

    wait_for_render(150)


def screenshot_dir() -> Path:
    out_dir = os.environ.get("DOCS_SCREENSHOT_DIR", str(DOCS_STATIC_DIR))
    path = Path(out_dir)
    path.mkdir(parents=True, exist_ok=True)
    (path / "videos").mkdir(parents=True, exist_ok=True)
    return path


def wait_for_render(ms: int = 400) -> None:
    QApplication.processEvents()
    QTest.qWait(ms)


def save_pixmap(pixmap: QPixmap, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    assert pixmap.save(str(path)), f"Failed to save screenshot: {path}"


def save_electrode_canvas(
    canvas,
    path: Path,
    *,
    width: int = 420,
    height: int = 760,
    background: str = "#f8fafc",
) -> None:
    """Render electrode state to PNG (same offscreen path as session export).

    ``grab()`` / ``render(QPainter)`` on the live Step 1 widget often yields a
    blank gray image; a detached canvas with a temporary background fill in
    ``paintEvent`` matches ``SessionExporter._render_electrode_png``.
    """
    from dbs_annotator.models.electrode_viewer import ElectrodeCanvas

    model = canvas.model or ELECTRODE_MODELS["Medtronic SenSight B33005"]
    offscreen = ElectrodeCanvas()
    offscreen.set_model(model)
    offscreen.contact_states = dict(canvas.contact_states)
    offscreen.case_state = canvas.case_state
    offscreen.resize(width, height)
    offscreen.set_export_mode(True)
    offscreen.update()

    bg = QColor(background)
    original_paint = offscreen.paintEvent

    def bg_paint(event):
        painter = QPainter(offscreen)
        painter.fillRect(offscreen.rect(), bg)
        original_paint(event)

    offscreen.paintEvent = bg_paint  # type: ignore[assignment]  # ty: ignore[invalid-assignment]

    pixmap = QPixmap(offscreen.size())
    pixmap.fill(bg)
    offscreen.render(pixmap)
    save_pixmap(pixmap, path)


def save_widget(
    widget: QWidget, path: Path, width: int | None = None, height: int | None = None
) -> None:
    if width and height:
        widget.resize(width, height)
    widget.show()
    wait_for_render()
    save_pixmap(widget.grab(), path)


def pd_session_scales_for_export_dialog() -> list[tuple[str, str, str]]:
    """All PD session scales (name, observed min, observed max) for export dialogs."""
    return list(PD_SESSION_SCALES)


def configure_scale_optimization_dialog(
    dlg: QWidget,
    *,
    custom_scale: str = "Paresthesia",
    custom_value: str = "6",
) -> None:
    """Select Custom target on one scale (e.g. Paresthesia → 6) for doc screenshots."""
    rows = getattr(dlg, "_rows", [])
    for name, _min_v, _max_v, _checkbox, group, custom_edit, _ in rows:
        if name == custom_scale:
            custom_btn = group.button(2)
            if custom_btn is not None:
                custom_btn.setChecked(True)
            custom_edit.setVisible(True)
            custom_edit.setText(custom_value)
            break
    wait_for_render(100)


def save_scale_optimization_dialog(dlg: QWidget, path: Path) -> None:
    """Capture scale optimization dialog tall enough to show every session scale row."""
    layout = dlg.layout()
    if layout is not None:
        layout.setSizeConstraint(QLayout.SizeConstraint.SetFixedSize)
    row_count = len(getattr(dlg, "_rows", []))
    width = max(int(getattr(dlg, "minimumWidth", lambda: 720)()), 720)
    height = 130 + row_count * 46 + 72
    dlg.setFixedSize(width, height)
    dlg.show()
    wait_for_render()
    save_pixmap(dlg.grab(), path)


def save_dialog(dlg: QWidget, path: Path, *, min_width: int = 340) -> None:
    """Capture a dialog at its natural size (avoids extra empty vertical space)."""
    layout = dlg.layout()
    if layout is not None:
        layout.setSizeConstraint(QLayout.SizeConstraint.SetFixedSize)
    dlg.setMinimumWidth(min_width)
    dlg.setMaximumSize(16777215, 16777215)  # reset any prior max from test resizes
    dlg.adjustSize()
    hint = dlg.sizeHint()
    dlg.setFixedSize(max(hint.width(), min_width), hint.height())
    dlg.show()
    wait_for_render()
    save_pixmap(dlg.grab(), path)


def save_wizard(
    wizard: QWidget, path: Path, width: int = 1400, height: int = 900
) -> None:
    """Capture the window; use screen grab for native frame when possible."""
    wizard.resize(width, height)
    wizard.show()
    wizard.raise_()
    wizard.activateWindow()
    wait_for_render(500)

    pixmap = None
    win_id = wizard.winId()
    if win_id:
        screen = QApplication.primaryScreen()
        if screen is not None:
            try:
                grabbed = screen.grabWindow(int(win_id))
                if not grabbed.isNull():
                    pixmap = grabbed
            except (TypeError, ValueError):
                pass

    if pixmap is None or pixmap.isNull():
        pixmap = wizard.grab()

    save_pixmap(pixmap, path)


def copy_logo(out_dir: Path) -> None:
    if LOGO_SOURCE.is_file():
        shutil.copy2(LOGO_SOURCE, out_dir / "logo.png")


def make_bids_tsv(tmp_path: Path) -> Path:
    path = tmp_path / BIDS_FILENAME
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("", encoding="utf-8")
    return path


def make_longitudinal_tsv_files(tmp_path: Path) -> list[Path]:
    """Two sub-01 session files with PD session-scale rows for longitudinal UI."""
    rows_template = [
        {
            "date": "2025-01-10",
            "time": "09:00:00",
            "block_ID": "1",
            "is_initial": "1",
            "scale_name": name,
            "scale_value": str(val),
            "notes": "baseline",
        }
        for name, val in zip(PD_CLINICAL_SCALES, PD_CLINICAL_VALUES, strict=True)
    ]
    session_row = {
        "date": "2025-01-10",
        "time": "10:00:00",
        "block_ID": "2",
        "is_initial": "0",
        "scale_name": "Tremor",
        "scale_value": "15",
        "left_stim_freq": STIM_FREQ_HZ,
        "left_pulse_width": STIM_PULSE_WIDTH_US,
        "left_amplitude": STIM_AMPLITUDE_MA,
        "notes": "config 1",
    }
    paths: list[Path] = []
    for run in ("01", "02"):
        rows = [*rows_template, {**session_row, "block_ID": "2"}]
        p = (
            tmp_path
            / f"sub-{PATIENT_ID}_ses-202501{run}_task-programming_run-{run}_events.tsv"
        )
        pd.DataFrame(rows).to_csv(p, sep="\t", index=False)
        paths.append(p)
    return paths


def make_annotations_tsv(tmp_path: Path) -> Path:
    """Return path for a new annotations file (created when the wizard validates)."""
    return tmp_path / f"sub-{PATIENT_ID}_ses-20250115_task-notes_run-01_events.tsv"


def fill_clinical_scale_values(step1, values: list[int] | None = None) -> None:
    values = values or PD_CLINICAL_VALUES
    for idx, (_, score_edit, _) in enumerate(step1.clinical_scales_rows):
        if idx < len(values):
            score_edit.setText(str(values[idx]))


def configure_stimulation(step1) -> None:
    """Default stim parameters + left E1a/E1b (40/60 %) + right E2 cathode."""
    left = step1.left_canvas
    right = step1.right_canvas
    left.contact_states.clear()
    right.contact_states.clear()
    left.case_state = ContactState.ANODIC
    right.case_state = ContactState.ANODIC
    left.contact_states[(1, 0)] = ContactState.CATHODIC
    left.contact_states[(1, 1)] = ContactState.CATHODIC
    right.contact_states[(2, 0)] = ContactState.CATHODIC
    left.update()
    right.update()

    step1.left_stim_freq_edit.setText(STIM_FREQ_HZ)
    step1.right_stim_freq_edit.setText(STIM_FREQ_HZ)
    step1.left_pw_edit.setText(STIM_PULSE_WIDTH_US)
    step1.right_pw_edit.setText(STIM_PULSE_WIDTH_US)
    step1.right_amp_edit.setText(STIM_AMPLITUDE_MA)
    step1.left_amp_edit.setText(STIM_AMPLITUDE_MA)
    set_program_group(step1, PROGRAM_NAME)

    step1.update_configuration_display()
    wait_for_render(100)

    left_labels = get_cathode_labels(left)
    right_labels = get_cathode_labels(right)
    step1.left_amp_split.update_cathodes(
        left_labels,
        step1._is_single_grouped_directional(left_labels, left),
    )
    step1.right_amp_split.update_cathodes(
        right_labels,
        step1._is_single_grouped_directional(right_labels, right),
    )
    set_amplitude_split_percentages(step1.left_amp_split, SEGMENT_SPLIT)


def set_amplitude_split_percentages(
    amp_split: AmplitudeSplitWidget, percentages: dict[str, float]
) -> None:
    amp_split._percentages.update(percentages)
    amp_split._rebuild_rows()
    amp_split._refresh_ma_values()
    wait_for_render(100)


def set_program_group(view, program: str = PROGRAM_NAME) -> None:
    combo = getattr(view, "group_combo", None)
    if combo is None:
        return
    idx = combo.findText(program)
    if idx >= 0:
        combo.setCurrentIndex(idx)


def fill_step1_initial_notes(step1, text: str | None = None) -> None:
    if hasattr(step1, "notes_edit"):
        step1.notes_edit.setPlainText(text or STEP1_INITIAL_NOTES)


def fill_step3_session_scale_values(
    step3,
    values: list[float] | None = None,
) -> None:
    """Set session scale sliders to 0–10 with visible green fill (theme QSS)."""
    values = list(values or STEP3_SESSION_SCALE_VALUES)
    for idx, (_name, widget) in enumerate(step3.session_scale_value_edits):
        val = max(0.0, min(10.0, float(values[idx % len(values)])))
        internal = int(round(val * 4))
        bar = widget.progress_bar
        bar.blockSignals(True)
        widget._value = internal
        bar.setMinimum(widget._minimum)
        bar.setMaximum(widget._maximum)
        bar.setValue(internal)
        bar.setFormat(f"{val:.2f}")
        bar.blockSignals(False)
        widget.style().unpolish(bar)
        widget.style().polish(bar)
    wait_for_render(150)


def setup_step1_file(step1, tsv_path: Path) -> None:
    step1.file_path_edit.setText(str(tsv_path))
    step1.current_file_mode = "new"
    step1.bids_patient_id = PATIENT_ID


def apply_pd_clinical_preset(wizard) -> None:
    wizard.controller.apply_clinical_preset("PD", wizard.step1_view)
    fill_clinical_scale_values(wizard.step1_view)


def apply_pd_session_preset(wizard) -> None:
    wizard.controller.apply_session_preset("PD", wizard.step2_view)
