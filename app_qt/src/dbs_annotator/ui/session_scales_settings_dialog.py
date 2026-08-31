"""
Session scales settings dialog.

Provides a dialog for creating, editing, and deleting session-scale presets
(e.g. Mood 0-10, Anxiety 0-10). Presets are persisted to a JSON file.
"""

import json
import os
import typing

from PySide6.QtCore import QEvent, QObject, Qt, Signal
from PySide6.QtGui import QCloseEvent, QFont, QMouseEvent
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
from ..utils.user_data import user_config_file


class SessionScalesSettingsDialog(QDialog):
    """Dialog for managing session-scale presets (add / edit / delete)."""

    presets_changed = Signal(dict)

    def __init__(
        self,
        current_presets: dict[str, list[tuple[str, str, str]]],
        parent=None,
        original_presets=None,
    ):
        """Initialize the dialog with existing presets.

        Args:
            current_presets: Dict mapping preset name to list of (scale_name, min, max).
            parent: Optional parent widget.
            original_presets: Optional fallback presets list.
        """
        super().__init__(parent)
        self.current_presets = {
            k: [tuple(x) for x in v] for k, v in (current_presets or {}).items()
        }
        self.original_presets = original_presets or []
        # User-writable location (upgrade-safe). Bundled defaults, if any, are
        # seeded via `_load_presets` below.
        self.presets_file = str(user_config_file("session_scales_presets.json"))
        self._bundled_presets_file = resource_path("config/session_scales_presets.json")

        self.setWindowTitle("Session Scales Settings")
        self.setModal(True)
        self.resize(520, 420)

        self._setup_ui()
        self._load_presets()

    def _setup_ui(self):
        """Build the dialog layout: presets list, edit form, and action buttons."""
        layout = QVBoxLayout(self)

        title = QLabel("Edit Session Scales Presets")
        title.setFont(QFont("Segoe UI", 12, QFont.Weight.Bold))
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(title)

        self.presets_list = QListWidget()
        self.presets_list.setMaximumHeight(150)
        layout.addWidget(QLabel("Current Presets:"))
        layout.addWidget(self.presets_list)

        edit_group = QGroupBox("Edit Preset")
        edit_layout = QFormLayout(edit_group)

        self.preset_name_edit = QLineEdit()
        self.preset_name_edit.setPlaceholderText("Enter preset name...")
        edit_layout.addRow("Preset Name:", self.preset_name_edit)

        self.scales_edit = QLineEdit()
        self.scales_edit.setPlaceholderText("Example: Mood:0-10, Anxiety:0-10")
        edit_layout.addRow("Scales:", self.scales_edit)

        layout.addWidget(edit_group)

        button_layout = QHBoxLayout()

        self.add_btn = QPushButton("Add/Update Preset")
        self.add_btn.clicked.connect(self._add_update_preset)
        button_layout.addWidget(self.add_btn)

        self.delete_btn = QPushButton("Delete Selected")
        self.delete_btn.clicked.connect(self._delete_preset)
        button_layout.addWidget(self.delete_btn)

        button_layout.addStretch()
        layout.addLayout(button_layout)

        dialog_buttons = QHBoxLayout()
        dialog_buttons.addStretch()

        save_btn = QPushButton("Save & Close")
        save_btn.clicked.connect(self._save_and_close)
        dialog_buttons.addWidget(save_btn)

        close_btn = QPushButton("Close")
        close_btn.clicked.connect(self.reject)
        dialog_buttons.addWidget(close_btn)

        layout.addLayout(dialog_buttons)

        self.presets_list.itemSelectionChanged.connect(self._on_preset_selected)
        self.presets_list.viewport().installEventFilter(self)

    @typing.override
    def eventFilter(self, arg__1: QObject, arg__2: QEvent) -> bool:
        """Deselect preset when clicking empty space in the list."""
        if (
            arg__1 == self.presets_list.viewport()
            and arg__2.type() == QEvent.Type.MouseButtonPress
        ):
            me = typing.cast(QMouseEvent, arg__2)
            if me.button() == Qt.MouseButton.LeftButton:
                item = self.presets_list.itemAt(me.pos())
                if item is None:
                    self._clear_selection()
        return super().eventFilter(arg__1, arg__2)

    def mousePressEvent(self, event):  # noqa: N802
        """Deselect preset when clicking outside the list widget."""
        if event.button() == Qt.MouseButton.LeftButton:
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
        """Load presets from the JSON config file and merge with current.

        Prefers the user-writable location; falls back to bundled defaults for
        fresh installs that have never been edited.
        """
        file_presets: dict[str, list] = {}
        for path in (self.presets_file, self._bundled_presets_file):
            if path and os.path.exists(path):
                try:
                    with open(path, encoding="utf-8") as f:
                        file_presets = json.load(f)
                    break
                except Exception:
                    file_presets = {}

        for name, scales in file_presets.items():
            if name not in self.current_presets:
                try:
                    self.current_presets[name] = [tuple(x) for x in scales]
                except Exception:
                    self.current_presets[name] = []

        self._update_presets_list()

    def _format_scales(self, scales: list[tuple[str, str, str]]) -> str:
        """Format a list of (name, min, max) tuples into a readable string."""
        parts = []
        for n, mn, mx in scales:
            parts.append(f"{n}({mn}-{mx})")
        return ", ".join(parts)

    def _update_presets_list(self):
        """Refresh the QListWidget with the current presets dictionary."""
        self.presets_list.clear()
        for name, scales in self.current_presets.items():
            item_text = f"{name}: {self._format_scales(scales)}"
            item = QListWidgetItem(item_text)
            item.setData(Qt.ItemDataRole.UserRole, name)
            self.presets_list.addItem(item)

    def _on_preset_selected(self):
        """Populate edit fields when a preset is selected in the list."""
        selected_items = self.presets_list.selectedItems()
        if not selected_items:
            self.preset_name_edit.clear()
            self.scales_edit.clear()
            return

        item = selected_items[0]
        preset_name = item.data(Qt.ItemDataRole.UserRole)
        scales = self.current_presets.get(preset_name, [])

        self.preset_name_edit.setText(preset_name)
        self.scales_edit.setText(", ".join([f"{n}:{mn}-{mx}" for n, mn, mx in scales]))

    def _parse_scales(self, text: str) -> list[tuple[str, str, str]]:
        """Parse user-entered text into a list of (name, min, max) tuples."""
        text = (text or "").strip()
        if not text:
            return []

        parts = [p.strip() for p in text.replace("\n", ",").split(",")]
        parts = [p for p in parts if p]

        scales: list[tuple[str, str, str]] = []
        for part in parts:
            if ":" in part:
                name, rest = part.split(":", 1)
                name = name.strip()
                rest = rest.strip()
                if "-" in rest:
                    mn, mx = rest.split("-", 1)
                elif "," in rest:
                    mn, mx = rest.split(",", 1)
                else:
                    continue
                mn = mn.strip()
                mx = mx.strip()
            else:
                chunks = [c.strip() for c in part.split(",") if c.strip()]
                if len(chunks) != 3:
                    continue
                name, mn, mx = chunks

            if name:
                scales.append((name, mn, mx))

        return scales

    def _add_update_preset(self):
        """Add a new preset or update an existing one from the edit fields."""
        name = self.preset_name_edit.text().strip()
        scales_text = self.scales_edit.text().strip()

        if not name or not scales_text:
            return

        scales = self._parse_scales(scales_text)
        if not scales:
            return

        self.current_presets[name] = scales
        self._update_presets_list()

        self.preset_name_edit.clear()
        self.scales_edit.clear()

        for i in range(self.presets_list.count()):
            item = self.presets_list.item(i)
            if item and item.data(Qt.ItemDataRole.UserRole) == name:
                self.presets_list.setCurrentItem(item)
                break

    def _delete_preset(self):
        """Delete the currently selected preset after user confirmation."""
        selected_items = self.presets_list.selectedItems()
        if not selected_items:
            return

        item = selected_items[0]
        preset_name = item.data(Qt.ItemDataRole.UserRole)

        reply = QMessageBox.question(
            self,
            "Confirm Delete",
            f"Are you sure you want to delete preset '{preset_name}'?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )

        if reply != QMessageBox.StandardButton.Yes:
            return

        if preset_name in self.current_presets:
            del self.current_presets[preset_name]
        self._update_presets_list()

        if self.preset_name_edit.text() == preset_name:
            self.preset_name_edit.clear()
            self.scales_edit.clear()

    def _save_presets_to_file(self):
        """Persist all presets to the JSON configuration file."""
        os.makedirs(os.path.dirname(self.presets_file), exist_ok=True)
        serializable = {
            k: [list(x) for x in v] for k, v in self.current_presets.items()
        }
        with open(self.presets_file, "w", encoding="utf-8") as f:
            json.dump(serializable, f, indent=2, ensure_ascii=False)

    def _save_and_close(self):
        """Save presets, emit signal, and close the dialog."""
        try:
            self._save_presets_to_file()
            self.presets_changed.emit(self.current_presets)
            self.accept()
        except Exception as e:
            QMessageBox.critical(self, "Error", f"Error saving presets: {e}")

    @typing.override
    def closeEvent(self, arg__1: QCloseEvent) -> None:
        """Auto-save presets when the dialog is closed."""
        try:
            self._save_presets_to_file()
            self.presets_changed.emit(self.current_presets)
        except Exception:
            pass
        super().closeEvent(arg__1)
