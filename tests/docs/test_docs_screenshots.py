"""Generate UI screenshots for Read the Docs (opt-in via DOCS_SCREENSHOT_DIR).

Run locally and write into ``docs/_static`` (on Windows/macOS uses the native
Qt platform so fonts and window chrome render correctly; do not force
``offscreen`` on desktop)::

    $env:DOCS_SCREENSHOT_DIR="docs/_static"
    uv run pytest tests/docs/test_docs_screenshots.py -m docs_screenshot -q
"""

from __future__ import annotations

import os

import pytest
from PySide6.QtCore import Qt

from dbs_annotator.views.export_dialog import (
    ReportSectionsDialog,
    ScaleTargetValuesDialog,
)
from tests.docs import screenshot_helpers as sh

pytestmark = [pytest.mark.docs_screenshot, pytest.mark.gui]


def _require_out_dir() -> sh.Path:
    if not os.environ.get("DOCS_SCREENSHOT_DIR"):
        pytest.skip("DOCS_SCREENSHOT_DIR is not set; skipping screenshot generation.")
    return sh.screenshot_dir()


@pytest.fixture
def docs_out(tmp_path) -> sh.Path:
    out = _require_out_dir()
    sh.copy_logo(out)
    return out


@pytest.fixture
def docs_tsv(tmp_path) -> sh.Path:
    return sh.make_bids_tsv(tmp_path)


@pytest.mark.timeout(300)
def test_generate_documentation_screenshots(wizard, qtbot, docs_out, docs_tsv) -> None:
    """Walk the main workflows and save PNGs referenced by the Sphinx docs."""
    out = docs_out

    # --- Home / Step 0 (mode selection) ---
    save_wizard = sh.save_wizard
    save_wizard(wizard, out / "home_screen.png")

    from dbs_annotator.utils.theme_manager import Theme

    sh.apply_docs_theme(wizard.app, Theme.DARK)
    wizard._update_theme_button_icon()
    save_wizard(wizard, out / "home_screen_dark.png")
    sh.apply_docs_theme(wizard.app, Theme.LIGHT)
    wizard._update_theme_button_icon()

    # --- Full session workflow ---
    qtbot.mouseClick(wizard.step0_view.full_mode_button, Qt.MouseButton.LeftButton)
    sh.wait_for_render()
    assert wizard.workflow_mode == "full"
    assert wizard.step1_view is not None

    s1 = wizard.step1_view
    sh.setup_step1_file(s1, docs_tsv)
    save_wizard(wizard, out / "step0.png")  # file path visible on Step 1 setup

    sh.apply_pd_clinical_preset(wizard)
    sh.configure_stimulation(s1)
    sh.fill_step1_initial_notes(s1)
    save_wizard(wizard, out / "step1.png")
    sh.save_clinical_scales_settings_dialog(
        wizard, out / "clinical_scales_settings_dialog.png"
    )
    sh.save_electrode_canvas(s1.left_canvas, out / "electrode_diagram.png")
    sh.save_electrode_canvas(s1.left_canvas, out / "electrode-canvas.png")

    qtbot.mouseClick(s1.next_button, Qt.MouseButton.LeftButton)
    sh.wait_for_render()
    assert wizard.current_step == 2 and wizard.step2_view is not None

    sh.apply_pd_session_preset(wizard)
    save_wizard(wizard, out / "step2.png")
    sh.save_session_scales_settings_dialog(
        wizard, out / "session_scales_settings_dialog.png"
    )

    qtbot.mouseClick(wizard.step2_view.next_button, Qt.MouseButton.LeftButton)
    sh.wait_for_render()
    assert wizard.current_step == 3 and wizard.step3_view is not None

    s3 = wizard.step3_view
    save_wizard(wizard, out / "step3.png")

    sh.fill_step3_session_scale_values(s3)
    sh.set_program_group(s3, sh.PROGRAM_NAME)
    s3.session_notes_edit.setPlainText(sh.STEP3_ENTRY_NOTES)
    sh.wait_for_render()
    # Before Insert: notes and scale values stay visible (Insert clears notes).
    save_wizard(wizard, out / "step3_entry_recorded.png")
    qtbot.mouseClick(s3.insert_button, Qt.MouseButton.LeftButton)
    sh.wait_for_render()

    # --- Export dialogs (no file save) ---
    scale_dlg = ScaleTargetValuesDialog(
        sh.pd_session_scales_for_export_dialog(),
        wizard,
        title="Select Scales Target Values",
    )
    sh.configure_scale_optimization_dialog(
        scale_dlg, custom_scale="Paresthesia", custom_value="6"
    )
    sh.save_scale_optimization_dialog(scale_dlg, out / "scale_optimization_dialog.png")

    session_data_children = [
        ("session_data_graph", "Session Data Graph", True),
        ("session_data_table", "Session Data Table", True),
    ]
    session_sections = [
        ("initial_notes", "Initial Clinical Notes", True, None),
        ("session_data", "Session Data", True, session_data_children),
        ("electrode_config", "Electrode Configurations", True, None),
        ("programming_summary", "Programming Summary", True, None),
    ]
    report_dlg = ReportSectionsDialog(session_sections, wizard, title="Report Sections")
    sh.save_dialog(report_dlg, out / "report_sections_dialog.png")

    long_children = [
        ("session_data_graph", "Session Data Graph", True),
        ("session_data_table", "Session Data Table", False),
    ]
    long_sections = [
        ("sessions_overview", "Sessions Overview", True, None),
        ("session_data", "Session Data", False, long_children),
        ("electrode_config", "Electrode Configuration", False, None),
        ("programming_summary", "Programming Summary", False, None),
    ]
    long_report_dlg = ReportSectionsDialog(
        long_sections, wizard, title="Report Sections"
    )
    sh.save_dialog(long_report_dlg, out / "report_sections_dialog_longitudinal.png")

    # --- Longitudinal workflow ---
    wizard.current_step = 0
    wizard.stack.setCurrentWidget(wizard.step0_view)
    qtbot.mouseClick(
        wizard.step0_view.longitudinal_report_button, Qt.MouseButton.LeftButton
    )
    sh.wait_for_render()
    assert wizard.longitudinal_file_view is not None
    long_view = wizard.longitudinal_file_view
    save_wizard(wizard, out / "longitudinal_view.png")

    for path in sh.make_longitudinal_tsv_files(docs_tsv.parent):
        long_view.loaded_files.append(str(path))
    long_view._refresh_file_list()
    sh.wait_for_render()
    save_wizard(wizard, out / "longitudinal_drag_drop.png")

    # --- Free annotations workflow (close programming session file first) ---
    wizard.controller.session_data.close_file()
    wizard.current_step = 0
    wizard.stack.setCurrentWidget(wizard.step0_view)
    qtbot.mouseClick(
        wizard.step0_view.annotations_only_button, Qt.MouseButton.LeftButton
    )
    sh.wait_for_render()
    assert wizard.annotations_file_view is not None

    ann_tsv = sh.make_annotations_tsv(docs_tsv.parent)
    afv = wizard.annotations_file_view
    afv.file_path_edit.setText(str(ann_tsv))
    afv.current_file_mode = "new"
    save_wizard(wizard, out / "annotations_view.png")

    qtbot.mouseClick(afv.next_button, Qt.MouseButton.LeftButton)
    sh.wait_for_render()
    assert wizard.annotations_session_view is not None
    asv = wizard.annotations_session_view
    asv.annotation_edit.setPlainText("Patient more fluent; mild tremor at rest.")
    wizard.controller.insert_simple_annotation(asv)
    sh.wait_for_render()
    save_wizard(wizard, out / "annotations_list.png")
