"""
Dialog for editing clinical scales presets.
"""

import json
import os
import typing

from PySide6.QtCore import QEvent, Qt, Signal
from PySide6.QtGui import QCloseEvent, QFont
from PySide6.QtWidgets import (
    QDialog,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
)

from ..utils.resources import resource_path


class ClinicalScalesSettingsDialog(QDialog):
    """Dialog for editing clinical scales presets."""

    presets_changed = Signal(dict)

    def __init__(
        self, current_presets: dict[str, list[str]], parent=None, original_presets=None
    ):
        """Initialize with existing presets.

        Args:
            current_presets: Dict mapping preset name to list of scale names.
            parent: Optional parent widget.
            original_presets: Optional fallback presets list.
        """
        super().__init__(parent)
        self.current_presets = current_presets.copy()
        self.original_presets = original_presets or []
        self.presets_file = resource_path("config/clinical_presets.json")

        self.setWindowTitle("Clinical Scales Settings")
        self.setModal(True)
        self.resize(500, 400)

        self._setup_ui()
        self._load_presets()

    def _setup_ui(self):
        """Setup the dialog UI."""
        layout = QVBoxLayout(self)

        # Title
        title = QLabel("Edit Clinical Scales Presets")
        title.setFont(QFont("Segoe UI", 12, QFont.Bold))
        title.setAlignment(Qt.AlignCenter)
        layout.addWidget(title)

        # Presets list
        self.presets_list = QListWidget()
        self.presets_list.setMaximumHeight(150)
        layout.addWidget(QLabel("Current Presets:"))
        layout.addWidget(self.presets_list)

        # Edit section
        edit_group = QGroupBox("Edit Preset")
        edit_layout = QFormLayout(edit_group)

        self.preset_name_edit = QLineEdit()
        self.preset_name_edit.setPlaceholderText("Enter preset name...")
        edit_layout.addRow("Preset Name:", self.preset_name_edit)

        self.scales_edit = QLineEdit()
        self.scales_edit.setPlaceholderText("Enter scales separated by commas...")
        edit_layout.addRow("Scales:", self.scales_edit)

        layout.addWidget(edit_group)

        # Buttons
        button_layout = QHBoxLayout()

        self.add_btn = QPushButton("Add/Update Preset")
        self.add_btn.clicked.connect(self._add_update_preset)
        button_layout.addWidget(self.add_btn)

        self.delete_btn = QPushButton("Delete Selected")
        self.delete_btn.clicked.connect(self._delete_preset)
        button_layout.addWidget(self.delete_btn)

        button_layout.addStretch()

        layout.addLayout(button_layout)

        # Dialog buttons
        dialog_buttons = QHBoxLayout()

        dialog_buttons.addStretch()

        save_btn = QPushButton("Save & Close")
        save_btn.clicked.connect(self._save_and_close)
        dialog_buttons.addWidget(save_btn)

        close_btn = QPushButton("Close")
        close_btn.clicked.connect(self.reject)
        dialog_buttons.addWidget(close_btn)

        layout.addLayout(dialog_buttons)

        # Connect list selection
        self.presets_list.itemSelectionChanged.connect(self._on_preset_selected)

        # Handle deselection by clicking empty space in the list
        self.presets_list.viewport().installEventFilter(self)

    @typing.override
    def eventFilter(self, obj, event):
        """Handle clicks on empty space for deselection."""
        if (
            obj == self.presets_list.viewport()
            and event.type() == QEvent.MouseButtonPress
        ):
            if event.button() == Qt.LeftButton:
                # Check if click is on empty space
                item = self.presets_list.itemAt(event.pos())
                if item is None:
                    self._clear_selection()
        return super().eventFilter(obj, event)

    @typing.override
    def mousePressEvent(self, event):
        """Deselect preset when clicking outside the list widget."""
        # If user clicks outside the list, clear selection
        if event.button() == Qt.LeftButton:
            list_rect = self.presets_list.geometry()
            if not list_rect.contains(event.pos()):
                self._clear_selection()
        super().mousePressEvent(event)

    def _clear_selection(self):
        """Clear list selection and reset edit fields."""
        self.presets_list.blockSignals(True)
        self.presets_list.clearSelection()
        self.presets_list.blockSignals(False)
        self.preset_name_edit.clear()
        self.scales_edit.clear()

    def _load_presets(self):
        """Load presets from file."""
        file_presets = {}
        if os.path.exists(self.presets_file):
            try:
                with open(self.presets_file, encoding="utf-8") as f:
                    file_presets = json.load(f)
            except Exception as e:
                print(f"Error loading presets from file: {e}")

        # Merge with current presets (current presets take precedence)
        for name, scales in file_presets.items():
            if name not in self.current_presets:
                self.current_presets[name] = scales

        self._update_presets_list()

    def _update_presets_list(self):
        """Update the presets list widget."""
        self.presets_list.clear()

        for name, scales in self.current_presets.items():
            item_text = f"{name}: {', '.join(scales)}"
            item = QListWidgetItem(item_text)
            item.setData(Qt.UserRole, name)
            self.presets_list.addItem(item)

    def _on_preset_selected(self):
        """Handle preset selection in list."""
        selected_items = self.presets_list.selectedItems()
        if not selected_items:
            self.preset_name_edit.clear()
            self.scales_edit.clear()
            return

        item = selected_items[0]
        preset_name = item.data(Qt.UserRole)

        if preset_name in self.current_presets:
            self.preset_name_edit.setText(preset_name)
            self.scales_edit.setText(", ".join(self.current_presets[preset_name]))

    def _add_update_preset(self):
        """Add or update a preset."""
        name = self.preset_name_edit.text().strip()
        scales_text = self.scales_edit.text().strip()

        if not name or not scales_text:
            return

        scales = [scale.strip() for scale in scales_text.split(",") if scale.strip()]

        self.current_presets[name] = scales
        self._update_presets_list()

        # Clear inputs
        self.preset_name_edit.clear()
        self.scales_edit.clear()

        # Select the newly added/updated preset in the list
        for i in range(self.presets_list.count()):
            item = self.presets_list.item(i)
            if item and item.data(Qt.UserRole) == name:
                self.presets_list.setCurrentItem(item)
                break

    def _delete_preset(self):
        """Delete selected preset."""
        selected_items = self.presets_list.selectedItems()
        if not selected_items:
            return

        item = selected_items[0]
        preset_name = item.data(Qt.UserRole)

        reply = QMessageBox.question(
            self,
            "Confirm Delete",
            f"Are you sure you want to delete preset '{preset_name}'?",
            QMessageBox.Yes | QMessageBox.No,
        )

        if reply == QMessageBox.Yes:
            del self.current_presets[preset_name]
            self._update_presets_list()

            # Clear inputs if deleted preset was being edited
            if self.preset_name_edit.text() == preset_name:
                self.preset_name_edit.clear()
                self.scales_edit.clear()

    def _save_and_close(self):
        """Save presets to file and close dialog."""
        try:
            # Ensure config directory exists
            os.makedirs(os.path.dirname(self.presets_file), exist_ok=True)

            # Save all presets to file
            with open(self.presets_file, "w", encoding="utf-8") as f:
                json.dump(self.current_presets, f, indent=2, ensure_ascii=False)

            # Emit presets for UI
            self.presets_changed.emit(self.current_presets)
            self.accept()

        except Exception as e:
            QMessageBox.critical(self, "Error", f"Error saving presets: {e}")

    @typing.override
    def closeEvent(self, event: QCloseEvent):
        """Handle dialog close event to save changes."""
        # Save changes before closing
        try:
            # Ensure config directory exists
            os.makedirs(os.path.dirname(self.presets_file), exist_ok=True)

            # Save all presets to file
            with open(self.presets_file, "w", encoding="utf-8") as f:
                json.dump(self.current_presets, f, indent=2, ensure_ascii=False)

            # Emit the presets for the UI
            self.presets_changed.emit(self.current_presets)

        except Exception:
            # Don't show error message on close to avoid annoying the user
            pass

        super().closeEvent(event)
