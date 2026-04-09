"""
Custom UI widgets and components.

This module provides reusable UI components such as increment buttons,
section labels, and horizontal lines.
"""

import typing

from PySide6.QtCore import QEvent, QSize, Qt, Signal
from PySide6.QtGui import QIcon, QPixmap
from PySide6.QtWidgets import (
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QProgressBar,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from ..config import BUTTON_SIZES, COLORS, ICON_SIZES
from ..utils import create_arrow_icon


def create_horizontal_line() -> QFrame:
    """
    Create a styled horizontal separator line.

    Returns:
        QFrame configured as a horizontal line
    """
    line = QFrame()
    line.setFrameShape(QFrame.HLine)
    line.setFrameShadow(QFrame.Sunken)
    line.setStyleSheet(
        f"background: {COLORS['separator']}; "
        "max-height: 2pt; min-height: 2pt; "
        "border: none; margin: 10pt 0 10pt 0;"
    )
    return line


def create_section_label(text: str) -> QLabel:
    """
    Create a styled section label.

    Args:
        text: The label text

    Returns:
        QLabel styled as a section header
    """
    label = QLabel(text)
    label.setStyleSheet(
        f"color: {COLORS['primary']}; "
        "font-size: 18pt; font-weight: 600; "
        "margin-bottom: 4pt;"
    )
    return label


class IncrementWidget(QWidget):
    """
    A widget that combines a QLineEdit with increment/decrement buttons.

    This widget provides a text input field with up/down arrow buttons for
    incrementing/decrementing numeric values. Supports single and dual-step modes.

    Attributes:
        line_edit: The QLineEdit for value input
        step1: Large increment/decrement step
        step2: Small increment/decrement step (optional)
        decimals: Number of decimal places for formatting
        min_value: Minimum allowed value
        max_value: Maximum allowed value
    """

    def __init__(
        self,
        line_edit: QLineEdit,
        step1: float = 1.0,
        step2: float | None = None,
        decimals: int = 2,
        min_value: float | None = None,
        max_value: float | None = None,
    ):
        """
        Initialize the increment widget.

        Args:
            line_edit: QLineEdit to attach increment buttons to
            step1: Primary step size for large adjustments
            step2: Secondary step size for small adjustments (optional)
            decimals: Number of decimal places for value formatting
            min_value: Minimum allowed value
            max_value: Maximum allowed value
        """
        super().__init__()
        self.line_edit = line_edit
        self.step1 = step1
        self.step2 = step2
        self.decimals = decimals
        self.min_value = min_value
        self.max_value = max_value

        self._setup_ui()

    def _setup_ui(self) -> None:
        """Set up the widget UI layout."""
        hbox = QHBoxLayout(self)
        hbox.setContentsMargins(0, 0, 0, 0)
        hbox.setSpacing(0)
        hbox.addWidget(self.line_edit)

        # Create primary increment/decrement buttons (step1)
        vbox1 = self._create_button_column(self.step1, double=True)
        hbox.addLayout(vbox1)

        # Create secondary buttons if step2 is provided
        if self.step2 is not None:
            vbox2 = self._create_button_column(self.step2, double=False)
            hbox.addLayout(vbox2)

        self.setMaximumWidth(self.sizeHint().width())

    def _create_button_column(self, step: float, double: bool = False) -> QVBoxLayout:
        """
        Create a column of up/down buttons.

        Args:
            step: The step value for this button pair
            double: If True, creates double arrow icons

        Returns:
            QVBoxLayout containing the up and down buttons
        """
        vbox = QVBoxLayout()
        vbox.setContentsMargins(0, 0, 0, 0)
        vbox.setSpacing(0)

        # Create up button
        btn_up = self._create_arrow_button("up", double)
        btn_up.clicked.connect(lambda: self._adjust_value(+step))

        # Create down button
        btn_down = self._create_arrow_button("down", double)
        btn_down.clicked.connect(lambda: self._adjust_value(-step))

        vbox.addWidget(btn_up)
        vbox.addWidget(btn_down)

        return vbox

    def _create_arrow_button(self, direction: str, double: bool) -> QPushButton:
        """
        Create an arrow button.

        Args:
            direction: Arrow direction ("up" or "down")
            double: If True, creates a double arrow icon

        Returns:
            Configured QPushButton with arrow icon
        """
        btn = QPushButton()
        btn.setIcon(create_arrow_icon(direction, double))
        btn.setIconSize(QSize(*ICON_SIZES["increment"]))
        btn.setFixedSize(
            BUTTON_SIZES["increment"]["width"], BUTTON_SIZES["increment"]["height"]
        )
        btn.setCursor(Qt.PointingHandCursor)
        btn.setStyleSheet(
            """
            QPushButton {
                background: transparent;
                border: none;
                padding: 0;
            }
            QPushButton:hover, QPushButton:pressed {
                background: transparent;
            }
        """
        )
        return btn

    def _adjust_value(self, delta: float) -> None:
        """
        Adjust the line edit value by a delta.

        Args:
            delta: Amount to add to current value (can be negative)
        """
        try:
            value = float(self.line_edit.text())
        except ValueError, TypeError:
            value = 0.0

        value += delta

        # Apply min/max constraints
        if self.min_value is not None:
            value = max(value, self.min_value)
        if self.max_value is not None:
            value = min(value, self.max_value)

        # Format and set the new value
        self.line_edit.setText(f"{value:.{self.decimals}f}")

    def get_line_edit(self) -> QLineEdit:
        """Get the underlying QLineEdit widget."""
        return self.line_edit


class ScaleProgressWidget(QWidget):
    """Interactive progress widget with arrow controls and drag support.

    Internal values are integers; UI displays value / 4.0 to represent 0.25 steps.
    """

    valueChanged = Signal(int)  # noqa: N815

    def __init__(self, parent=None):
        """Initialize the scale progress widget with default range 0-10."""
        super().__init__(parent)
        self._is_dragging = False
        self._minimum = 0
        self._maximum = 40
        self._value = 0
        self._disabled = False
        self._setup_ui()

    def _setup_ui(self) -> None:
        """Build layout: left arrows, progress bar, right arrows, reset button."""
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(4)

        # Left controls
        left_layout = QHBoxLayout()
        left_layout.setContentsMargins(0, 0, 0, 0)
        left_layout.setSpacing(2)

        self.left_single_btn = self._create_icon_button(
            self._create_lr_arrow_icon("left", False), 18, 18
        )
        self.left_single_btn.setToolTip("-0.25")
        self.left_single_btn.clicked.connect(lambda: self._adjust_value(-1))

        self.left_double_btn = self._create_icon_button(
            self._create_lr_arrow_icon("left", True), 24, 18
        )
        self.left_double_btn.setToolTip("-0.5")
        self.left_double_btn.clicked.connect(lambda: self._adjust_value(-2))

        left_layout.addWidget(self.left_single_btn)
        left_layout.addWidget(self.left_double_btn)

        # Progress bar
        self.progress_bar = QProgressBar()
        self.progress_bar.setMinimum(self._minimum)
        self.progress_bar.setMaximum(self._maximum)
        self.progress_bar.setValue(self._value)
        self.progress_bar.setFormat("0.00")
        self.progress_bar.setCursor(Qt.PointingHandCursor)
        self.progress_bar.valueChanged.connect(self._on_bar_value_changed)

        # Right controls
        right_layout = QHBoxLayout()
        right_layout.setContentsMargins(0, 0, 0, 0)
        right_layout.setSpacing(2)

        self.right_single_btn = self._create_icon_button(
            self._create_lr_arrow_icon("right", False), 18, 18
        )
        self.right_single_btn.setToolTip("+0.25")
        self.right_single_btn.clicked.connect(lambda: self._adjust_value(1))

        self.right_double_btn = self._create_icon_button(
            self._create_lr_arrow_icon("right", True), 24, 18
        )
        self.right_double_btn.setToolTip("+0.5")
        self.right_double_btn.clicked.connect(lambda: self._adjust_value(2))

        self.reset_btn = self._create_icon_button(self._create_x_icon(), 18, 18)
        self.reset_btn.setToolTip("Disable/Enable")
        self.reset_btn.clicked.connect(self._toggle_disabled)

        right_layout.addWidget(self.right_single_btn)
        right_layout.addWidget(self.right_double_btn)
        right_layout.addWidget(self.reset_btn)

        layout.addLayout(left_layout)
        layout.addWidget(self.progress_bar)
        layout.addLayout(right_layout)

        self.progress_bar.installEventFilter(self)

    def _create_icon_button(self, icon: QIcon, w: int, h: int) -> QPushButton:
        """Create a small transparent icon button."""
        btn = QPushButton()
        btn.setFixedSize(w, h)
        btn.setIcon(icon)
        btn.setIconSize(QSize(w - 2, h - 2))
        btn.setCursor(Qt.PointingHandCursor)
        btn.setStyleSheet(
            """
            QPushButton {
                background: transparent;
                border: none;
                padding: 0;
            }
            QPushButton:hover, QPushButton:pressed {
                background: transparent;
            }
            """
        )
        return btn

    def _create_lr_arrow_icon(self, direction: str, double: bool) -> QIcon:
        """Generate an SVG left/right arrow icon (single or double chevron)."""
        arrow_color = "#cccccc"
        if double:
            if direction == "left":
                svg = f"""
                <svg width="16" height="16" viewBox="0 0 18 18" fill="none">
                    <polygon points="12,4 7,9 12,14" fill="{arrow_color}"/>
                    <polygon points="16,4 11,9 16,14" fill="{arrow_color}"/>
                </svg>
                """
            else:
                svg = f"""
                <svg width="16" height="16" viewBox="0 0 18 18" fill="none">
                    <polygon points="6,4 11,9 6,14" fill="{arrow_color}"/>
                    <polygon points="2,4 7,9 2,14" fill="{arrow_color}"/>
                </svg>
                """
        else:
            if direction == "left":
                svg = f"""
                <svg width="16" height="16" viewBox="0 0 18 18" fill="none">
                    <polygon points="12,4 7,9 12,14" fill="{arrow_color}"/>
                </svg>
                """
            else:
                svg = f"""
                <svg width="16" height="16" viewBox="0 0 18 18" fill="none">
                    <polygon points="6,4 11,9 6,14" fill="{arrow_color}"/>
                </svg>
                """

        pixmap = QPixmap()
        pixmap.loadFromData(bytes(svg, encoding="utf-8"), "SVG")
        return QIcon(pixmap)

    def _create_x_icon(self) -> QIcon:
        """Generate an SVG 'x' (reset) icon."""
        color = "#cccccc"
        svg = f"""
        <svg width="16" height="16" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg">
            <line x1="5" y1="5" x2="13" y2="13" stroke="{color}" stroke-width="2" stroke-linecap="round"/>
            <line x1="13" y1="5" x2="5" y2="13" stroke="{color}" stroke-width="2" stroke-linecap="round"/>
        </svg>
        """
        pixmap = QPixmap()
        pixmap.loadFromData(bytes(svg, encoding="utf-8"), "SVG")
        return QIcon(pixmap)

    @typing.override
    def eventFilter(self, obj, event):
        """Handle mouse press/move/release on the progress bar for drag interaction."""
        if obj == self.progress_bar:
            if event.type() == QEvent.MouseButtonPress:
                self._is_dragging = True
                self._update_value_from_position(event.pos().x())
                return True
            if event.type() == QEvent.MouseMove and self._is_dragging:
                self._update_value_from_position(event.pos().x())
                return True
            if event.type() == QEvent.MouseButtonRelease:
                self._is_dragging = False
                return True
        return super().eventFilter(obj, event)

    def _adjust_value(self, delta: int) -> None:
        """Increment or decrement the current value by *delta* steps."""
        if self._disabled:
            self.setDisabled(False)
        new_value = max(self._minimum, min(self._maximum, self._value + delta))
        self.setValue(new_value)

    def _update_value_from_position(self, x_position: int) -> None:
        """Map a pixel x-position on the bar to the corresponding value."""
        if self._disabled:
            self.setDisabled(False)
        rect = self.progress_bar.rect()
        if rect.width() > 0:
            relative_x = max(0, min(x_position, rect.width()))
            value = int((relative_x / rect.width()) * self._maximum)
            self.setValue(value)

    def _on_bar_value_changed(self, value: int) -> None:
        """Sync internal state and update the display label."""
        self._value = value
        if not self._disabled:
            self.valueChanged.emit(value)
        self._update_display()

    def _update_display(self) -> None:
        """Update the progress bar appearance based on disabled state."""
        if self._disabled:
            self.progress_bar.setFormat("")
            self.progress_bar.setStyleSheet("""
                QProgressBar {
                    border: 1px solid #cccccc;
                    border-radius: 3px;
                    background-color: #f5f5f5;
                }
                QProgressBar::chunk {
                    background-color: #e0e0e0;
                }
            """)
        else:
            actual_value = self._value / 4.0
            self.progress_bar.setFormat(f"{actual_value:.2f}")
            self.progress_bar.setStyleSheet("")

    def _toggle_disabled(self) -> None:
        """Toggle disabled state when X button is clicked."""
        self._disabled = not self._disabled
        self._update_display()
        if not self._disabled:
            # Re-enable and emit current value
            self.valueChanged.emit(self._value)

    # Public API (mirrors old InteractiveProgressBar)
    @typing.override
    def setMinimum(self, value: int) -> None:
        """Set the minimum internal value."""
        self._minimum = int(value)
        self.progress_bar.setMinimum(int(value))

    @typing.override
    def setMaximum(self, value: int) -> None:
        """Set the maximum internal value."""
        self._maximum = int(value)
        self.progress_bar.setMaximum(int(value))

    @typing.override
    def setValue(self, value: int) -> None:
        """Set the current value and update the progress bar."""
        self._value = int(value)
        self.progress_bar.setValue(int(value))

    @typing.override
    def setFormat(self, format_str: str) -> None:
        """Set the text format displayed on the progress bar."""
        self.progress_bar.setFormat(format_str)

    @typing.override
    def setFixedWidth(self, width: int) -> None:
        """Override to allocate space for arrow buttons alongside the bar."""
        # Same reserve logic as previous implementation
        bar_width = width - 120
        self.progress_bar.setFixedWidth(bar_width)
        super().setFixedWidth(width)

    @typing.override
    def setToolTip(self, tooltip: str) -> None:
        """Forward the tooltip to the inner progress bar."""
        self.progress_bar.setToolTip(tooltip)

    def value(self) -> int:
        """Return the current internal value."""
        return self._value

    @typing.override
    def isDisabled(self) -> bool:
        """Return True if the widget is in disabled state."""
        return self._disabled

    @typing.override
    def setDisabled(self, disabled: bool) -> None:
        """Set the disabled state."""
        if self._disabled != disabled:
            self._disabled = disabled
            self._update_display()
            if not self._disabled:
                self.valueChanged.emit(self._value)
