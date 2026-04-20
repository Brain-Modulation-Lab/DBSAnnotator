"""Export dialogs for report generation.

Provides:

- ``ScaleTargetValuesDialog``: lets the user set target values
  (min/max/custom) for each session scale, used before exporting any report.
- ``ReportSectionsDialog``: lets the user choose which sections to include.

These dialogs are shared by both the longitudinal workflow and the Step-3
single-session export.
"""

from collections.abc import Sequence

from PySide6.QtCore import Qt
from PySide6.QtGui import QDoubleValidator
from PySide6.QtWidgets import (
    QButtonGroup,
    QCheckBox,
    QDialog,
    QDialogButtonBox,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QScrollArea,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

from ..utils.theme_manager import get_theme_manager


class ScaleTargetValuesDialog(QDialog):
    """
    Dialog that shows session scales (and optionally clinical scales) and
    lets the user pick an optimization mode for each, with a checkbox to
    include / exclude individual scales.

    Accepted result: call ``get_scale_prefs()`` for session scales and
    ``get_clinical_scale_prefs()`` for clinical scales.
    Each returns ``[(name, min, max, mode, custom_value), ...]``.
    Unchecked scales get ``mode="ignore"``.
    """

    def __init__(
        self,
        scales: list[tuple[str, str, str]],
        parent=None,
        title: str = "Select Scales Target Values",
        clinical_scales: list[tuple[str, str, str]] | None = None,
    ):
        """
        Args:
            scales: list of (scale_name, observed_min, observed_max) for session scales
            title: window title
            clinical_scales: optional list of (scale_name, observed_min, observed_max)
                for clinical (is_initial=1) scales
        """
        super().__init__(parent)
        self.setWindowTitle(title)
        self.setMinimumWidth(720)
        self.setMinimumHeight(350)

        # Apply current theme stylesheet
        theme_manager = get_theme_manager()
        try:
            stylesheet = theme_manager.load_stylesheet(
                theme_manager.get_current_theme()
            )
            self.setStyleSheet(stylesheet)
        except FileNotFoundError:
            if parent and parent.styleSheet():
                self.setStyleSheet(parent.styleSheet())

        # Each entry: (name, min, max, checkbox, button_group, custom_edit, row_widgets)
        self._rows: list = []
        self._clinical_rows: list = []

        layout = QVBoxLayout(self)
        layout.setSpacing(12)

        # Scrollable content for both sections
        scroll_content = QWidget()
        scroll_content.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum
        )
        scroll_content.setAutoFillBackground(False)
        self._rows_layout = QVBoxLayout(scroll_content)
        self._rows_layout.setContentsMargins(0, 0, 0, 0)
        self._rows_layout.setSpacing(6)

        # ── Session Scales section ──────────────────────────────────
        session_header = QLabel(
            "<b>Session Scales</b><br>"
            "Uncheck a scale to exclude it from the best-entry calculation."
        )
        session_header.setWordWrap(True)
        session_header.setStyleSheet("padding: 4px;")
        self._rows_layout.addWidget(session_header)

        for name, min_v, max_v in scales:
            self._add_scale_row(name, min_v, max_v, target_list=self._rows)

        # ── Clinical Scales section (optional) ──────────────────────
        if clinical_scales:
            separator = QLabel("")
            separator.setFixedHeight(8)
            self._rows_layout.addWidget(separator)

            clinical_header = QLabel(
                "<b>Clinical Scales</b><br>"
                "Set target values for clinical (baseline) scales."
            )
            clinical_header.setWordWrap(True)
            clinical_header.setStyleSheet("padding: 4px;")
            self._rows_layout.addWidget(clinical_header)

            for name, min_v, max_v in clinical_scales:
                self._add_scale_row(name, min_v, max_v, target_list=self._clinical_rows)

        self._rows_layout.addStretch()

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        scroll.setWidget(scroll_content)
        scroll.setStyleSheet("""
            QScrollArea {
                background: transparent;
                border: none;
            }
            QScrollArea > QWidget > QWidget {
                background: transparent;
            }
        """)
        layout.addWidget(scroll, 1)

        # Dialog buttons
        btn_box = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        btn_box.accepted.connect(self.accept)
        btn_box.rejected.connect(self.reject)
        layout.addWidget(btn_box)

    # -----------------------------------------------------------------

    def _add_scale_row(
        self,
        name: str,
        min_v: str,
        max_v: str,
        target_list: list | None = None,
    ) -> None:
        """Add a single scale row with checkbox + Min / Max / Custom."""
        if target_list is None:
            target_list = self._rows
        row_layout = QHBoxLayout()

        # Checkbox (default: checked / enabled)
        checkbox = QCheckBox()
        checkbox.setChecked(True)
        checkbox.setToolTip("Include this scale in the calculation")
        row_layout.addWidget(checkbox)

        name_label = QLabel(f"<b>{name}</b>")
        name_label.setMinimumWidth(120)
        row_layout.addWidget(name_label)

        range_label = QLabel(f"[{min_v} – {max_v}]")
        range_label.setProperty("_default_style", "color: #64748b;")
        range_label.setStyleSheet("color: #64748b;")
        range_label.setMinimumWidth(80)
        row_layout.addWidget(range_label)

        row_layout.addSpacing(10)

        best_if_label = QLabel("Best if:")
        row_layout.addWidget(best_if_label)

        group = QButtonGroup(self)
        group.setExclusive(True)

        btn_low = QPushButton("Min")
        btn_low.setCheckable(True)
        btn_low.setChecked(True)
        btn_low.setMinimumWidth(55)
        btn_low.setProperty("class", "best-if-btn")
        btn_low.setToolTip("Lower values are better")
        group.addButton(btn_low, 0)

        btn_high = QPushButton("Max")
        btn_high.setCheckable(True)
        btn_high.setMinimumWidth(55)
        btn_high.setProperty("class", "best-if-btn")
        btn_high.setToolTip("Higher values are better")
        group.addButton(btn_high, 1)

        btn_custom = QPushButton("Custom")
        btn_custom.setCheckable(True)
        btn_custom.setMinimumWidth(65)
        btn_custom.setProperty("class", "best-if-btn")
        btn_custom.setToolTip("Specify target value")
        group.addButton(btn_custom, 2)

        custom_edit = QLineEdit()
        custom_edit.setPlaceholderText("target")
        custom_edit.setMinimumWidth(55)
        custom_edit.setMaximumWidth(60)
        custom_edit.setVisible(False)
        custom_edit.setValidator(QDoubleValidator())

        def _on_mode_changed(button_id, ce=custom_edit):
            ce.setVisible(button_id == 2)

        group.idClicked.connect(_on_mode_changed)

        row_layout.addWidget(btn_low)
        row_layout.addWidget(btn_high)
        row_layout.addWidget(btn_custom)
        row_layout.addWidget(custom_edit)
        row_layout.addStretch(1)

        self._rows_layout.addLayout(row_layout)

        # Collect widgets whose opacity we toggle on check/uncheck
        toggleable = [
            name_label,
            range_label,
            best_if_label,
            btn_low,
            btn_high,
            btn_custom,
            custom_edit,
        ]

        def _on_toggled(checked, widgets=toggleable):
            for w in widgets:
                w.setEnabled(checked)
                if checked:
                    default = w.property("_default_style")
                    w.setStyleSheet(default if default else "")
                else:
                    w.setStyleSheet("color: rgba(128,128,128,0.4);")  # disabled style

        checkbox.toggled.connect(_on_toggled)

        target_list.append(
            (name, min_v, max_v, checkbox, group, custom_edit, toggleable)
        )

    # -----------------------------------------------------------------

    @staticmethod
    def _extract_prefs(
        rows: list,
    ) -> list[tuple[str, str, str, str, str]]:
        """Extract preference tuples from a row list."""
        prefs: list[tuple[str, str, str, str, str]] = []
        for name, min_v, max_v, checkbox, group, custom_edit, _ in rows:
            if not checkbox.isChecked():
                prefs.append((name, min_v, max_v, "ignore", ""))
                continue

            checked_id = group.checkedId()
            if checked_id == 1:
                mode = "max"
            elif checked_id == 2:
                mode = "custom"
            else:
                mode = "min"
            custom_value = custom_edit.text().strip() if mode == "custom" else ""
            prefs.append((name, min_v, max_v, mode, custom_value))
        return prefs

    def get_scale_prefs(self) -> list[tuple[str, str, str, str, str]]:
        """
        Return the user's optimization preferences for **session** scales.

        Returns:
            List of (name, min, max, mode, custom_value) tuples.
            mode is one of ``"min"``, ``"max"``, ``"custom"``, ``"ignore"``.
            Unchecked scales get ``mode="ignore"``.
        """
        return self._extract_prefs(self._rows)

    def get_clinical_scale_prefs(self) -> list[tuple[str, str, str, str, str]]:
        """
        Return the user's optimization preferences for **clinical** scales.

        Returns:
            Same format as :meth:`get_scale_prefs`.
        """
        return self._extract_prefs(self._clinical_rows)


