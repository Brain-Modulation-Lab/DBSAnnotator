"""
Base view class for wizard steps.

This module provides the base class that all step views inherit from,
containing common functionality and UI elements.
"""

from PySide6.QtCore import QByteArray
from PySide6.QtGui import QIcon, QPixmap
from PySide6.QtWidgets import QHBoxLayout, QLabel, QPushButton, QVBoxLayout, QWidget


class BaseStepView(QWidget):
    """
    Base class for all wizard step views.

    This class provides common functionality for step views including:
    - Common UI patterns
    - Header title provision for global header

    Subclasses should implement their specific UI in their setup methods.
    """

    def __init__(self):
        """
        Initialize the base step view.
        """
        super().__init__()
        self.parent_style = self.style()
        self.main_layout = QVBoxLayout(self)

    def get_header_title(self) -> str:
        """Return the title displayed in the wizard header for this step."""
        return ""

    def _create_settings_icon(self) -> QIcon:
        """Create an SVG gear icon coloured to match the current theme."""
        fill_color = self._get_theme_icon_color()

        # Material-design style gear-icon path; kept as a single `d` string
        # because SVG path data has no meaningful line-break boundaries.
        gear_path = (
            "M12 15.5A3.5 3.5 0 0 1 8.5 12A3.5 3.5 0 0 1 12 8.5a3.5 3.5 0 0 1"
            " 3.5 3.5a3.5 3.5 0 0 1-3.5 3.5m7.43-2.53c.04-.32.07-.64.07-.97"
            "c0-.33-.03-.66-.07-1l2.11-1.63c.19-.15.24-.42.12-.64l-2-3.46"
            "c-.12-.22-.39-.3-.61-.22l-2.49 1c-.52-.39-1.06-.73-1.69-.98"
            "l-.37-2.65A.506.506 0 0 0 14 2h-4c-.25 0-.46.18-.5.42l-.37 2.65"
            "c-.63.25-1.17.59-1.69.98l-2.49-1c-.22-.08-.49 0-.61.22l-2 3.46"
            "c-.13.22-.07.49.12.64L4.57 11c-.04.34-.07.67-.07 1"
            "c0 .33.03.65.07.97l-2.11 1.66c-.19.15-.25.42-.12.64l2 3.46"
            "c.12.22.39.3.61.22l2.49-1.01c.52.4 1.06.74 1.69.99l.37 2.65"
            "c.04.24.25.42.5.42h4c.25 0 .46-.18.5-.42l.37-2.65"
            "c.63-.26 1.17-.59 1.69-.99l2.49 1.01c.22.08.49 0 .61-.22l2-3.46"
            "c.12-.22.07-.49-.12-.64l-2.11-1.66Z"
        )
        svg = (
            '<svg width="16" height="16" viewBox="0 0 24 24" fill="none"'
            ' xmlns="http://www.w3.org/2000/svg">'
            f'<path d="{gear_path}" fill="{fill_color}"/>'
            "</svg>"
        )
        pixmap = QPixmap()
        pixmap.loadFromData(QByteArray(svg.encode("utf-8")))
        return QIcon(pixmap)

    def _get_theme_icon_color(self) -> str:
        """Get icon color from QSS theme file (Icon: #xxxxxx in Base Colors comment)."""
        from ..utils.theme_manager import get_theme_manager

        return get_theme_manager().get_theme_color("Icon")

    def _create_electrode_legend_layout(self) -> QHBoxLayout:
        """Create the colour legend row for electrode contact states."""
        layout = QHBoxLayout()
        layout.addStretch(1)

        def legend_item(color: str, text: str, border: str) -> QWidget:
            w = QWidget()
            w.setStyleSheet("background-color: transparent;")
            row = QHBoxLayout(w)
            row.setContentsMargins(0, 0, 0, 0)
            swatch = QLabel()
            swatch.setFixedSize(16, 12)
            swatch.setStyleSheet(
                f"background-color: {color}; border: 1px solid {border};"
            )
            label = QLabel(text)
            row.addWidget(swatch)
            row.addSpacing(6)
            row.addWidget(label)
            return w

        layout.addWidget(legend_item("#969696", "OFF", "#333333"))
        layout.addSpacing(18)
        layout.addWidget(legend_item("#ff6464", "Anodic (+)", "#c83232"))
        layout.addSpacing(18)
        layout.addWidget(legend_item("#6496ff", "Cathodic (-)", "#3264c8"))
        layout.addStretch(1)
        return layout

    def refresh_theme_icons(self) -> None:
        """Refresh icons that depend on the current theme (call after theme toggle)."""
        # Auto-discover all settings buttons by objectName pattern
        for btn in self.findChildren(QPushButton):
            if btn.objectName() and "settings" in btn.objectName().lower():
                btn.setIcon(self._create_settings_icon())
