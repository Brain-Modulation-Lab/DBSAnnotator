"""
Step 0 view: Mode selection page.

This module contains the initial view where users choose between
full mode (with stimulation settings and scales) or annotations-only mode,
and provides access to longitudinal reporting.
"""

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QFrame,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QWidget,
)


class Step0View(QWidget):
    """
    Step 0: Mode selection view.

    Organized into two sections:
    - Session Notes: start a new annotation session (full or simple mode)
    - Longitudinal Data: create longitudinal reports from existing sessions
    """

    def __init__(self, parent=None):
        """Initialize the Step 0 view."""
        super().__init__(parent)
        self.main_layout = QVBoxLayout(self)
        self.main_layout.setContentsMargins(24, 16, 24, 16)
        self.main_layout.setSpacing(5)

        # ── Section 1: Session Notes ──────────────────────────────
        section1_label = QLabel("New session")
        section1_label.setObjectName("step0_section_title")
        section1_label.setAlignment(
            Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter
        )
        self.main_layout.addWidget(section1_label)

        # Buttons row for session notes
        notes_buttons_layout = QHBoxLayout()
        notes_buttons_layout.setAlignment(Qt.AlignmentFlag.AlignCenter)
        notes_buttons_layout.setSpacing(30)

        # Full mode button
        self.full_mode_button = QPushButton("Complete workflow")
        self.full_mode_button.setObjectName("full_mode_button")
        self.full_mode_button.setCursor(Qt.CursorShape.PointingHandCursor)
        notes_buttons_layout.addWidget(self.full_mode_button)

        # Annotations only button
        self.annotations_only_button = QPushButton("Annotation-only workflow")
        self.annotations_only_button.setObjectName("annotations_only_button")
        self.annotations_only_button.setCursor(Qt.CursorShape.PointingHandCursor)
        notes_buttons_layout.addWidget(self.annotations_only_button)

        self.main_layout.addLayout(notes_buttons_layout)

        # ── Separator ─────────────────────────────────────────────
        separator = QFrame()
        separator.setFrameShape(QFrame.Shape.HLine)
        separator.setFrameShadow(QFrame.Shadow.Sunken)
        self.main_layout.addWidget(separator)

        # ── Section 2: Longitudinal Data ──────────────────────────
        section2_label = QLabel("Longitudinal Report")
        section2_label.setObjectName("step0_section_title")
        section2_label.setAlignment(
            Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter
        )
        self.main_layout.addWidget(section2_label)

        # Longitudinal report button
        longitudinal_buttons_layout = QHBoxLayout()
        longitudinal_buttons_layout.setAlignment(Qt.AlignmentFlag.AlignCenter)
        # longitudinal_buttons_layout.setSpacing(10)

        self.longitudinal_report_button = QPushButton("Create Longitudinal Report")
        self.longitudinal_report_button.setObjectName("longitudinal_report_button")
        self.longitudinal_report_button.setCursor(Qt.CursorShape.PointingHandCursor)
        longitudinal_buttons_layout.addWidget(self.longitudinal_report_button)

        self.main_layout.addLayout(longitudinal_buttons_layout)

        # Add stretch to push content up
        self.main_layout.addStretch(1)

    def get_header_title(self) -> str:
        """Return the wizard header title for Step 0."""
        return "DBS Annotator"

    def get_header_subtitle(self) -> str:
        """Return the wizard header subtitle for Step 0."""
        return "Record and analyze deep brain stimulation programming sessions"
