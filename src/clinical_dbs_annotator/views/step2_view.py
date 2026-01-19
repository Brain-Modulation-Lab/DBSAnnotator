"""
Step 2 view - Session scales configuration.

This module contains the view for the second step where users configure
the session tracking scales that will be used during the programming session.
"""

import json
import os
from typing import Callable, Dict, List, Tuple

from PyQt5.QtCore import QSize, Qt
from PyQt5.QtGui import QFont, QPixmap
from PyQt5.QtWidgets import (
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QScrollArea,
    QSizePolicy,
    QStyle,
    QVBoxLayout,
    QWidget,
)

from ..config import PLACEHOLDERS, PRESET_BUTTONS, SESSION_SCALES_PRESETS
from ..ui.session_scales_settings_dialog import SessionScalesSettingsDialog
from ..utils.resources import resource_path
from .base_view import BaseStepView


class Step2View(BaseStepView):
    """
    Second step view for session scales configuration.

    This view handles:
    - Selection of session tracking scales
    - Configuration of scale ranges (min/max values)
    """

    def __init__(self, logo_pixmap: QPixmap, parent_style):
        """
        Initialize Step 2 view.

        Args:
            logo_pixmap: Application logo
            parent_style: Parent widget style for icon access
        """
        super().__init__(logo_pixmap)
        self.parent_style = parent_style
        self.session_presets: Dict[str, List[Tuple[str, str, str]]] = self._load_session_presets()
        self.preset_buttons: List[QPushButton] = []
        self.session_scales_rows: List[
            Tuple[QLineEdit, QLineEdit, QLineEdit, QHBoxLayout]
        ] = []
        self._setup_ui()

    def _setup_ui(self) -> None:
        """Set up the UI layout."""
        # Header
        header = self.create_header("Which session scales would you like to track?")
        self.main_layout.addWidget(header)

        # Session scales group
        session_group = self._create_session_scales_group()
        self.main_layout.addWidget(session_group)
        self.main_layout.addStretch(1)

        # Next button
        self.next_button = QPushButton("Next")
        self.next_button.setIcon(self.parent_style.standardIcon(QStyle.SP_ArrowForward))
        self.next_button.setIconSize(QSize(16, 16))
        self.next_button.setMaximumWidth(120)
        self.main_layout.addWidget(self.next_button, alignment=Qt.AlignRight)

    def _create_session_scales_group(self) -> QGroupBox:
        """Create the session scales group box."""
        gb_session = QGroupBox("Session scales")
        gb_session.setStyleSheet(
            "QGroupBox::title { color: #ff8800; font-size: 11pt; font-weight: 600; }"
        )
        gb_session.setFont(QFont("Segoe UI", 10, QFont.Bold))
        gb_session.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        gb_session.setMinimumHeight(400)  # Increased height for better visibility

        layout = QVBoxLayout(gb_session)

        # Preset buttons (dynamic from JSON)
        preset_row = QHBoxLayout()
        preset_row.addStretch(1)

        settings_btn = QPushButton("⚙️")
        settings_btn.setObjectName("settings_session_scales")
        settings_btn.setToolTip("Settings session scales")
        settings_btn.clicked.connect(self._open_session_scales_settings)
        preset_row.addWidget(settings_btn)

        layout.addLayout(preset_row)

        self.preset_row_layout = preset_row
        self._refresh_preset_buttons()

        # Container for dynamic scale rows - expands to show all rows
        scroll_content = QWidget()
        scroll_content.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.session_scales_container = QVBoxLayout(scroll_content)
        self.session_scales_container.setContentsMargins(0, 0, 0, 0)

        # Scrollable area - will only scroll when user resizes window smaller
        scroll_area = QScrollArea()
        scroll_area.setWidgetResizable(True)
        scroll_area.setFrameShape(QScrollArea.NoFrame)
        scroll_area.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        scroll_area.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        scroll_area.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        scroll_area.setWidget(scroll_content)

        layout.addWidget(scroll_area)

        return gb_session

    def get_preset_button(self, preset_name: str) -> QPushButton:
        """Get a preset button by name."""
        return self.findChild(QPushButton, f"preset2_{preset_name}")

    def _load_session_presets(self) -> Dict[str, List[Tuple[str, str, str]]]:
        presets_file = resource_path("config/session_scales_presets.json")

        if os.path.exists(presets_file):
            try:
                with open(presets_file, "r", encoding="utf-8") as f:
                    raw = json.load(f)
                presets: Dict[str, List[Tuple[str, str, str]]] = {}
                for name, scales in (raw or {}).items():
                    try:
                        presets[name] = [tuple(x) for x in scales]
                    except Exception:
                        presets[name] = []
                return presets
            except Exception as e:
                print(f"Error loading session presets: {e}")
                return {}

        return {k: list(v) for k, v in SESSION_SCALES_PRESETS.items()}

    def _open_session_scales_settings(self):
        dialog = SessionScalesSettingsDialog(self.session_presets, self, PRESET_BUTTONS)
        dialog.presets_changed.connect(self._on_presets_changed)
        dialog.exec_()

    def _on_presets_changed(self, new_presets: Dict[str, List[Tuple[str, str, str]]]):
        self.session_presets = new_presets

        try:
            presets_file = resource_path("config/session_scales_presets.json")
            os.makedirs(os.path.dirname(presets_file), exist_ok=True)
            serializable = {k: [list(x) for x in v] for k, v in new_presets.items()}
            with open(presets_file, "w", encoding="utf-8") as f:
                json.dump(serializable, f, indent=2, ensure_ascii=False)
        except Exception as e:
            print(f"Error saving session presets: {e}")

        self._refresh_preset_buttons()

        if hasattr(self, "on_add_callback") and hasattr(self, "on_remove_callback"):
            self._connect_preset_buttons()

    def _refresh_preset_buttons(self):
        for btn in self.preset_buttons:
            btn.setParent(None)
            btn.deleteLater()
        self.preset_buttons.clear()

        preset_row = getattr(self, "preset_row_layout", None)
        if not preset_row:
            return

        widgets_to_remove = []
        for i in range(preset_row.count()):
            item = preset_row.itemAt(i)
            if item and item.widget():
                widget = item.widget()
                if widget and widget.objectName() != "settings_session_scales":
                    widgets_to_remove.append(widget)

        for widget in widgets_to_remove:
            preset_row.removeWidget(widget)
            widget.setParent(None)
            widget.deleteLater()

        settings_btn = None
        settings_index = -1
        for i in range(preset_row.count()):
            item = preset_row.itemAt(i)
            if item and item.widget():
                widget = item.widget()
                if widget and widget.objectName() == "settings_session_scales":
                    settings_btn = widget
                    settings_index = i
                    break

        if settings_btn is None:
            return

        stretch_index = settings_index - 1
        if stretch_index < 0 or not (
            preset_row.itemAt(stretch_index) and preset_row.itemAt(stretch_index).spacerItem()
        ):
            preset_row.insertStretch(settings_index, 1)
            settings_index += 1
            stretch_index = settings_index - 1

        insert_index = stretch_index

        ordered_names: List[str] = []
        for name in PRESET_BUTTONS:
            if name in self.session_presets:
                ordered_names.append(name)
        for name in self.session_presets.keys():
            if name not in ordered_names:
                ordered_names.append(name)

        for preset_name in ordered_names:
            btn = QPushButton(preset_name)
            btn.setObjectName(f"preset2_{preset_name}")
            self.preset_buttons.append(btn)
            preset_row.insertWidget(insert_index, btn)
            insert_index += 1
            settings_index += 1
            stretch_index += 1

        if hasattr(self, "on_add_callback") and hasattr(self, "on_remove_callback"):
            self._connect_preset_buttons()

    def _connect_preset_buttons(self):
        for btn in self.preset_buttons:
            try:
                btn.clicked.disconnect()
            except Exception:
                pass

            preset_name = btn.objectName().replace("preset2_", "")
            preset_scales = self.session_presets.get(preset_name, [])

            def create_handler(scales):
                return lambda: self._apply_preset_scales(scales)

            btn.clicked.connect(create_handler(preset_scales))

    def _apply_preset_scales(self, scales: List[Tuple[str, str, str]]):
        if not isinstance(scales, list):
            return

        if hasattr(self, "on_add_callback") and hasattr(self, "on_remove_callback"):
            for _, _, _, row_layout in self.session_scales_rows:
                while row_layout.count():
                    item = row_layout.takeAt(0)
                    widget = item.widget()
                    if widget is not None:
                        widget.deleteLater()
                self.session_scales_container.removeItem(row_layout)
            self.session_scales_rows = []

            while self.session_scales_container.count():
                item = self.session_scales_container.takeAt(0)
                if item.spacerItem():
                    continue
                if item.widget():
                    item.widget().deleteLater()

            for name, minval, maxval in scales:
                self._add_session_scale_row(
                    name,
                    minval,
                    maxval,
                    with_minus=True,
                    on_remove=self.on_remove_callback,
                )

            self._add_session_scale_row("", "", "", with_plus=True, on_add=self.on_add_callback)

            # Add stretch at very bottom 
            self.session_scales_container.addStretch()

    def update_session_scales(
        self,
        preset_scales: List[Tuple[str, str, str]],
        on_add_callback: Callable,
        on_remove_callback: Callable,
    ) -> None:
        """
        Update the session scales UI with the given scales.

        Args:
            preset_scales: List of (name, min, max) tuples
            on_add_callback: Callback for add button
            on_remove_callback: Callback for remove button
        """
        # Clear existing rows
        for _, _, _, row_layout in self.session_scales_rows:
            while row_layout.count():
                item = row_layout.takeAt(0)
                widget = item.widget()
                if widget is not None:
                    widget.deleteLater()
            self.session_scales_container.removeItem(row_layout)
        self.session_scales_rows = []

        # Add preset scales
        for name, minval, maxval in preset_scales:
            self._add_session_scale_row(
                name, minval, maxval, with_minus=True, on_remove=on_remove_callback
            )

        # Add empty row with add button
        self._add_session_scale_row("", "", "", with_plus=True, on_add=on_add_callback)

        # Add stretch at bottom to push content up
        self.session_scales_container.addStretch()

        self.on_add_callback = on_add_callback
        self.on_remove_callback = on_remove_callback
        self._connect_preset_buttons()

    def _add_session_scale_row(
        self,
        name: str = "",
        minval: str = "",
        maxval: str = "",
        with_plus: bool = False,
        with_minus: bool = False,
        on_add: Callable = None,
        on_remove: Callable = None,
    ) -> None:
        """Add a single session scale row."""
        row = QHBoxLayout()

        name_edit = QLineEdit()
        name_edit.setPlaceholderText(PLACEHOLDERS["scale_name"])
        name_edit.setMaximumWidth(100)
        name_edit.setText(name)

        scale1_edit = QLineEdit()
        scale1_edit.setPlaceholderText(PLACEHOLDERS["scale_min"])
        scale1_edit.setMaximumWidth(40)
        scale1_edit.setText(minval)

        scale2_edit = QLineEdit()
        scale2_edit.setPlaceholderText(PLACEHOLDERS["scale_max"])
        scale2_edit.setMaximumWidth(40)
        scale2_edit.setText(maxval)

        if with_plus:
            btn = QPushButton("+")
            btn.setToolTip("Add session scale")
            btn.setMaximumWidth(24)
            if on_add:
                btn.clicked.connect(on_add)
        elif with_minus:
            btn = QPushButton("-")
            btn.setToolTip("Remove session scale")
            btn.setMaximumWidth(24)
            if on_remove:
                btn.clicked.connect(lambda: on_remove(row))
        else:
            btn = QLabel("")

        row.addWidget(QLabel("Name:"))
        row.addWidget(name_edit)
        row.addSpacing(5)
        row.addWidget(QLabel("Min:"))
        row.addWidget(scale1_edit)
        row.addWidget(QLabel("Max:"))
        row.addWidget(scale2_edit)
        row.addWidget(btn)
        row.addStretch(1)

        self.session_scales_container.addLayout(row)
        self.session_scales_rows.append((name_edit, scale1_edit, scale2_edit, row))
