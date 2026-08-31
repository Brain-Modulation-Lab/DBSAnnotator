"""Shared helpers for documentation screenshot generation."""

from __future__ import annotations

import os
import shutil
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from dbs_annotator.views.wizard_window import WizardWindow

import pandas as pd
from PySide6.QtCore import Qt
from PySide6.QtGui import QColor, QPainter, QPixmap
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication, QDialog, QLayout, QWidget

from dbs_annotator.config import CLINICAL_SCALES_PRESETS, SESSION_SCALES_PRESETS
from dbs_annotator.config_electrode_models import ELECTRODE_MODELS, ContactState
from dbs_annotator.ui.amplitude_split_widget import (
    AmplitudeSplitWidget,
    get_cathode_labels,
)
from dbs_annotator.utils.theme_manager import Theme

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
# Qt PNG quality: compression 0 (largest) .. 9 (smallest); 2 = high fidelity.
PNG_SAVE_COMPRESSION = 2
ELECTRODE_SCREENSHOT_SCALE = 2

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

# Wizard PNGs: 65% of the app's normal step geometry (matches RTD screenshot cap).
WIZARD_SCREENSHOT_SIZE_RATIO = 0.65
WIZARD_SCREENSHOT_MIN_WIDTH = 520
WIZARD_SCREENSHOT_MIN_HEIGHT = 320


def apply_docs_theme(qapp: QApplication, theme: Theme) -> None:
    """Apply light/dark QSS and fonts for documentation screenshots."""
    import PySide6.QtSvg  # noqa: F401 - enables SVG icons referenced in QSS
    from PySide6.QtGui import QFont, QFontDatabase

    from dbs_annotator.utils import get_theme_manager

    families = set(QFontDatabase.families())
    for name in _FONT_FALLBACK_CHAIN:
        if name in families:
            qapp.setFont(QFont(name, 10))
            break

    theme_manager = get_theme_manager()
    try:
        stylesheet = theme_manager.load_stylesheet(theme)
        if "Segoe UI" not in families:
            stylesheet = stylesheet.replace(_QSS_FONT_CHAIN, _QSS_FONT_CHAIN_LINUX)
        qapp.setStyleSheet(stylesheet)
        theme_manager._current_theme = theme  # noqa: SLF001 — match apply_theme side effect
    except FileNotFoundError:
        theme_manager.apply_theme(theme, qapp)

    wait_for_render(150)


def prepare_qt_for_docs(qapp: QApplication) -> None:
    """Apply the same theme, fonts, and SVG support as the real application."""
    apply_docs_theme(qapp, Theme.LIGHT)


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
    # Runtime PySide6 on Windows accepts str format + positional quality; bytes fail.
    ok = pixmap.save(str(path), "PNG", PNG_SAVE_COMPRESSION)
    assert ok, f"Failed to save screenshot: {path}"


def _crop_grab_to_widget(widget: QWidget, pixmap: QPixmap) -> QPixmap:
    """Trim ``grabWindow`` over-capture (frame/shadow) to the widget client area."""
    dpr = widget.devicePixelRatioF()
    target_w = max(1, int(widget.width() * dpr))
    target_h = max(1, int(widget.height() * dpr))
    if pixmap.width() <= target_w and pixmap.height() <= target_h:
        return pixmap
    w = min(pixmap.width(), target_w)
    h = min(pixmap.height(), target_h)
    return pixmap.copy(0, 0, w, h)


def grab_window_pixmap(widget: QWidget) -> QPixmap:
    """Capture a top-level window/dialog at native resolution (incl. HiDPI)."""
    widget.show()
    widget.raise_()
    widget.activateWindow()
    wait_for_render(500)

    win_id = widget.winId()
    if win_id:
        screen = QApplication.primaryScreen()
        if screen is not None:
            try:
                grabbed = screen.grabWindow(int(win_id))
                if not grabbed.isNull():
                    return _crop_grab_to_widget(widget, grabbed)
            except (TypeError, ValueError):
                pass

    return widget.grab()


def grab_widget_pixmap(widget: QWidget) -> QPixmap:
    """Capture a dialog or modal at native resolution."""
    return grab_window_pixmap(widget)