class ReportSectionsDialog(QDialog):
    """
    Dialog that lets the user choose which sections to include in the report.

    Initialise with a list of (key, label, default_checked, children) tuples.
    children is an optional list of (key, label, default_checked) tuples for nested
    checkboxes.
    Call ``get_selected_sections()`` to retrieve the list of selected keys in
    the original order.
    """

    def __init__(
        self,
        sections: Sequence[tuple[str, str, bool, list | None]],
        parent=None,
        title: str = "Report Sections",
    ):
        super().__init__(parent)
        self.setWindowTitle(title)
        self.setMinimumWidth(340)
        self._checkboxes: list[tuple[str, QCheckBox]] = []
        self._parent_child_map: dict[
            str, list[str]
        ] = {}  # parent key -> list of child keys
        self._child_parent_map: dict[str, str] = {}  # child key -> parent key

        # Apply current theme stylesheet
        theme_manager = get_theme_manager()
        try:
            stylesheet = theme_manager.load_stylesheet(
                theme_manager.get_current_theme()
            )
            self.setStyleSheet(stylesheet)
        except FileNotFoundError:
            if parent and parent.styleSheet():
                self.setStyleSheet(parent.styleSheet())

        layout = QVBoxLayout(self)
        layout.setSpacing(8)

        label = QLabel("Select the sections to include in the report:")
        label.setWordWrap(True)
        layout.addWidget(label)

        for key, section_label, checked, children in sections:
            cb = QCheckBox(section_label)
            cb.setChecked(checked)
            layout.addWidget(cb)
            self._checkboxes.append((key, cb))

            # Add nested children if present
            if children:
                child_layout = QVBoxLayout()
                child_layout.setContentsMargins(20, 0, 0, 0)  # Indent for children
                child_layout.setSpacing(4)

                child_keys = []
                for child_key, child_label, child_checked in children:
                    child_cb = QCheckBox(child_label)
                    child_cb.setChecked(child_checked)
                    child_layout.addWidget(child_cb)
                    self._checkboxes.append((child_key, child_cb))
                    child_keys.append(child_key)
                    self._child_parent_map[child_key] = key

                    # Connect child checkbox to update parent
                    child_cb.toggled.connect(
                        lambda checked, parent=cb: self._on_child_toggled(
                            parent, checked
                        )
                    )

                self._parent_child_map[key] = child_keys
                layout.addLayout(child_layout)

                # Connect parent checkbox to update children
                cb.toggled.connect(
                    lambda checked, keys=child_keys: self._on_parent_toggled(
                        keys, checked
                    )
                )

                # If parent is initially checked, also check all children
                if checked:
                    for child_key in child_keys:
                        for k, c in self._checkboxes:
                            if k == child_key:
                                c.setChecked(True)
                                break

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _on_parent_toggled(self, child_keys: list[str], checked: bool) -> None:
        """Handle parent checkbox toggled - update all children."""
        for child_key in child_keys:
            for key, cb in self._checkboxes:
                if key == child_key:
                    cb.setChecked(checked)
                    break

    def _on_child_toggled(self, parent_cb: QCheckBox, checked: bool) -> None:
        """Handle child checkbox toggled: update parent if all children share state."""
        # Find parent key from parent checkbox
        parent_key = None
        for key, cb in self._checkboxes:
            if cb == parent_cb:
                parent_key = key
                break

        if not parent_key:
            return

        # Get all children of this parent
        child_keys = self._parent_child_map.get(parent_key, [])

        # Check if all children are checked
        all_checked = True
        all_unchecked = True
        for child_key in child_keys:
            for key, cb in self._checkboxes:
                if key == child_key:
                    if cb.isChecked():
                        all_unchecked = False
                    else:
                        all_checked = False
                    break

        # Update parent checkbox
        parent_cb.blockSignals(True)
        if all_checked:
            parent_cb.setChecked(True)
        elif all_unchecked:
            parent_cb.setChecked(False)
        # If mixed, set to partially checked
        else:
            parent_cb.setTristate(True)
            parent_cb.setCheckState(Qt.CheckState.PartiallyChecked)
        parent_cb.blockSignals(False)

    def get_selected_sections(self) -> list[str]:
        """Return ordered list of keys for checked sections."""
        selected = []
        for key, cb in self._checkboxes:
            if cb.isChecked():
                # If this is a parent with children, include children instead of parent
                if key in self._parent_child_map:
                    child_keys = self._parent_child_map[key]
                    # Include all checked children
                    for child_key in child_keys:
                        for k, c in self._checkboxes:
                            if k == child_key and c.isChecked():
                                selected.append(child_key)
                                break
                else:
                    selected.append(key)
        return selected
