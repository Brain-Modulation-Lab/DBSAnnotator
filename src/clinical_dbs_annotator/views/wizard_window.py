"""
Main wizard window for the Clinical DBS Annotator application.

This module contains the main window that manages the wizard flow,
navigation, and coordinates views with the controller.
"""

import os
import typing

from PySide6.QtCore import QSize, Qt
from PySide6.QtGui import QIcon, QPixmap
from PySide6.QtWidgets import (
    QDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPushButton,
    QScrollArea,
    QSizePolicy,
    QSpacerItem,
    QStackedWidget,
    QStyle,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from ..config import (
    APP_NAME,
    APP_VERSION,
    BASE_DPI,
    CLINICAL_SCALES_PRESETS,
    FONT_SCALE_ENABLED,
    ICON_FILENAME,
    ICONS_DIR,
    RESPONSIVE_WINDOW_RATIOS,
    SCREEN_SIZE_THRESHOLDS,
    WINDOW_MAX_SIZE_RATIO,
    WINDOW_MIN_SIZE,
    WINDOW_SIZE_RATIO,
)
from ..controllers import WizardController
from ..utils import get_theme_manager, resource_path, rounded_pixmap
from .annotations_simple_view import AnnotationsFileView, AnnotationsSessionView
from .longitudinal_file_view import LongitudinalFileView
from .step0_view import Step0View
from .step1_view import Step1View
from .step2_view import Step2View
from .step3_view import Step3View


class WizardWindow(QWidget):
    """
    Main window for the annotation wizard.

    This window manages:
    - Multi-step wizard interface
    - Navigation between steps
    - Controller integration
    - Window configuration and styling
    """

    def __init__(self, app):
        """
        Initialize the wizard window.

        Args:
            app: QApplication instance for screen geometry
        """
        super().__init__()
        self.app = app
        self.controller = WizardController()
        self.current_step = 0
        self.workflow_mode = None  # "full" or "annotations_only"

        # Load logo
        logo_path = resource_path(os.path.join(ICONS_DIR, ICON_FILENAME))
        self.logo_pixmap = QPixmap(logo_path)

        self._setup_window()
        self._setup_ui()
        self._update_ui_state()

    def _setup_window(self) -> None:
        """Configure the main window properties with responsive sizing."""
        self.setWindowTitle(f"{APP_NAME} {APP_VERSION}")

        # Set window icon
        icon_path = resource_path(os.path.join(ICONS_DIR, ICON_FILENAME))
        self.setWindowIcon(QIcon(icon_path))

        # Get screen geometry and DPI
        screen = self.app.primaryScreen()
        rect = screen.availableGeometry()
        screen_width = rect.width()
        screen_height = rect.height()

        # Get logical DPI for font scaling
        logical_dpi = screen.logicalDotsPerInch()
        self.dpi_scale = logical_dpi / BASE_DPI if FONT_SCALE_ENABLED else 1.0

        # Determine screen size category for responsive design
        if screen_width < SCREEN_SIZE_THRESHOLDS["small"]:
            size_category = "small"
        elif screen_width < SCREEN_SIZE_THRESHOLDS["medium"]:
            size_category = "medium"
        else:
            size_category = "large"

        # Get responsive ratios based on screen size
        ratios = RESPONSIVE_WINDOW_RATIOS[size_category]

        # Calculate desired window size with responsive ratios
        desired_width = int(screen_width * ratios["width"])
        desired_height = int(screen_height * ratios["height"])

        # Apply minimum size constraints
        width = max(desired_width, WINDOW_MIN_SIZE["width"])
        height = max(desired_height, WINDOW_MIN_SIZE["height"])

        # Apply maximum size constraints with margin for small screens
        margin = 100 if screen_width < SCREEN_SIZE_THRESHOLDS["small"] else 50
        max_width = min(width, screen_width - margin)
        max_height = min(height, screen_height - margin)
        width = min(width, max_width)
        height = min(height, max_height)

        # Apply maximum size ratios (prevent too large on big screens)
        max_width_ratio = int(screen_width * WINDOW_MAX_SIZE_RATIO["width"])
        max_height_ratio = int(screen_height * WINDOW_MAX_SIZE_RATIO["height"])
        width = min(width, max_width_ratio)
        height = min(height, max_height_ratio)

        # Calculate position (centered with bounds checking)
        x = max(0, min(int((screen_width - width) / 2), screen_width - width))
        y = max(0, min(int((screen_height - height) / 2), screen_height - height))

        # Set geometry and constraints
        self.setGeometry(x, y, width, height)
        self.setMinimumSize(WINDOW_MIN_SIZE["width"], WINDOW_MIN_SIZE["height"])

        # Make window resizable
        self.setWindowFlag(Qt.WindowMaximizeButtonHint, True)

        # Set smaller size for step 0 (mode selection)
        self._update_window_size_for_step0()

    def _setup_ui(self) -> None:
        """Set up the main UI layout."""
        main_layout = QVBoxLayout(self)

        # Header row (title + theme/help)
        header_layout = self._create_header()
        main_layout.addLayout(header_layout)

        # Create stacked widget for steps
        self.stack = QStackedWidget(self)
        self.stack.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Minimum)

        self.stack.currentChanged.connect(lambda _: self._update_ui_state())

        # Create Step 0 - Mode selection
        self.step0_view = Step0View(self)
        self.stack.addWidget(self.step0_view)
        self._connect_step0_signals()

        # Full workflow views (lazy loaded)
        self.step1_view = None
        self.step2_view = None
        self.step3_view = None

        # Annotations-only workflow views (lazy loaded)
        self.annotations_file_view = None
        self.annotations_session_view = None

        # Longitudinal workflow view (lazy loaded)
        self.longitudinal_file_view = None

        self.stack_scroll_area = QScrollArea(self)
        self.stack_scroll_area.setWidgetResizable(True)
        self.stack_scroll_area.setFrameShape(QFrame.NoFrame)
        self.stack_scroll_area.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.stack_scroll_area.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        self.stack_scroll_area.setWidget(self.stack)
        main_layout.addWidget(self.stack_scroll_area)

        # Add a spacer that can shrink/grow to help with resizing
        spacer = QSpacerItem(20, 20, QSizePolicy.Minimum, QSizePolicy.Minimum)
        main_layout.addItem(spacer)

        # Navigation bar
        nav_layout = self._create_nav_bar()
        main_layout.addLayout(nav_layout)

    def _create_header(self) -> QHBoxLayout:
        """
        Create header with theme toggle button.

        Returns:
            QHBoxLayout containing header elements
        """
        header_layout = QHBoxLayout()

        # Left: logo + title
        self.header_logo_label = QLabel()
        if not self.logo_pixmap.isNull():
            logo = self.logo_pixmap.scaledToWidth(34, Qt.SmoothTransformation)
            logo = rounded_pixmap(logo, 5)
            self.header_logo_label.setPixmap(logo)
        self.header_logo_label.setAlignment(Qt.AlignVCenter | Qt.AlignLeft)
        header_layout.addWidget(self.header_logo_label)

        # Title and subtitle container
        title_container = QVBoxLayout()
        title_container.setSpacing(0)  # Ridotto spacing tra titolo e sottotitolo
        title_container.setContentsMargins(0, 2, 0, 0)  # Margini più stretti

        self.header_title_label = QLabel("")
        self.header_title_label.setStyleSheet("font-size: 12pt; font-weight: 500;")
        self.header_title_label.setAlignment(Qt.AlignLeft | Qt.AlignVCenter)
        title_container.addWidget(self.header_title_label)

        self.header_subtitle_label = QLabel("")
        self.header_subtitle_label.setStyleSheet("font-size: 8pt; color: #64748b; margin-top: -2px;")
        self.header_subtitle_label.setAlignment(Qt.AlignLeft | Qt.AlignVCenter)
        title_container.addWidget(self.header_subtitle_label)

        header_layout.addLayout(title_container)
        header_layout.addStretch()  # Push buttons to the right

        # Theme toggle button
        self.theme_toggle_btn = QPushButton()
        self.theme_toggle_btn.setObjectName("theme_toggle")
        self.theme_toggle_btn.setToolTip("Switch between Dark and Light mode")
        self.theme_toggle_btn.setCursor(Qt.PointingHandCursor)
        self._update_theme_button_icon()

        self.theme_toggle_btn.clicked.connect(self._toggle_theme)

        header_layout.addWidget(self.theme_toggle_btn)

        # Info button
        self.info_btn = QPushButton()
        self.info_btn.setObjectName("info_button")
        self.info_btn.setToolTip("Info / Help")
        self.info_btn.setCursor(Qt.PointingHandCursor)
        self.info_btn.setText("Help")
        self.info_btn.clicked.connect(self._show_info_dialog)
        header_layout.addWidget(self.info_btn)

        return header_layout

    def _get_current_header_title(self) -> str:
        """Return the header title string for the currently visible view."""
        current = self.stack.currentWidget() if hasattr(self, "stack") else None
        if current is None:
            return ""

        if hasattr(current, "get_header_title"):
            try:
                return str(current.get_header_title() or "")
            except Exception:
                return ""

        # Fallbacks for non-BaseStepView screens
        if isinstance(current, Step0View):
            return ""
        if isinstance(current, AnnotationsFileView):
            return "Output File"
        if isinstance(current, AnnotationsSessionView):
            return "Session Annotations"
        if isinstance(current, LongitudinalFileView):
            return "Longitudinal Report"
        return ""

    def _get_current_header_subtitle(self) -> str:
        """Return the header subtitle string for the currently visible view."""
        current = self.stack.currentWidget() if hasattr(self, "stack") else None
        if current is None:
            return ""

        if hasattr(current, "get_header_subtitle"):
            try:
                return str(current.get_header_subtitle() or "")
            except Exception:
                return ""

        # No subtitle fallbacks for other views
        return ""

    def _update_header_title(self) -> None:
        """Refresh the header title and subtitle labels to match the active view."""
        if not hasattr(self, "header_title_label"):
            return
        self.header_title_label.setText(self._get_current_header_title())

        if hasattr(self, "header_subtitle_label"):
            subtitle = self._get_current_header_subtitle()
            self.header_subtitle_label.setText(subtitle)
            self.header_subtitle_label.setVisible(bool(subtitle))  # Hide if empty

    def _update_theme_button_icon(self) -> None:
        """Update the theme toggle button icon based on current theme."""
        theme_manager = get_theme_manager()
        theme_manager.get_current_theme()

        # Show the icon for what the button will switch TO
        # (opposite of current theme)
        if theme_manager.is_dark_mode():
            self.theme_toggle_btn.setText("☀")  # Sun = will switch to light
        else:
            self.theme_toggle_btn.setText("🌙")  # Moon = will switch to dark

    def _show_info_dialog(self) -> None:
        """Show application info dialog with help and contact information."""
        dialog = QDialog(self)
        dialog.setWindowTitle("About Clinical DBS Annotator")
        dialog.setMinimumSize(600, 500)
        dialog.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)

        layout = QVBoxLayout(dialog)

        # Title and version
        title_label = QLabel(f"<h2>{APP_NAME} v{APP_VERSION}</h2>")
        title_label.setAlignment(Qt.AlignCenter)
        layout.addWidget(title_label)

        # Description
        desc_text = QTextEdit()
        desc_text.setReadOnly(True)
        desc_text.setHtml("""
        <h3>About this application</h3>
        <p>Clinical DBS Annotator is a specialized tool for clinicians and researchers
        working with Deep Brain Stimulation (DBS) systems. This application provides:</p>
        <ul>
            <li>Interactive electrode visualization and configuration</li>
            <li>Clinical scale assessment and tracking</li>
            <li>Session annotation and management</li>
            <li>Export functionality for clinical documentation</li>
        </ul>
        <h3>Key Features</h3>
        <ul>
            <li><b>Electrode Modeling:</b> Support for various DBS lead models with directional contacts</li>
            <li><b>Stimulation Configuration:</b> Visual interface for setting stimulation parameters</li>
            <li><b>Clinical Assessment:</b> Standardized clinical scales (UPDRS, Y-BOCS, HAM-D, etc.)</li>
            <li><b>Session Management:</b> Track patient sessions over time with detailed annotations</li>
            <li><b>Export Capabilities:</b> Generate clinical reports in multiple formats</li>
        </ul>
        <h3>Getting Started</h3>
        <ol>
            <li>Select your workflow mode (Full or Annotations Only)</li>
            <li>Choose the electrode model being used</li>
            <li>Configure stimulation parameters using the interactive electrode viewer</li>
            <li>Complete clinical assessments as needed</li>
            <li>Add session annotations and notes</li>
            <li>Export your session data for documentation</li>
        </ol>

        <h3>Support & Contact</h3>
        <p><b>GitHub Repository:</b> <a href='https://github.com/your-username/clinical-dbs-annotator'>https://github.com/your-username/clinical-dbs-annotator</a></p>
        <p>For bug reports, feature requests, or general support, please visit our GitHub repository
        or contact Lucia Poma directly at</b> <a href='mailto:lucia.poma@wysscenter.ch'>lucia.poma@wysscenter.ch</a></p>.

        <h3>License</h3>
        <p>This software is released under an open-source license. Please see the GitHub repository
        for detailed licensing information.</p>
        """)

        layout.addWidget(desc_text)

        # Close button
        button_layout = QHBoxLayout()
        button_layout.addStretch()
        close_btn = QPushButton("Close")
        close_btn.setMinimumWidth(100)
        close_btn.clicked.connect(dialog.accept)
        button_layout.addWidget(close_btn)
        layout.addLayout(button_layout)

        dialog.exec()

    def _toggle_theme(self) -> None:
        """Toggle between dark and light themes."""
        theme_manager = get_theme_manager()
        theme_manager.toggle_theme(self.app)
        self._update_theme_button_icon()
        # Refresh theme-dependent icons in step1 and step2
        if self.step1_view is not None:
            self.step1_view.refresh_theme_icons()
        if self.step2_view is not None:
            self.step2_view.refresh_theme_icons()

    def _connect_step0_signals(self) -> None:
        """Connect Step 0 mode selection signals."""
        self.step0_view.full_mode_button.clicked.connect(self._select_full_mode)
        self.step0_view.annotations_only_button.clicked.connect(self._select_annotations_only_mode)
        self.step0_view.longitudinal_report_button.clicked.connect(self._select_longitudinal_report)

    def _select_full_mode(self) -> None:
        """Handle selection of full workflow mode."""
        self.workflow_mode = "full"
        self.current_step = 1
        self._load_full_workflow_views()
        self.stack.setCurrentWidget(self.step1_view)
        self._update_window_size_for_main_workflow()  # Resize to normal size
        self._update_ui_state()

    def _select_annotations_only_mode(self) -> None:
        """Handle selection of annotations-only workflow mode."""
        self.workflow_mode = "annotations_only"
        self.current_step = 1
        self._load_annotations_only_views()
        self.stack.setCurrentWidget(self.annotations_file_view)
        self._update_window_size_for_main_workflow()  # Resize to normal size
        self._update_ui_state()

    def _select_longitudinal_report(self) -> None:
        """Handle selection of longitudinal report mode."""
        self.workflow_mode = "longitudinal"
        self.current_step = 1
        self._load_longitudinal_views()
        self.stack.setCurrentWidget(self.longitudinal_file_view)
        self._update_window_size_for_main_workflow()
        self._update_ui_state()

    def _load_longitudinal_views(self) -> None:
        """Load longitudinal workflow views (lazy loading)."""
        if self.longitudinal_file_view is None:
            self.longitudinal_file_view = LongitudinalFileView(self)
            self.stack.addWidget(self.longitudinal_file_view)
            self._connect_longitudinal_signals()

    def _connect_longitudinal_signals(self) -> None:
        """Connect signals for the longitudinal file view."""
        self.longitudinal_file_view.export_word_action.triggered.connect(
            lambda: self._export_longitudinal_report("word")
        )
        self.longitudinal_file_view.export_pdf_action.triggered.connect(
            lambda: self._export_longitudinal_report("pdf")
        )

    def _export_longitudinal_report(self, fmt: str) -> None:
        """Handle longitudinal report export (Word or PDF)."""
        files = self.longitudinal_file_view.get_loaded_files()
        if not files:
            QMessageBox.warning(
                self, "No Files",
                "Please load at least one annotation file before creating a report.",
            )
            return

        # Extract session scales from all files
        scales = LongitudinalFileView.extract_session_scales_from_files(files)
        if not scales:
            QMessageBox.warning(
                self, "No Session Scales",
                "No session scales (is_initial=0) were found in the loaded files.\n"
                "The report cannot determine the best entry without scale data.",
            )
            return

        # Show scale optimization dialog
        from .longitudinal_scale_dialog import (
            LongitudinalScaleDialog,
            ReportSectionsDialog,
        )
        dialog = LongitudinalScaleDialog(scales, self)
        if dialog.exec() != QDialog.Accepted:
            return

        prefs = dialog.get_scale_prefs()

        # Show section selection dialog
        section_defs = [
            ("sessions_overview", "Sessions Overview", True),
            ("session_data", "Session Data", True),
            ("electrode_config", "Electrode Configuration", False),
            ("programming_summary", "Programming Summary", False),
        ]
        sec_dialog = ReportSectionsDialog(section_defs, self, title="Report Sections")
        if sec_dialog.exec() != QDialog.Accepted:
            return
        sections = sec_dialog.get_selected_sections()

        # Generate report
        self.controller.export_longitudinal_report(
            file_paths=files,
            scale_prefs=prefs,
            fmt=fmt,
            parent_widget=self,
            sections=sections,
        )

    def _load_full_workflow_views(self) -> None:
        """Load full workflow views (lazy loading)."""
        if self.step1_view is None:
            from .step1_view import Step1View
            self.step1_view = Step1View(self.style())
            self.stack.addWidget(self.step1_view)
            self._connect_step1_signals()

        if self.step2_view is None:
            from .step2_view import Step2View
            self.step2_view = Step2View(self.style())
            self.stack.addWidget(self.step2_view)
            self._connect_step2_signals()

        if self.step3_view is None:
            from .step3_view import Step3View
            self.step3_view = Step3View(self.style())
            self.stack.addWidget(self.step3_view)
            self._connect_step3_signals()

    def _load_annotations_only_views(self) -> None:
        """Load annotations-only workflow views (lazy loading)."""
        if self.annotations_file_view is None:
            from .annotations_simple_view import AnnotationsFileView
            self.annotations_file_view = AnnotationsFileView(self)
            self.stack.addWidget(self.annotations_file_view)
            self._connect_annotations_file_signals()

        if self.annotations_session_view is None:
            from .annotations_simple_view import AnnotationsSessionView
            self.annotations_session_view = AnnotationsSessionView(self)
            self.stack.addWidget(self.annotations_session_view)
            self._connect_annotations_session_signals()

    def _update_window_size_for_step0(self) -> None:
        """Set smaller window size for mode selection (step 0)."""
        compact_width = 620
        compact_height = 340

        # Reset constraints first to avoid min/max conflicts with previous size
        self.setMinimumSize(1, 1)
        self.setMaximumSize(16777215, 16777215)

        # Force stack to reset its size - critical for preventing button shift from view1
        if hasattr(self, "stack"):
            self.stack.setSizePolicy(QSizePolicy.Fixed, QSizePolicy.Fixed)
            self.stack.setFixedWidth(compact_width - 40)  # Account for margins
            self.stack.setFixedHeight(compact_height - 100)  # Prevent vertical scrollbar
            self.stack.adjustSize()
        if hasattr(self, "stack_scroll_area"):
            self.stack_scroll_area.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)

        # Center the compact window on screen
        screen = self.app.primaryScreen()
        screen_geometry = screen.availableGeometry()
        x = int((screen_geometry.width() - compact_width) / 2)
        y = int((screen_geometry.height() - compact_height) / 2)

        self.setGeometry(x, y, compact_width, compact_height)
        self.setMinimumSize(compact_width, compact_height)
        self.setMaximumSize(compact_width, compact_height)

    def _update_window_size_for_main_workflow(self) -> None:
        """Restore normal window size for main workflow (steps 1+)."""
        # Restore normal size policies and remove fixed constraints from step0
        if hasattr(self, "stack"):
            self.stack.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Minimum)
            self.stack.setMaximumWidth(16777215)  # Remove fixed width
            self.stack.setMaximumHeight(16777215)  # Remove fixed height
        if hasattr(self, "stack_scroll_area"):
            self.stack_scroll_area.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)

        # Get original normal size
        screen = self.app.primaryScreen()
        rect = screen.availableGeometry()
        screen_width = rect.width()
        screen_height = rect.height()

        # Calculate desired window size with ratio
        desired_width = int(screen_width * WINDOW_SIZE_RATIO["width"])
        desired_height = int(screen_height * WINDOW_SIZE_RATIO["height"])

        # Apply minimum size constraints
        width = max(desired_width, WINDOW_MIN_SIZE["width"])
        height = max(desired_height, WINDOW_MIN_SIZE["height"])

        # Center the normal window
        x = int((screen_width - width) / 2)
        y = int((screen_height - height) / 2)

        # Reset constraints first to avoid min/max conflicts
        self.setMinimumSize(1, 1)
        self.setMaximumSize(16777215, 16777215)  # Qt max size

        # Apply new geometry and constraints (allow full maximization)
        self.setGeometry(x, y, width, height)
        self.setMinimumSize(WINDOW_MIN_SIZE["width"], WINDOW_MIN_SIZE["height"])
        self.setMaximumSize(screen_width, screen_height)  # Allow full screen maximization

        self._clamp_to_screen()

    def _clamp_to_screen(self) -> None:
        """Ensure the window stays within the available screen area."""
        if getattr(self, "_is_clamping", False):
            return
        self._is_clamping = True
        try:
            screen = self.app.screenAt(self.frameGeometry().center()) or self.app.primaryScreen()
            rect = screen.availableGeometry()
            geo = self.geometry()

            width = min(geo.width(), rect.width())
            height = min(geo.height(), rect.height())

            x = min(max(geo.x(), rect.x()), rect.x() + rect.width() - width)
            y = min(max(geo.y(), rect.y()), rect.y() + rect.height() - height)

            if (x, y, width, height) != (geo.x(), geo.y(), geo.width(), geo.height()):
                self.setGeometry(x, y, width, height)
        finally:
            self._is_clamping = False

    @typing.override
    def resizeEvent(self, event):
        """Re-clamp to screen on every resize."""
        super().resizeEvent(event)
        self._clamp_to_screen()

    @typing.override
    def moveEvent(self, event):
        """Re-clamp to screen on every move."""
        super().moveEvent(event)
        self._clamp_to_screen()

    def _connect_step1_signals(self) -> None:
        """Connect Step 1 view signals to controller."""
        # Connect preset buttons
        for preset_name in CLINICAL_SCALES_PRESETS.keys():
            btn = self.step1_view.get_preset_button(preset_name)
            if btn:
                btn.clicked.connect(
                    lambda checked, name=preset_name: self.controller.apply_clinical_preset(
                        name, self.step1_view
                    )
                )

        # Initialize empty clinical scales
        self.step1_view.update_clinical_scales(
            [],
            on_add_callback=lambda: self.controller.on_add_clinical_scale(
                self.step1_view
            ),
            on_remove_callback=lambda row: self.controller.on_remove_clinical_scale(
                self.step1_view, row
            ),
        )

        # Connect next button
        self.step1_view.next_button.clicked.connect(self._go_to_step2)

    def _connect_step2_signals(self) -> None:
        """Connect Step 2 view signals to controller."""
        self.controller.prepare_step2(self.step2_view)
        self.step2_view.next_button.clicked.connect(self._go_to_step3)

    def _connect_step3_signals(self) -> None:
        """Connect Step 3 view signals to controller."""
        self.controller.prepare_step3(self.step3_view)
        self.step3_view.insert_button.clicked.connect(
            lambda: self.controller.insert_session_row(self.step3_view)
        )
        self.step3_view.close_button.clicked.connect(
            lambda: self.controller.close_session(self)
        )
        self.step3_view.export_word_action.triggered.connect(
            lambda: self._export_session_report("word")
        )
        self.step3_view.export_pdf_action.triggered.connect(
            lambda: self._export_session_report("pdf")
        )

    def _export_session_report(self, fmt: str) -> None:
        """Show scale optimization dialog then export Step 3 session report."""
        # Collect scale definitions from the controller
        scales = list(getattr(self.controller, "session_scales_data", []))
        if not scales:
            # No scales defined — export without optimization
            if fmt == "word":
                self.controller.export_session_word(self)
            else:
                self.controller.export_session_pdf(self)
            return

        from .longitudinal_scale_dialog import ScaleOptimizationDialog
        dialog = ScaleOptimizationDialog(
            scales, self, title="Scale Optimization — Session Report"
        )
        if dialog.exec() != QDialog.Accepted:
            return

        prefs = dialog.get_scale_prefs()

        # Show section selection dialog
        from .longitudinal_scale_dialog import ReportSectionsDialog
        section_defs = [
            ("initial_notes", "Initial Clinical Notes", True),
            ("session_data", "Session Data", True),
            ("electrode_config", "Electrode Configurations", True),
            ("programming_summary", "Programming Summary", True),
        ]
        sec_dialog = ReportSectionsDialog(section_defs, self, title="Report Sections")
        if sec_dialog.exec() != QDialog.Accepted:
            return
        sections = sec_dialog.get_selected_sections()

        if fmt == "word":
            self.controller.export_session_word(self, scale_prefs=prefs, sections=sections)
        else:
            self.controller.export_session_pdf(self, scale_prefs=prefs, sections=sections)

    def _create_nav_bar(self) -> QHBoxLayout:
        """
        Create the navigation bar with back button.

        Returns:
            QHBoxLayout containing navigation controls
        """
        nav_layout = QHBoxLayout()

        self.back_button = QPushButton("Back")
        self.back_button.setIcon(self.style().standardIcon(QStyle.SP_ArrowBack))
        self.back_button.setIconSize(QSize(22, 22))
        self.back_button.setFixedWidth(140)
        self.back_button.clicked.connect(self._go_back)

        nav_layout.addWidget(self.back_button)
        nav_layout.addStretch()

        self._nav_right_container = QWidget()
        self._nav_right_layout = QHBoxLayout(self._nav_right_container)
        self._nav_right_layout.setContentsMargins(0, 0, 0, 0)
        self._nav_right_layout.setSpacing(8)
        nav_layout.addWidget(self._nav_right_container)

        return nav_layout

    def _clear_nav_right(self) -> None:
        """Remove all widgets from the right side of the navigation bar."""
        if not hasattr(self, "_nav_right_layout"):
            return

        while self._nav_right_layout.count():
            item = self._nav_right_layout.takeAt(0)
            w = item.widget()
            if w is not None:
                w.setParent(None)

    def _refresh_nav_right(self) -> None:
        """Populate the nav-bar right side with the active view's action buttons."""
        self._clear_nav_right()

        current = self.stack.currentWidget()
        if current is None:
            return

        widgets = []
        if hasattr(current, "next_button"):
            widgets.append(current.next_button)

        if hasattr(current, "insert_button"):
            widgets.append(current.insert_button)

        if hasattr(current, "export_button"):
            widgets.append(current.export_button)

        if hasattr(current, "close_button"):
            widgets.append(current.close_button)

        for w in widgets:
            if w is not None:
                self._nav_right_layout.addWidget(w)

    def _go_to_step1(self) -> None:
        """Navigate to Step 1 (full workflow)."""
        # Create Step 1 if needed
        if self.step1_view is None:
            self.step1_view = Step1View(self.style())
            self.stack.addWidget(self.step1_view)
            self._connect_step1_signals()

        self.current_step = 1
        self.stack.setCurrentWidget(self.step1_view)
        self._update_ui_state()

    def _go_to_annotations_file(self) -> None:
        """Navigate to annotations file selection (annotations-only workflow)."""
        # Create annotations file view if needed
        if self.annotations_file_view is None:
            self.annotations_file_view = AnnotationsFileView(self)
            self.stack.addWidget(self.annotations_file_view)
            self._connect_annotations_file_signals()

        self.current_step = 1  # First step after mode selection
        self.stack.setCurrentWidget(self.annotations_file_view)
        self._update_ui_state()

    def _connect_annotations_file_signals(self) -> None:
        """Connect signals for annotations file view."""
        # Backward-compatible: older AnnotationsFileView exposed browse_button.
        # Newer UI manages file open/new internally.
        if hasattr(self.annotations_file_view, "browse_button"):
            self.annotations_file_view.browse_button.clicked.connect(
                lambda: self.controller.browse_save_location_simple(self.annotations_file_view, self)
            )
        self.annotations_file_view.next_button.clicked.connect(self._go_to_annotations_session)

    def _go_to_annotations_session(self) -> None:
        """Navigate to annotations session (annotations-only workflow)."""
        # Validate file info
        if not self.controller.validate_annotations_file(self.annotations_file_view, self):
            return

        # Create annotations session view if needed
        if self.annotations_session_view is None:
            self.annotations_session_view = AnnotationsSessionView(self)
            self.stack.addWidget(self.annotations_session_view)
            self._connect_annotations_session_signals()

        self.current_step = 2
        self.stack.setCurrentWidget(self.annotations_session_view)
        self._update_ui_state()

    def _connect_annotations_session_signals(self) -> None:
        """Connect signals for annotations session view."""
        self.annotations_session_view.insert_button.clicked.connect(
            lambda: self.controller.insert_simple_annotation(self.annotations_session_view)
        )
        self.annotations_session_view.close_button.clicked.connect(
            lambda: self.controller.close_session(self)
        )

        if hasattr(self.annotations_session_view, "export_word_action"):
            self.annotations_session_view.export_word_action.triggered.connect(
                lambda: self.controller.export_annotations_word(self)
            )
        if hasattr(self.annotations_session_view, "export_pdf_action"):
            self.annotations_session_view.export_pdf_action.triggered.connect(
                lambda: self.controller.export_annotations_pdf(self)
            )

    def _go_to_step2(self) -> None:
        """Navigate to Step 2 after validating Step 1."""
        if not self.controller.validate_step1(self.step1_view, self):
            return

        # Create Step 2 if needed
        if self.step2_view is None:
            self.step2_view = Step2View(self.style())
            self.stack.addWidget(self.step2_view)
            self._connect_step2_signals()

        self.current_step = 2
        self.stack.setCurrentWidget(self.step2_view)
        self._update_ui_state()

    def _go_to_step3(self) -> None:
        """Navigate to Step 3 after validating Step 2."""
        if not self.controller.validate_step2(self.step2_view):
            return

        # Create Step 3 if needed
        if self.step3_view is None:
            self.step3_view = Step3View(self.style())
            self.stack.addWidget(self.step3_view)
            self._connect_step3_signals()
            self._step3_prepared = True
        elif not getattr(self, '_step3_prepared', False):
            # Step 3 was created but preparation failed previously — retry
            try:
                self.controller.prepare_step3(self.step3_view)
                self._step3_prepared = True
            except Exception as e:
                print(f"[ERROR] prepare_step3 retry failed: {e}")
                import traceback
                traceback.print_exc()
        else:
            # Only refresh scales if definitions changed; keep everything else as-is
            self.controller.refresh_step3_scales(self.step3_view)

        self.current_step = 3
        self.stack.setCurrentWidget(self.step3_view)
        self._update_ui_state()

    def _go_back(self) -> None:
        """Navigate to the previous step."""
        if self.current_step > 0:
            self.current_step -= 1

            # Determine which widget to show based on workflow and step
            if self.current_step == 0:
                self.stack.setCurrentWidget(self.step0_view)
                self._update_window_size_for_step0()
            elif self.workflow_mode == "full":
                if self.current_step == 1 and self.step1_view:
                    self.stack.setCurrentWidget(self.step1_view)
                elif self.current_step == 2 and self.step2_view:
                    self.stack.setCurrentWidget(self.step2_view)
            elif self.workflow_mode == "annotations_only":
                if self.current_step == 1 and self.annotations_file_view:
                    self.stack.setCurrentWidget(self.annotations_file_view)
            elif self.workflow_mode == "longitudinal":
                pass  # Step 0 already handled above

            self._update_ui_state()

    def _update_ui_state(self) -> None:
        """Update UI elements based on current step."""
        if not hasattr(self, "back_button"):
            return
        self._update_header_title()
        # Hide back button completely on step 0 (mode selection)
        self.back_button.setVisible(self.current_step > 0)

        self._refresh_nav_right()
