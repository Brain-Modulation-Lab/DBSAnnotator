"""
Responsive design utilities for adaptive UI scaling.

This module provides functions to scale UI elements based on screen DPI
and resolution, ensuring consistent appearance across different displays.
"""

from PySide6.QtWidgets import QApplication


def get_dpi_scale() -> float:
    """
    Get the DPI scaling factor for the current screen.

    Returns:
        float: DPI scale factor (1.0 = 96 DPI, 1.5 = 144 DPI, etc.)
    """
    app = QApplication.instance()
    if app is None:
        return 1.0

    screen = app.primaryScreen()
    if screen is None:
        return 1.0

    logical_dpi = screen.logicalDotsPerInch()
    base_dpi = 96  # Standard DPI
    return logical_dpi / base_dpi


def scale_value(value: int | float, dpi_scale: float = None) -> int:
    """
    Scale a value based on DPI.

    Args:
        value: Original value to scale
        dpi_scale: Optional DPI scale factor. If None, auto-detected.

    Returns:
        int: Scaled value
    """
    if dpi_scale is None:
        dpi_scale = get_dpi_scale()

    return int(value * dpi_scale)


def scale_font_size(base_size: int, dpi_scale: float = None) -> int:
    """
    Scale font size based on DPI, with reasonable limits.

    Args:
        base_size: Base font size in points
        dpi_scale: Optional DPI scale factor. If None, auto-detected.

    Returns:
        int: Scaled font size (minimum 8pt, maximum 24pt)
    """
    if dpi_scale is None:
        dpi_scale = get_dpi_scale()

    scaled = int(base_size * dpi_scale)
    return max(8, min(24, scaled))  # Clamp between 8-24pt


def get_responsive_stylesheet_variables(dpi_scale: float = None) -> dict:
    """
    Get stylesheet variables for responsive design.

    Args:
        dpi_scale: Optional DPI scale factor. If None, auto-detected.

    Returns:
        dict: Dictionary of CSS variable values
    """
    if dpi_scale is None:
        dpi_scale = get_dpi_scale()

    return {
        "font_size_small": f"{scale_font_size(10, dpi_scale)}pt",
        "font_size_normal": f"{scale_font_size(12, dpi_scale)}pt",
        "font_size_large": f"{scale_font_size(14, dpi_scale)}pt",
        "font_size_title": f"{scale_font_size(20, dpi_scale)}pt",
        "padding": f"{scale_value(6, dpi_scale)}px",
        "margin": f"{scale_value(10, dpi_scale)}px",
        "border_radius": f"{scale_value(4, dpi_scale)}px",
    }


def apply_responsive_size_policy(widget, min_width: int = None, min_height: int = None):
    """
    Apply responsive size policy to a widget.

    Args:
        widget: QWidget to apply policy to
        min_width: Minimum width in pixels (scaled by DPI)
        min_height: Minimum height in pixels (scaled by DPI)
    """
    dpi_scale = get_dpi_scale()

    if min_width is not None:
        widget.setMinimumWidth(scale_value(min_width, dpi_scale))

    if min_height is not None:
        widget.setMinimumHeight(scale_value(min_height, dpi_scale))
