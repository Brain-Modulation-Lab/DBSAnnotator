"""
Step 2 view - Session scales configuration.

This module contains the view for the second step where users configure
the session tracking scales that will be used during the programming session.
"""

import logging
from collections.abc import Callable

from PySide6.QtCore import QSize, Qt
from PySide6.QtGui import QFont
from PySide6.QtWidgets import (
    QFrame,
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

from ..config import PLACEHOLDERS, PRESET_BUTTONS
from ..ui.session_scales_settings_dialog import SessionScalesSettingsDialog
from ..utils.scale_preset_manager import get_scale_preset_manager
from .base_view import BaseStepView

logger = logging.getLogger(__name__)


class Step2View(BaseStepView):
    """
    Second step view for session scales configuration.

    This view handles:
    - Selection of session tracking scales
    - Configuration of scale ranges (min/max values)
    """

    def __init__(self, parent_style=None):
        """
        Initialize Step 2 view.

        Args:
            parent_style: Parent widget style for icon access (deprecated,
                kept for compatibility).
        """
        super().__init__()
        # parent_style is now set in BaseStepView.__init__
        self.session_presets: dict[str, list[tuple[str, str, str]]] = (
            self._load_session_presets()
        )
        self.preset_buttons: list[QPushButton] = []
        # Each row: (name_edit, min_edit, max_edit, row_layout, None, None)
        self.session_scales_rows: list[
            tuple[QLineEdit, QLineEdit, QLineEdit, QHBoxLayout, None, None]
        ] = []
        self.active_preset_button: QPushButton | None = None  # Track active preset
        self._setup_ui()

    def get_header_title(self) -> str:
        """Return the wizard header title for Step 2."""
        return "Session Scale Configuration"

    def _setup_ui(self) -> None:
        """Set up the UI layout."""
        # Session scales group
        session_group = self._create_session_scales_group()
        self.main_layout.addWidget(session_group)
        # self.main_layout.addStretch(1)

        self.next_button = QPushButton("Next")
        self.next_button.setIcon(
            self.parent_style.standardIcon(QStyle.StandardPixmap.SP_ArrowForward)
        )
        self.next_button.setIconSize(QSize(16, 16))
        self.next_button.setMaximumWidth(120)

    def _create_session_scales_group(self) -> QGroupBox:
        """Create the session scales group box."""
        gb_session = QGroupBox("Session scales")
        gb_session.setStyleSheet(
            "QGroupBox::title { color: #ff8800; font-size: 11pt; font-weight: 600; }"
        )
        gb_session.setFont(QFont("Segoe UI", 10, QFont.Weight.Bold))
        gb_session.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding
        )

        layout = QVBoxLayout(gb_session)

        # Preset buttons (dynamic from JSON)
        preset_row = QHBoxLayout()
        preset_row.addStretch(1)

        settings_btn = QPushButton()
        settings_btn.setIcon(self._create_settings_icon())
        settings_btn.setObjectName("settings_session_scales")
        settings_btn.setToolTip("Settings session scales")
        settings_btn.clicked.connect(self._open_session_scales_settings)
        preset_row.addWidget(settings_btn)

        layout.addLayout(preset_row)

        self.preset_row_layout = preset_row
        self._refresh_preset_buttons()

        # Container for dynamic scale rows - expands to show all rows
        scroll_content = QWidget()
        scroll_content.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum
        )
        self.session_scales_container = QVBoxLayout(scroll_content)
        self.session_scales_container.setContentsMargins(0, 0, 0, 0)

        # Scrollable area - will only scroll when user resizes window smaller
        scroll_area = QScrollArea()
        scroll_area.setStyleSheet("""
            QScrollArea {
                background: transparent;
                border: none;
            }
            QScrollArea > QWidget > QWidget {
                background: transparent;
            }
        """)
        scroll_area.setWidgetResizable(True)
        scroll_area.setFrameShape(QFrame.Shape.NoFrame)
        scroll_area.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        scroll_area.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        scroll_area.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum
        )
        scroll_area.setWidget(scroll_content)

        layout.addWidget(scroll_area)

        return gb_session

    def get_preset_button(self, preset_name: str) -> QPushButton | None:
        """Get a preset button by name."""
        return self.findChild(QPushButton, f"preset2_{preset_name}")

    def _load_session_presets(self) -> dict[str, list[tuple[str, str, str]]]:
        """Load session presets from ScalePresetManager."""
        preset_manager = get_scale_preset_manager()
        return preset_manager.get_session_presets()

    def _open_session_scales_settings(self):
        """Open the session scales settings dialog."""
        dialog = SessionScalesSettingsDialog(self.session_presets, self, PRESET_BUTTONS)
        dialog.presets_changed.connect(self._on_presets_changed)
        dialog.exec()

    def _on_presets_changed(self, new_presets: dict[str, list[tuple[str, str, str]]]):
        """Handle presets change from settings dialog and persist to JSON."""
        self.session_presets = new_presets

        # Save all presets using ScalePresetManager
        try:
            preset_manager = get_scale_preset_manager()
            preset_manager.save_session_presets(new_presets)
        except Exception:
            logger.exception("Failed to save session presets")

        self._refresh_preset_buttons()

        if hasattr(self, "on_add_callback") and hasattr(self, "on_remove_callback"):
            self._connect_preset_buttons()

    def _refresh_preset_buttons(self):
        """Rebuild the preset button row from the current presets dictionary."""
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
            preset_row.itemAt(stretch_index)
            and preset_row.itemAt(stretch_index).spacerItem()
        ):
            preset_row.insertStretch(settings_index, 1)
            settings_index += 1
            stretch_index = settings_index - 1

        insert_index = stretch_index

        ordered_names: list[str] = []
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
        """Wire each preset button to apply its scales on click."""
        import warnings

        for btn in self.preset_buttons:
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", RuntimeWarning)
                try:
                    btn.clicked.disconnect()
                except RuntimeError:
                    pass

            preset_name = btn.objectName().replace("preset2_", "")
            preset_scales = self.session_presets.get(preset_name, [])

            def create_handler(scales, button):
                def handler():
                    self._set_active_preset_button(button)
                    self._apply_preset_scales(scales)

                return handler

            btn.clicked.connect(create_handler(preset_scales, btn))

    def _set_active_preset_button(self, button: QPushButton) -> None:
        """Set the active preset button and update visual state."""
        # Clear previous active button
        if self.active_preset_button is not None:
            try:
                self.active_preset_button.setProperty("active", "false")
                self.active_preset_button.style().unpolish(self.active_preset_button)
                self.active_preset_button.style().polish(self.active_preset_button)
            except RuntimeError:
                pass
            self.active_preset_button = None

        # Set new active button
        self.active_preset_button = button
        if button is not None:
            button.setProperty("active", "true")
            button.style().unpolish(button)
            button.style().polish(button)

    def _apply_preset_scales(self, scales: list[tuple[str, str, str]]):
        """Replace the current session scale rows with the given preset scales."""
        if not isinstance(scales, list):
            return

        if hasattr(self, "on_add_callback") and hasattr(self, "on_remove_callback"):
            for row_data in self.session_scales_rows:
                row_layout = row_data[3]
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

            self._add_session_scale_row(
                "", "", "", with_plus=True, on_add=self.on_add_callback
            )

            # Add stretch at very bottom
            self.session_scales_container.addStretch()

    def update_session_scales(
        self,
        preset_scales: list[tuple[str, str, str]],
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
        for row_data in self.session_scales_rows:
            row_layout = row_data[3]
            while row_layout.count():
                item = row_layout.takeAt(0)
                widget = item.widget()
                if widget is not None:
                    widget.deleteLater()
            self.session_scales_container.removeItem(row_layout)
        self.session_scales_rows = []

        # Remove any existing stretches from container
        while self.session_scales_container.count():
            item = self.session_scales_container.takeAt(0)
            if item.spacerItem():
                # Just remove the stretch, no widget to delete
                continue
            elif item.widget():
                item.widget().deleteLater()

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

    def get_session_scales_data(self) -> list[tuple[str, str, str]]:
        """
        Get session scale definitions (name, min, max) for use by the
        ScaleTargetValuesDialog at export time.

        Returns:
            List of (name, min, max) tuples for scales that have all fields filled.
        """
        scales = []
        for row_data in self.session_scales_rows:
            name_edit, min_edit, max_edit = row_data[0], row_data[1], row_data[2]
            name = name_edit.text().strip()
            min_val = min_edit.text().strip()
            max_val = max_edit.text().strip()
            if name and min_val and max_val:
                scales.append((name, min_val, max_val))
        return scales

    def _add_session_scale_row(
        self,
        name: str = "",
        minval: str = "",
        maxval: str = "",
        with_plus: bool = False,
        with_minus: bool = False,
        on_add: Callable[[], None] | None = None,
        on_remove: Callable[[QHBoxLayout], None] | None = None,
    ) -> None:
        """Add a single session scale row (name, min, max)."""
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
            btn.setFixedSize(20, 20)
            btn.setObjectName("scale_add_btn")
            if on_add:
                btn.clicked.connect(on_add)
        elif with_minus:
            btn = QPushButton("-")
            btn.setToolTip("Remove session scale")
            btn.setFixedSize(20, 20)
            btn.setObjectName("scale_remove_btn")
            if on_remove:
                btn.clicked.connect(lambda: on_remove(row))
        else:
            btn = QLabel("")
            btn.setFixedSize(20, 20)

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
        self.session_scales_rows.append(
            (name_edit, scale1_edit, scale2_edit, row, None, None)
        )
