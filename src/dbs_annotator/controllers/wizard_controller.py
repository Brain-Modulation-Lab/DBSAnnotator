"""
Wizard controller for managing the application flow and business logic.

This module contains the main controller that coordinates between the
views and models, handling user interactions and data flow.
"""

import csv

from PySide6.QtWidgets import QMessageBox

from ..config_electrode_models import ELECTRODE_MODELS
from ..models import ClinicalScale, SessionData, SessionScale, StimulationParameters
from ..utils import animate_button
from ..utils.scale_preset_manager import get_scale_preset_manager


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
        self.session_scales_names: list[str] = []
        self.session_scales_data: list[tuple[str, str, str]] = []
        # Scale optimization preferences: (name, min, max, mode, custom_value)
        # mode: "low", "high", "custom", "ignore"
        self.scale_optimization_prefs: list[tuple[str, str, str, str, str]] = []
        self.workflow_mode: str | None = None  # "full" or "annotations_only"
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
        preset_manager = get_scale_preset_manager()
        clinical_presets = preset_manager.get_clinical_presets()
        preset = clinical_presets.get(preset_name, [])
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
        preset_manager = get_scale_preset_manager()
        session_presets = preset_manager.get_session_presets()
        preset = session_presets.get(preset_name, [])
        view.update_session_scales(
            preset,
            on_add_callback=lambda: self.on_add_session_scale(view),
            on_remove_callback=lambda row: self.on_remove_session_scale(view, row),
        )

        # Set the active preset button
        preset_btn = view.get_preset_button(preset_name)
        if preset_btn:
            view._set_active_preset_button(preset_btn)

    def on_add_clinical_scale(self, view) -> None:
        """
        Handle add button click for clinical scales.

        Args:
            view: The Step1View instance
        """
        # Collect current scales with their values (excluding last empty row)
        preset_scales = []
        for name_edit, score_edit, _ in view.clinical_scales_rows[:-1]:
            name = name_edit.text()
            score = score_edit.text()
            if name:
                preset_scales.append((name, score))

        # Check if last row has text to add
        last_row = view.clinical_scales_rows[-1]
        if last_row[0].text():
            preset_scales.append((last_row[0].text(), last_row[1].text()))

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
        for name_edit, score_edit, row_layout in view.clinical_scales_rows[:-1]:
            if row_layout != layout:
                name = name_edit.text()
                score = score_edit.text()
                preset_scales.append((name, score))

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
        for row_data in view.session_scales_rows[:-1]:
            name_edit, scale1_edit, scale2_edit, row_layout = (
                row_data[0],
                row_data[1],
                row_data[2],
                row_data[3],
            )
            if row_layout != layout:
                name = name_edit.text()
                minval = scale1_edit.text()
                maxval = scale2_edit.text()
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
                self.session_data.open_file_append(
                    file_path, start_block_id=start_block_id
                )
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
        # Use split amplitude text when multiple cathodes are active
        left_amp_text = (
            view.left_amp_split.get_amplitude_text()
            if hasattr(view, "left_amp_split")
            else view.left_amp_edit.text()
        )
        right_amp_text = (
            view.right_amp_split.get_amplitude_text()
            if hasattr(view, "right_amp_split")
            else view.right_amp_edit.text()
        )
        stimulation = StimulationParameters(
            left_frequency=view.left_stim_freq_edit.text(),
            left_cathode=view.get_left_cathode_text(),
            left_anode=view.get_left_anode_text(),
            left_amplitude=left_amp_text,
            left_pulse_width=view.left_pw_edit.text(),
            right_frequency=view.right_stim_freq_edit.text(),
            right_cathode=view.get_right_cathode_text(),
            right_anode=view.get_right_anode_text(),
            right_amplitude=right_amp_text,
            right_pulse_width=view.right_pw_edit.text(),
        )

        notes = view.notes_edit.toPlainText()
        group = view.group_combo.currentText() if hasattr(view, "group_combo") else ""

        electrode_model = (
            view.model_combo.currentText() if hasattr(view, "model_combo") else ""
        )
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
        self.current_electrode_model_name = (
            view.model_combo.currentText() if hasattr(view, "model_combo") else ""
        )

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

    def auto_select_session_preset(self, view, step1_view) -> None:
        """
        Auto-select session preset if clinical preset with same name was selected.

        Args:
            view: The Step2View instance
            step1_view: The Step1View instance to read active preset from
        """
        # Read the active preset name from the step1_view's active button
        active_preset_name = None
        if step1_view and step1_view.active_preset_button is not None:
            obj_name = step1_view.active_preset_button.objectName()
            # objectName is like "preset_OCD" -> extract "OCD"
            if obj_name.startswith("preset_"):
                active_preset_name = obj_name[len("preset_") :]

        if active_preset_name:
            preset_manager = get_scale_preset_manager()
            session_presets = preset_manager.get_session_presets()

            if active_preset_name in session_presets:
                # Apply the matching session preset
                self.apply_session_preset(active_preset_name, view)

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
        current_names = (
            [name for name, _ in view.session_scale_value_edits]
            if hasattr(view, "session_scale_value_edits")
            else []
        )
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

            # Check if widget is disabled (X button clicked)
            if hasattr(value_widget, "isDisabled") and value_widget.isDisabled():
                scale_value = "NaN"
            elif hasattr(value_widget, "value") and callable(value_widget.value):
                try:
                    scale_value = f"{float(value_widget.value()) / 4.0:.2f}"
                except Exception:
                    scale_value = ""

            if name and scale_value != "":
                scale = SessionScale(name=name, current_value=str(scale_value))
                session_scales.append(scale)

        # Collect current stimulation parameters
        # Use split amplitude text when multiple cathodes are active
        left_amp_text = (
            view.left_amp_split.get_amplitude_text()
            if hasattr(view, "left_amp_split")
            else view.session_left_amp_edit.text()
        )
        right_amp_text = (
            view.right_amp_split.get_amplitude_text()
            if hasattr(view, "right_amp_split")
            else view.session_right_amp_edit.text()
        )
        stimulation = StimulationParameters(
            left_frequency=view.session_left_stim_freq_edit.text(),
            left_cathode=view.get_left_cathode_text(),
            left_anode=view.get_left_anode_text(),
            left_amplitude=left_amp_text,
            left_pulse_width=view.session_left_pw_edit.text(),
            right_frequency=view.session_right_stim_freq_edit.text(),
            right_cathode=view.get_right_cathode_text(),
            right_anode=view.get_right_anode_text(),
            right_amplitude=right_amp_text,
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

        # Enable undo button after successful insert
        if hasattr(view, "undo_button"):
            view.undo_button.setEnabled(True)

    def undo_last_session_entry(self, view) -> None:
        """
        Delete the last block_ID entry from the TSV file.

        Args:
            view: The Step3View instance
        """
        if not self.session_data.is_file_open():
            QMessageBox.warning(view, "Error", "No file is currently open.")
            return

        # Get the last written block_id (current block_id is the next one to write)
        last_written_block_id = self.session_data.block_id - 1

        if last_written_block_id < 0:
            QMessageBox.warning(view, "Error", "No entries to undo.")
            return

        # Read the TSV file and filter out rows with the last block_id
        file_path = self.session_data.file_path
        if file_path is None:
            QMessageBox.warning(
                view, "Error", "No file path is associated with this session."
            )
            return
        rows_to_keep = []
        rows_to_delete = []

        with open(file_path, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f, delimiter="\t")
            fieldnames = list(reader.fieldnames or [])

            for row in reader:
                block_id = row.get("block_id", "")
                try:
                    if int(block_id) != last_written_block_id:
                        rows_to_keep.append(row)
                    else:
                        rows_to_delete.append(row)
                except (ValueError, TypeError):
                    # If block_id is not a number, keep the row
                    rows_to_keep.append(row)

        if not rows_to_delete:
            QMessageBox.warning(
                view,
                "Error",
                f"No entries found with block_id {last_written_block_id}.",
            )
            return

        # Decrement block_id to point to the previous entry
        self.session_data.block_id = last_written_block_id

        # Rewrite the TSV file with the filtered rows
        with open(file_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter="\t")
            writer.writeheader()
            writer.writerows(rows_to_keep)

        # Disable undo button if no more entries to undo
        if self.session_data.block_id == 0 or len(rows_to_keep) == 0:
            if hasattr(view, "undo_button"):
                view.undo_button.setEnabled(False)

    def close_session(self, parent) -> None:
        """
        Close the current session and file.

        Args:
            parent: The parent widget for dialogs
        """
        # Show confirmation dialog
        reply = QMessageBox.question(
            parent,
            "Confirm Close Session",
            "Are you sure you want to close the current session? "
            "The session will be saved before closing.",
            QMessageBox.StandardButton.Ok | QMessageBox.StandardButton.Cancel,
            QMessageBox.StandardButton.Cancel,
        )

        if reply == QMessageBox.StandardButton.Ok:
            self.session_data.close_file()
            parent.close()

    def export_session_word(self, parent, scale_prefs=None, sections=None) -> None:
        """
        Export current session data to Word format.

        Args:
            parent: The parent widget for dialogs
            scale_prefs: Scale optimization prefs from the dialog
            sections: List of section keys to include
        """
        self.session_exporter.set_scale_optimization_prefs(scale_prefs or [])
        self.session_exporter.export_to_word(parent, sections=sections)

    def export_session_pdf(self, parent, scale_prefs=None, sections=None) -> None:
        """
        Export current session data to PDF format.

        Args:
            parent: The parent widget for dialogs
            scale_prefs: Scale optimization prefs from the dialog
            sections: List of section keys to include
        """
        self.session_exporter.set_scale_optimization_prefs(scale_prefs or [])
        self.session_exporter.export_to_pdf(parent, sections=sections)

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
        import os

        from PySide6.QtWidgets import QFileDialog

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
            "TSV Files (*.tsv);;All Files (*)",
        )

        if file_path:
            # Ensure .tsv extension
            if not file_path.endswith(".tsv"):
                file_path += ".tsv"
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

    # ============================================
    # Longitudinal Workflow Methods
    # ============================================

    def export_longitudinal_report(
        self,
        file_paths: list,
        scale_prefs: list,
        fmt: str,
        parent_widget=None,
        sections=None,
        clinical_scale_prefs: list | None = None,
    ) -> None:
        """
        Generate a longitudinal report combining data from multiple TSV files.

        Args:
            file_paths: List of TSV file paths to combine
            scale_prefs: Scale optimization prefs as a list of
                ``(name, min, max, mode, custom_value)`` tuples.
            fmt: "word" or "pdf"
            parent_widget: Parent widget for dialogs
            sections: List of section keys to include
            clinical_scale_prefs: Clinical scale prefs, same format as scale_prefs
        """
        from ..utils.longitudinal_exporter import LongitudinalExporter

        exporter = LongitudinalExporter()
        exporter.set_scale_optimization_prefs(scale_prefs)
        exporter.set_clinical_scale_prefs(clinical_scale_prefs)

        if fmt == "word":
            exporter.export_to_word(file_paths, parent_widget, sections=sections)
        else:
            exporter.export_to_pdf(file_paths, parent_widget, sections=sections)
