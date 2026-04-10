"""
Export dialogs for report generation.

Provides:
- ScaleTargetValuesDialog: lets the user set target values (min/max/custom)
  for each session scale, used before exporting any report.
- ReportSectionsDialog: lets the user choose which sections to include.

These dialogs are shared by both the longitudinal workflow and the Step-3
single-session export.
"""

from PySide6.QtCore import Qt
from PySide6.QtGui import QDoubleValidator
from PySide6.QtWidgets import (
    QButtonGroup,
    QCheckBox,
    QDialog,
    QDialogButtonBox,
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
    Dialog that shows session scales and lets the user pick an optimization
    mode for each, with a checkbox to include / exclude individual scales.

    Accepted result: call ``get_scale_prefs()`` to retrieve
    ``[(name, min, max, mode, custom_value), ...]``.
    Unchecked scales get ``mode="ignore"``.
    """

    def __init__(
        self,
        scales: list[tuple[str, str, str]],
        parent=None,
        title: str = "Select Scales Target Values",
    ):
        """
        Args:
            scales: list of (scale_name, observed_min, observed_max)
            title: window title
        """
        super().__init__(parent)
        self.setWindowTitle(title)
        self.setMinimumWidth(680)
        self.setMinimumHeight(300)

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

        layout = QVBoxLayout(self)
        layout.setSpacing(12)

        # Header
        header = QLabel(
            "The following session scales were found.\n"
            "Uncheck a scale to exclude it from the best-entry calculation."
        )
        header.setWordWrap(True)
        header.setStyleSheet("padding: 4px;")
        layout.addWidget(header)

        # Scrollable scale rows
        scroll_content = QWidget()
        scroll_content.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Minimum)
        scroll_content.setAutoFillBackground(False)
        self._rows_layout = QVBoxLayout(scroll_content)
        self._rows_layout.setContentsMargins(0, 0, 0, 0)
        self._rows_layout.setSpacing(6)

        for name, min_v, max_v in scales:
            self._add_scale_row(name, min_v, max_v)

        self._rows_layout.addStretch()

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QScrollArea.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
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
        btn_box = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        btn_box.accepted.connect(self.accept)
        btn_box.rejected.connect(self.reject)
        layout.addWidget(btn_box)

    # -----------------------------------------------------------------

    def _add_scale_row(self, name: str, min_v: str, max_v: str) -> None:
        """Add a single scale row with checkbox + Min / Max / Custom."""
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

        self._rows.append(
            (name, min_v, max_v, checkbox, group, custom_edit, toggleable)
        )

    # -----------------------------------------------------------------

    def get_scale_prefs(self) -> list[tuple[str, str, str, str, str]]:
        """
        Return the user's optimization preferences.

        Returns:
            List of (name, min, max, mode, custom_value) tuples.
            mode is one of ``"low"``, ``"high"``, ``"custom"``, ``"ignore"``.
            Unchecked scales get ``mode="ignore"``.
        """
        prefs = []
        for name, min_v, max_v, checkbox, group, custom_edit, _ in self._rows:
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


class ReportSectionsDialog(QDialog):
    """
    Dialog that lets the user choose which sections to include in the report.

    Initialise with a list of (key, label, default_checked) tuples.
    Call ``get_selected_sections()`` to retrieve the list of selected keys in
    the original order.
    """

    def __init__(
        self,
        sections: list[tuple[str, str, bool]],
        parent=None,
        title: str = "Report Sections",
    ):
        super().__init__(parent)
        self.setWindowTitle(title)
        self.setMinimumWidth(340)
        self._checkboxes: list[tuple[str, QCheckBox]] = []

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

        for key, section_label, checked in sections:
            cb = QCheckBox(section_label)
            cb.setChecked(checked)
            layout.addWidget(cb)
            self._checkboxes.append((key, cb))

        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def get_selected_sections(self) -> list[str]:
        """Return ordered list of keys for checked sections."""
        return [key for key, cb in self._checkboxes if cb.isChecked()]
