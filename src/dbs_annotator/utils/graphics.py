"""
Graphics utility functions for UI components.

This module provides functions for creating icons, rounded images,
and button animations.
"""

from PySide6.QtCore import QByteArray, QRectF, Qt, QTimer
from PySide6.QtGui import QIcon, QPainter, QPainterPath, QPixmap

from ..config import BUTTON_PULSE_COUNT, BUTTON_PULSE_DURATION


def create_arrow_icon(direction: str = "up", double: bool = False) -> QIcon:
    """
    Create an arrow icon for increment/decrement buttons.

    Args:
        direction: Arrow direction, either "up" or "down"
        double: If True, creates a double arrow (for larger steps)

    Returns:
        QIcon containing the arrow graphic
    """
    arrow_color = "#cccccc"

    if double:
        if direction == "up":
            svg = f"""
            <svg width="16" height="16" viewBox="0 0 18 18" fill="none">
                <polygon points="4,12 9,7 14,12" fill="{arrow_color}"/>
                <polygon points="4,16 9,11 14,16" fill="{arrow_color}"/>
            </svg>
            """
        else:  # down
            svg = f"""
            <svg width="16" height="16" viewBox="0 0 18 18" fill="none">
                <polygon points="4,6 9,11 14,6" fill="{arrow_color}"/>
                <polygon points="4,2 9,7 14,2" fill="{arrow_color}"/>
            </svg>
            """
    else:
        if direction == "up":
            svg = f"""
            <svg width="16" height="16" viewBox="0 0 18 18" fill="none">
                <polygon points="4,16 9,11 14,16" fill="{arrow_color}"/>
            </svg>
            """
        else:  # down
            svg = f"""
            <svg width="16" height="16" viewBox="0 0 18 18" fill="none">
                <polygon points="4,2 9,7 14,2" fill="{arrow_color}"/>
            </svg>
            """

    pixmap = QPixmap()
    pixmap.loadFromData(QByteArray(svg.encode("utf-8")))
    return QIcon(pixmap)


def rounded_pixmap(pixmap: QPixmap, radius: int) -> QPixmap:
    """
    Create a rounded version of a pixmap.

    Args:
        pixmap: The original pixmap
        radius: Corner radius in pixels

    Returns:
        New pixmap with rounded corners
    """
    size = pixmap.size()
    rounded = QPixmap(size)
    rounded.fill(Qt.GlobalColor.transparent)

    painter = QPainter(rounded)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)

    path = QPainterPath()
    path.addRoundedRect(QRectF(0, 0, size.width(), size.height()), radius, radius)

    painter.setClipPath(path)
    painter.drawPixmap(0, 0, pixmap)
    painter.end()

    return rounded


def animate_button(button, pulse_count: int = BUTTON_PULSE_COUNT) -> None:
    """
    Animate a button with a pulsing effect.

    This is typically used to provide visual feedback after an action,
    such as inserting data.

    Args:
        button: QPushButton to animate
        pulse_count: Number of times to pulse the button
    """
    normal_style = button.styleSheet()
    orange_style = "background-color: #ff6600; color: black;"

    def pulse(times_left: int) -> None:
        """Recursive function to create pulse effect."""
        if times_left == 0:
            button.setStyleSheet(normal_style)
            return

        button.setStyleSheet(orange_style)
        QTimer.singleShot(
            BUTTON_PULSE_DURATION,
            lambda: (
                button.setStyleSheet(normal_style),
                QTimer.singleShot(BUTTON_PULSE_DURATION, lambda: pulse(times_left - 1)),
            ),
        )

    pulse(pulse_count)