def _crop_pixmap_to_content(
    pixmap: QPixmap,
    background: QColor,
    *,
    margin: int = 20,
    margin_left: int | None = None,
) -> QPixmap:
    """Trim uniform background borders (same idea as session export)."""
    image = pixmap.toImage()
    bg_rgb = background.rgb()
    left, top, right, bottom = image.width(), image.height(), 0, 0
    for y in range(image.height()):
        for x in range(image.width()):
            if image.pixel(x, y) != bg_rgb:
                left = min(left, x)
                top = min(top, y)
                right = max(right, x)
                bottom = max(bottom, y)
    if right <= left or bottom <= top:
        return pixmap
    ml = margin if margin_left is None else margin_left
    left = max(0, left - ml)
    top = max(0, top - margin)
    right = min(image.width() - 1, right + margin)
    bottom = min(image.height() - 1, bottom + margin)
    return pixmap.copy(left, top, right - left + 1, bottom - top + 1)


def save_electrode_canvas(
    canvas,
    path: Path,
    *,
    width: int = 440 * ELECTRODE_SCREENSHOT_SCALE,
    height: int = 900 * ELECTRODE_SCREENSHOT_SCALE,
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
    pixmap = _crop_pixmap_to_content(pixmap, bg, margin=20, margin_left=16)
    save_pixmap(pixmap, path)


def save_widget(
    widget: QWidget, path: Path, width: int | None = None, height: int | None = None
) -> None:
    if width and height:
        widget.resize(width, height)
    save_pixmap(grab_window_pixmap(widget), path)


def pd_session_scales_for_export_dialog() -> list[tuple[str, str, str]]:
    """All PD session scales (name, observed min, observed max) for export dialogs.

    PD_SESSION_SCALES rows carry a 4th optimization-mode cell; drop it here so
    the export dialogs get the (name, min, max) triples they expect.
    """
    return [(row[0], row[1], row[2]) for row in PD_SESSION_SCALES]


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
    save_pixmap(grab_window_pixmap(dlg), path)


def _select_list_preset(dlg: QDialog, preset_name: str) -> None:
    """Select a preset row in settings dialogs (Clinical / Session Scales)."""
    presets_list = getattr(dlg, "presets_list", None)
    if presets_list is None:
        return
    for row in range(presets_list.count()):
        item = presets_list.item(row)
        if item is not None and item.data(Qt.ItemDataRole.UserRole) == preset_name:
            presets_list.setCurrentRow(row)
            return


def save_clinical_scales_settings_dialog(wizard, path: Path) -> None:
    """Clinical Scales Settings — same size and PD selection as the live dialog."""
    from dbs_annotator.config import PRESET_BUTTONS
    from dbs_annotator.ui.clinical_scales_settings_dialog import (
        ClinicalScalesSettingsDialog,
    )

    wizard.show()
    wizard.raise_()
    s1 = wizard.step1_view
    dlg = ClinicalScalesSettingsDialog(s1.clinical_presets, wizard, PRESET_BUTTONS)
    dlg.resize(500, 400)
    _select_list_preset(dlg, "PD")
    save_pixmap(grab_widget_pixmap(dlg), path)


def save_session_scales_settings_dialog(wizard, path: Path) -> None:
    """Session Scales Settings — draft new preset (not saved), native dialog size."""
    from dbs_annotator.config import PRESET_BUTTONS
    from dbs_annotator.ui.session_scales_settings_dialog import (
        SessionScalesSettingsDialog,
    )

    wizard.show()
    wizard.raise_()
    s2 = wizard.step2_view
    dlg = SessionScalesSettingsDialog(s2.session_presets, wizard, PRESET_BUTTONS)
    dlg.resize(520, 420)
    dlg._clear_selection()
    dlg.preset_name_edit.setText("MyPreset")
    dlg.scales_edit.setText("Mood:0-10, Anxiety:0-10, CustomScale:0-5")
    save_pixmap(grab_widget_pixmap(dlg), path)


def save_setting_presets_dialog(wizard, path: Path) -> None:
    """Edit Setting Presets — Frequencies tab with a row selected."""
    wizard.show()
    wizard.raise_()
    s1 = wizard.step1_view
    dlg, tabs, freq_list, _amp_list, _pw_list = s1._build_setting_presets_dialog(wizard)
    tabs.setCurrentIndex(0)
    freq_list.setCurrentRow(2)
    dlg.resize(480, 380)
    save_pixmap(grab_widget_pixmap(dlg), path)


def save_program_names_settings_dialog(wizard, path: Path) -> None:
    """Edit Program Names — demo custom names with a new name being drafted."""
    wizard.show()
    wizard.raise_()
    s1 = wizard.step1_view
    dlg, list_widget, new_program_edit, _program_config = (
        s1._build_program_names_dialog(wizard)
    )
    list_widget.clear()
    list_widget.addItems(["Morning", "Afternoon"])
    list_widget.setCurrentRow(0)
    new_program_edit.setText("Evening")
    dlg.resize(420, 340)
    save_pixmap(grab_widget_pixmap(dlg), path)


def save_help_dialog(wizard: WizardWindow, path: Path) -> None:
    """Capture the Help / About dialog at the app's normal size."""
    wizard.show()
    wizard.raise_()
    dlg = wizard._build_info_dialog()
    dlg.resize(640, max(dlg.sizeHint().height(), 520))
    save_pixmap(grab_widget_pixmap(dlg), path)


def _demo_release_info():
    from dbs_annotator.config import APP_REPOSITORY_URL
    from dbs_annotator.utils.updater import ReleaseInfo

    return ReleaseInfo(
        version="0.5.0",
        tag_name="v0.5.0",
        html_url=f"{APP_REPOSITORY_URL}/releases/tag/v0.5.0",
        published_at="2025-06-01T12:00:00Z",
        body=(
            "Documentation screenshot example.\n"
            "- Improved report export layout\n"
            "- Updated Help dialog and update notifications"
        ),
        is_prerelease=False,
    )


def save_update_available_dialog(wizard: WizardWindow, path: Path) -> None:
    """Capture the update-available message box."""
    wizard.show()
    wizard.raise_()
    box = wizard._build_update_available_message_box(_demo_release_info())
    save_dialog(box, path, min_width=460)


def save_release_notes_dialog(wizard: WizardWindow, path: Path) -> None:
    """Capture the release-notes dialog opened from an update notification."""
    wizard.show()
    wizard.raise_()
    dlg = wizard._build_release_notes_dialog(_demo_release_info())
    dlg.resize(560, max(dlg.sizeHint().height(), 400))
    save_pixmap(grab_widget_pixmap(dlg), path)


def save_dialog(
    dlg: QWidget,
    path: Path,
    *,
    min_width: int = 340,
) -> None:
    """Capture a dialog at its natural size (avoids extra empty vertical space)."""
    layout = dlg.layout()
    if layout is not None:
        layout.setSizeConstraint(QLayout.SizeConstraint.SetFixedSize)
    if min_width > 0:
        dlg.setMinimumWidth(min_width)
    dlg.setMaximumSize(16777215, 16777215)  # reset any prior max from test resizes
    dlg.adjustSize()
    hint = dlg.sizeHint()
    dlg.resize(max(hint.width(), min_width), hint.height())
    save_pixmap(grab_widget_pixmap(dlg), path)


def _apply_wizard_screenshot_geometry(
    wizard: WizardWindow,
    *,
    size_ratio: float = WIZARD_SCREENSHOT_SIZE_RATIO,
) -> None:
    """Resize wizard to app step geometry, then scale down for balanced RTD captures."""
    if wizard.current_step == 0:
        wizard._update_window_size_for_step0()
    else:
        wizard._update_window_size_for_main_workflow()
    wait_for_render(200)

    if size_ratio >= 1.0:
        return

    wizard._release_stack_size_constraints()
    geo = wizard.geometry()
    width = max(int(geo.width() * size_ratio), WIZARD_SCREENSHOT_MIN_WIDTH)
    height = max(int(geo.height() * size_ratio), WIZARD_SCREENSHOT_MIN_HEIGHT)

    screen = wizard.app.primaryScreen()
    if screen is not None:
        rect = screen.availableGeometry()
        width = min(width, max(WIZARD_SCREENSHOT_MIN_WIDTH, rect.width() - 40))
        height = min(height, max(WIZARD_SCREENSHOT_MIN_HEIGHT, rect.height() - 40))
        x = int((rect.width() - width) / 2)
        y = int((rect.height() - height) / 2)
    else:
        x, y = geo.x(), geo.y()

    wizard.setMinimumSize(1, 1)
    wizard.setMaximumSize(16777215, 16777215)
    wizard.setGeometry(x, y, width, height)
    wait_for_render(300)


def save_wizard(wizard: WizardWindow, path: Path) -> None:
    """Capture the wizard at 65% of the app's normal step size (step 0 compact)."""
    _apply_wizard_screenshot_geometry(wizard)
    save_pixmap(grab_window_pixmap(wizard), path)


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
