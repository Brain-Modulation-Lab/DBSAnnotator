"""
Wizard controller for managing the application flow and business logic.

This module contains the main controller that coordinates between the
views and models, handling user interactions and data flow.
"""

from typing import List, Optional, Tuple

from PyQt5.QtWidgets import QMessageBox

from ..config import (
    CLINICAL_SCALES_PRESETS,
    SESSION_SCALES_PRESETS,
)
from ..models import ClinicalScale, SessionData, SessionScale, StimulationParameters
from ..config_electrode_models import ELECTRODE_MODELS
from ..utils import animate_button


class WizardController:
    """
    Main controller for the wizard application.

    This controller manages:
    - Navigation between wizard steps
    - Clinical and session scale management
    - Data persistence through SessionData model
    - Preset application
    - User interaction handling
    """

    def __init__(self):
        """Initialize the wizard controller."""
        self.session_data = SessionData()
        self.current_stimulation = StimulationParameters()
        self.current_group: str = ""
        self.current_electrode_model_name: str = ""
        self.session_scales_names: List[str] = []
        self.session_scales_data: List[Tuple[str, str, str]] = []
        # Scale optimization preferences: (name, min, max, mode, custom_value)
        # mode: "low", "high", "custom", "ignore"
        self.scale_optimization_prefs: List[Tuple[str, str, str, str, str]] = []
        self.workflow_mode: Optional[str] = None  # "full" or "annotations_only"
        self._session_exporter = None  # Lazy-loaded SessionExporter

    @property
    def session_exporter(self):
        """Lazy-load SessionExporter to avoid heavy imports at startup."""
        if self._session_exporter is None:
            from ..utils.session_exporter import SessionExporter
            self._session_exporter = SessionExporter(self.session_data)
        return self._session_exporter

    def apply_clinical_preset(self, preset_name: str, view) -> None:
        """
        Apply a clinical scales preset.

        Args:
            preset_name: Name of the preset (e.g., "OCD", "MDD")
            view: The Step1View instance to update
        """
        preset = CLINICAL_SCALES_PRESETS.get(preset_name, [])
        view.update_clinical_scales(
            preset,
            on_add_callback=lambda: self.on_add_clinical_scale(view),
            on_remove_callback=lambda row: self.on_remove_clinical_scale(view, row),
        )

    def apply_session_preset(self, preset_name: str, view) -> None:
        """
        Apply a session scales preset.

        Args:
            preset_name: Name of the preset (e.g., "OCD", "MDD")
            view: The Step2View instance to update
        """
        preset = []
        if hasattr(view, "session_presets"):
            try:
                preset = view.session_presets.get(preset_name, [])
            except Exception:
                preset = []
        if not preset:
            preset = SESSION_SCALES_PRESETS.get(preset_name, [])
        view.update_session_scales(
            preset,
            on_add_callback=lambda: self.on_add_session_scale(view),
            on_remove_callback=lambda row: self.on_remove_session_scale(view, row),
        )

    def on_add_clinical_scale(self, view) -> None:
        """
        Handle add button click for clinical scales.

        Args:
            view: The Step1View instance
        """
        # Collect current scales (excluding last empty row)
        preset_scales = [
            r[0].text() for r in view.clinical_scales_rows[:-1] if r[0].text()
        ]

        # Check if last row has text to add
        last_row = view.clinical_scales_rows[-1]
        if last_row[0].text():
            preset_scales.append(last_row[0].text())

        view.update_clinical_scales(
            preset_scales,
            on_add_callback=lambda: self.on_add_clinical_scale(view),
            on_remove_callback=lambda row: self.on_remove_clinical_scale(view, row),
        )

    def on_remove_clinical_scale(self, view, layout) -> None:
        """
        Handle remove button click for clinical scales.

        Args:
            view: The Step1View instance
            layout: The layout to remove
        """
        preset_scales = []
        for name_edit, _, row_layout in view.clinical_scales_rows[:-1]:
            if row_layout != layout:
                preset_scales.append(name_edit.text())

        view.update_clinical_scales(
            preset_scales,
            on_add_callback=lambda: self.on_add_clinical_scale(view),
            on_remove_callback=lambda row: self.on_remove_clinical_scale(view, row),
        )

    def on_add_session_scale(self, view) -> None:
        """
        Handle add button click for session scales.

        Args:
            view: The Step2View instance
        """
        preset_scales = []

        # Collect current scales (excluding last empty row)
        for name_edit, scale1_edit, scale2_edit, _ in view.session_scales_rows[:-1]:
            name = name_edit.text()
            minval = scale1_edit.text()
            maxval = scale2_edit.text()
            if name:
                preset_scales.append((name, minval, maxval))

        # Check if last row has text to add
        last_row = view.session_scales_rows[-1]
        if last_row[0].text():
            name = last_row[0].text()
            minval = last_row[1].text()
            maxval = last_row[2].text()
            preset_scales.append((name, minval, maxval))

        view.update_session_scales(
            preset_scales,
            on_add_callback=lambda: self.on_add_session_scale(view),
            on_remove_callback=lambda row: self.on_remove_session_scale(view, row),
        )

    def on_remove_session_scale(self, view, layout) -> None:
        """
        Handle remove button click for session scales.

        Args:
            view: The Step2View instance
            layout: The layout to remove
        """
        preset_scales = []
        for name_edit, scale1_edit, scale2_edit, row_layout in view.session_scales_rows[
            :-1
        ]:
            if row_layout != layout:
                name = name_edit.text()
                minval = scale1_edit.text()
                maxval = scale2_edit.text()
                if name:
                    preset_scales.append((name, minval, maxval))

        view.update_session_scales(
            preset_scales,
            on_add_callback=lambda: self.on_add_session_scale(view),
            on_remove_callback=lambda row: self.on_remove_session_scale(view, row),
        )

    def validate_step1(self, view, parent) -> bool:
        """
        Validate Step 1 and proceed to Step 2.

        Args:
            view: The Step1View instance
            parent: The parent widget for dialogs

        Returns:
            True if validation passes, False otherwise
        """
        file_path = view.file_path_edit.text().strip()
        if not file_path:
            QMessageBox.warning(
                parent, "Missing file", "Please select a file path to save."
            )
            return False

        # Open the session data file if not already open
        if not self.session_data.is_file_open():
            if getattr(view, "current_file_mode", None) == "existing":
                start_block_id = getattr(view, "next_block_id", None)
                self.session_data.open_file_append(file_path, start_block_id=start_block_id)
            else:
                self.session_data.open_file(file_path)

        # Collect clinical scales
        clinical_scales = []
        for name_edit, score_edit, _ in view.clinical_scales_rows:
            name = name_edit.text().strip()
            score = score_edit.text().strip()
            if name:
                clinical_scales.append(ClinicalScale(name=name, value=score))

        # Collect stimulation parameters
        stimulation = StimulationParameters(
            left_frequency=view.left_stim_freq_edit.text(),
            left_cathode=view.get_left_cathode_text(),
            left_anode=view.get_left_anode_text(),
            left_amplitude=view.left_amp_edit.text(),
            left_pulse_width=view.left_pw_edit.text(),
            right_frequency=view.right_stim_freq_edit.text(),
            right_cathode=view.get_right_cathode_text(),
            right_anode=view.get_right_anode_text(),
            right_amplitude=view.right_amp_edit.text(),
            right_pulse_width=view.right_pw_edit.text(),
        )

        notes = view.notes_edit.toPlainText()
        group = view.group_combo.currentText() if hasattr(view, "group_combo") else ""

        electrode_model = view.model_combo.currentText() if hasattr(view, "model_combo") else ""
        self.session_data.write_clinical_scales(
            clinical_scales,
            stimulation,
            group=group,
            electrode_model=electrode_model,
            notes=notes,
        )

        # Store stimulation for next step
        self.current_stimulation = stimulation
        self.current_group = group
        self.current_electrode_model_name = view.model_combo.currentText() if hasattr(view, "model_combo") else ""

        return True

    def prepare_step2(self, view) -> None:
        """
        Prepare Step 2 view with preset buttons connected.

        Args:
            view: The Step2View instance
        """
        # Initialize with empty scale
        view.update_session_scales(
            [],
            on_add_callback=lambda: self.on_add_session_scale(view),
            on_remove_callback=lambda row: self.on_remove_session_scale(view, row),
        )

    def validate_step2(self, view) -> bool:
        """
        Validate Step 2 and collect session scale names.

        Args:
            view: The Step2View instance

        Returns:
            Always True (no validation required)
        """
        # Collect session scale names and data
        self.session_scales_names = []
        self.session_scales_data = []
        for row_data in view.session_scales_rows:
            name_edit, min_edit, max_edit = row_data[0], row_data[1], row_data[2]
            name = name_edit.text().strip()
            min_val = min_edit.text().strip()
            max_val = max_edit.text().strip()
            if name and min_val and max_val:
                self.session_scales_names.append(name)
                self.session_scales_data.append((name, min_val, max_val))

        # Collect optimization preferences
        if hasattr(view, "get_scale_optimization_prefs"):
            self.scale_optimization_prefs = view.get_scale_optimization_prefs()
        else:
            self.scale_optimization_prefs = []

        return True

    def prepare_step3(self, view) -> None:
        """
        Prepare Step 3 view with initial data (first-time setup).

        Args:
            view: The Step3View instance
        """
        model = ELECTRODE_MODELS.get(self.current_electrode_model_name)
        if model and hasattr(view, "set_electrode_model"):
            view.set_electrode_model(model)

        # Set initial stimulation parameters from Step 1
        view.set_initial_stimulation_params(
            self.current_stimulation.left_frequency or "",
            self.current_stimulation.left_cathode or "",
            self.current_stimulation.left_anode or "",
            self.current_stimulation.left_amplitude or "",
            self.current_stimulation.left_pulse_width or "",
            self.current_stimulation.right_frequency or "",
            self.current_stimulation.right_cathode or "",
            self.current_stimulation.right_anode or "",
            self.current_stimulation.right_amplitude or "",
            self.current_stimulation.right_pulse_width or "",
            self.current_group or "",
        )

        # Update session scales
        view.update_session_scales(self.session_scales_data)

    def refresh_step3_scales(self, view) -> None:
        """
        Refresh only session scales in Step 3 if definitions changed.
        Called when returning to step3 (not first time).

        Args:
            view: The Step3View instance
        """
        current_names = [name for name, _ in view.session_scale_value_edits] if hasattr(view, "session_scale_value_edits") else []
        new_names = [n for n, _, _ in self.session_scales_data]
        if current_names != new_names:
            view.update_session_scales(self.session_scales_data)

    def insert_session_row(self, view) -> None:
        """
        Insert a session data row into the TSV file.

        Args:
            view: The Step3View instance
        """
        # Collect session scales
        session_scales = []
        for name, value_widget in view.session_scale_value_edits:
            scale_value = ""

            if hasattr(value_widget, "value") and callable(getattr(value_widget, "value")):
                try:
                    scale_value = f"{float(value_widget.value()) / 4.0:.2f}"
                except Exception:
                    scale_value = ""

            if name and scale_value != "":
                scale = SessionScale(name=name, current_value=str(scale_value))
                session_scales.append(scale)

        # Collect current stimulation parameters
        stimulation = StimulationParameters(
            left_frequency=view.session_left_stim_freq_edit.text(),
            left_cathode=view.get_left_cathode_text(),
            left_anode=view.get_left_anode_text(),
            left_amplitude=view.session_left_amp_edit.text(),
            left_pulse_width=view.session_left_pw_edit.text(),
            right_frequency=view.session_right_stim_freq_edit.text(),
            right_cathode=view.get_right_cathode_text(),
            right_anode=view.get_right_anode_text(),
            right_amplitude=view.session_right_amp_edit.text(),
            right_pulse_width=view.session_right_pw_edit.text(),
        )

        notes = view.session_notes_edit.toPlainText()
        group = view.group_combo.currentText() if hasattr(view, "group_combo") else ""

        self.session_data.write_session_scales(
            session_scales,
            stimulation,
            group=group,
            electrode_model=self.current_electrode_model_name or "",
            notes=notes,
        )

        # Animate button and clear notes
        animate_button(view.insert_button)
        view.session_notes_edit.clear()

    def close_session(self, parent) -> None:
        """
        Close the current session and file.

        Args:
            parent: The parent widget for dialogs
        """
        self.session_data.close_file()
        QMessageBox.information(
            parent, "Session closed", "Session closed and file saved."
        )
        parent.close()

    def export_session_word(self, parent) -> None:
        """
        Export current session data to Word format.
        
        Args:
            parent: The parent widget for dialogs
        """
        # Pass scale optimization preferences to exporter
        self.session_exporter.set_scale_optimization_prefs(self.scale_optimization_prefs)
        self.session_exporter.export_to_word(parent)

    def export_session_pdf(self, parent) -> None:
        """
        Export current session data to PDF format.
        
        Args:
            parent: The parent widget for dialogs
        """
        # Pass scale optimization preferences to exporter
        self.session_exporter.set_scale_optimization_prefs(self.scale_optimization_prefs)
        self.session_exporter.export_to_pdf(parent)

    # ============================================
    # Annotations-Only Workflow Methods
    # ============================================

    def browse_save_location_simple(self, view, parent) -> None:
        """
        Browse for save location (annotations-only mode).

        Args:
            view: The AnnotationsFileView instance
            parent: The parent widget for dialogs
        """
        from PyQt5.QtWidgets import QFileDialog
        import os

        # Get current path if available
        current_path = view.file_path_edit.text()
        if current_path:
            start_dir = os.path.dirname(current_path)
        else:
            start_dir = ""

        # Open save file dialog with default name "annot"
        file_path, _ = QFileDialog.getSaveFileName(
            parent,
            "Save Annotations File",
            os.path.join(start_dir, "annot.tsv") if start_dir else "annot.tsv",
            "TSV Files (*.tsv);;All Files (*)"
        )

        if file_path:
            # Ensure .tsv extension
            if not file_path.endswith('.tsv'):
                file_path += '.tsv'
            view.file_path_edit.setText(file_path)

    def validate_annotations_file(self, view, parent) -> bool:
        """
        Validate file information for annotations-only mode.

        Args:
            view: The AnnotationsFileView instance
            parent: The parent widget for dialogs

        Returns:
            True if validation passes, False otherwise
        """
        file_path = view.file_path_edit.text().strip()

        # Check file path
        if not file_path:
            QMessageBox.warning(
                parent, "Missing File", "Please select a file path to save."
            )
            return False

        import os

        mode = getattr(view, "current_file_mode", None)
        file_exists = os.path.exists(file_path)

        # Initialize simple session file
        try:
            if mode == "new":
                self.session_data.initialize_simple_file(file_path)
            elif mode == "existing":
                self.session_data.open_simple_file_append(file_path)
            else:
                # Fallback: if the file already exists, append; otherwise create.
                if file_exists:
                    self.session_data.open_simple_file_append(file_path)
                else:
                    self.session_data.initialize_simple_file(file_path)
            return True
        except Exception as e:
            QMessageBox.critical(
                parent, "Error", f"Failed to initialize file:\n{str(e)}"
            )
            return False

    def insert_simple_annotation(self, view) -> None:
        """
        Insert a simple annotation (timestamp + text only).

        Args:
            view: The AnnotationsSessionView instance
        """
        annotation = view.get_annotation().strip()

        if not annotation:
            return  # Don't insert empty annotations

        # Write annotation with timestamp
        self.session_data.write_simple_annotation(annotation)

        # Animate button and clear text
        animate_button(view.insert_button)
        view.clear_annotation()

    def export_annotations_word(self, parent) -> None:
        """Export annotations-only TSV to a simple Word report."""
        self.session_exporter.export_annotations_to_word(parent)

    def export_annotations_pdf(self, parent) -> None:
        """Export annotations-only TSV to a simple PDF report (if available)."""
        self.session_exporter.export_annotations_to_pdf(parent)
