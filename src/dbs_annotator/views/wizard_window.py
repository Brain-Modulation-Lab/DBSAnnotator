"""
Main wizard window for the DBS Annotator application.

This module contains the main window that manages the wizard flow,
navigation, and coordinates views with the controller.
"""

import html
import logging
import os
import typing
from typing import Protocol

from PySide6.QtCore import QSize, Qt, QTimer, QUrl
from PySide6.QtGui import QDesktopServices, QIcon, QPixmap
from PySide6.QtWidgets import (
    QAbstractButton,
    QCheckBox,
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
    APP_ISSUES_URL,
    APP_NAME,
    APP_REPOSITORY_URL,
    APP_VERSION,
    BASE_DPI,
    FONT_SCALE_ENABLED,
    ICON_FILENAME,
    ICONS_DIR,
    RESPONSIVE_WINDOW_RATIOS,
    SCREEN_SIZE_THRESHOLDS,
    UPDATE_FEEDBACK_EMAIL,
    WINDOW_MAX_SIZE_RATIO,
    WINDOW_MIN_SIZE,
    WINDOW_SIZE_RATIO,
)
from ..controllers import WizardController
from ..utils import get_theme_manager, resource_path, rounded_pixmap
from ..utils.scale_preset_manager import get_scale_preset_manager
from ..utils.updater import ReleaseInfo, UpdateChecker
from .annotation_only_view import AnnotationsFileView, AnnotationsSessionView
from .longitudinal_report_view import LongitudinalReportView as LongitudinalFileView
from .step0_view import Step0View
from .step1_view import Step1View
from .step2_view import Step2View
from .step3_view import Step3View

logger = logging.getLogger(__name__)


class _HeaderTitleProvider(Protocol):
    def get_header_title(self) -> str: ...


class _HeaderSubtitleProvider(Protocol):
    def get_header_subtitle(self) -> str: ...


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

        # Background update check. Runs once per cooldown window (24h by
        # default); offline / rate-limited failures are logged silently.
        self._update_checker = UpdateChecker(parent=self)
        self._update_checker.update_available.connect(self._on_update_available)
        # Defer slightly so the window is painted before any dialog appears.
        QTimer.singleShot(1500, self._run_deferred_update_check)

    def _run_deferred_update_check(self) -> None:
        """Background update check; skipped if user disabled automatic checks."""
        self._update_checker.check_async()

    def _setup_window(self) -> None:
        """Configure the main window properties with responsive sizing."""
        self.setWindowTitle(f"{APP_NAME} v{APP_VERSION}")

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
        self.setWindowFlag(Qt.WindowType.WindowMaximizeButtonHint, True)

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
        self.stack.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum
        )

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
        self.stack_scroll_area.setFrameShape(QFrame.Shape.NoFrame)
        self.stack_scroll_area.setHorizontalScrollBarPolicy(
            Qt.ScrollBarPolicy.ScrollBarAlwaysOff
        )
        self.stack_scroll_area.setVerticalScrollBarPolicy(
            Qt.ScrollBarPolicy.ScrollBarAsNeeded
        )
        self.stack_scroll_area.setWidget(self.stack)
        main_layout.addWidget(self.stack_scroll_area)

        # Add a spacer that can shrink/grow to help with resizing
        spacer = QSpacerItem(
            20, 20, QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Minimum
        )
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
            logo = self.logo_pixmap.scaledToWidth(
                34, Qt.TransformationMode.SmoothTransformation
            )
            logo = rounded_pixmap(logo, 5)
            self.header_logo_label.setPixmap(logo)
        self.header_logo_label.setAlignment(
            Qt.AlignmentFlag.AlignVCenter | Qt.AlignmentFlag.AlignLeft
        )
        header_layout.addWidget(self.header_logo_label)

        # Title and subtitle container
        title_container = QVBoxLayout()
        title_container.setSpacing(0)  # Ridotto spacing tra titolo e sottotitolo
        title_container.setContentsMargins(0, 2, 0, 0)  # Margini più stretti

        self.header_title_label = QLabel("")
        self.header_title_label.setStyleSheet("font-size: 12pt; font-weight: 500;")
        self.header_title_label.setAlignment(
            Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter
        )
        title_container.addWidget(self.header_title_label)

        self.header_subtitle_label = QLabel("")
        self.header_subtitle_label.setStyleSheet(
            "font-size: 8pt; color: #64748b; margin-top: -2px;"
        )
        self.header_subtitle_label.setAlignment(
            Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter
        )
        title_container.addWidget(self.header_subtitle_label)

        header_layout.addLayout(title_container)
        header_layout.addStretch()  # Push buttons to the right

        # Theme toggle button
        self.theme_toggle_btn = QPushButton()
        self.theme_toggle_btn.setObjectName("theme_toggle")
        self.theme_toggle_btn.setToolTip("Switch between Dark and Light mode")
        self.theme_toggle_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self._update_theme_button_icon()

        self.theme_toggle_btn.clicked.connect(self._toggle_theme)

        header_layout.addWidget(self.theme_toggle_btn)

        # Info button
        self.info_btn = QPushButton()
        self.info_btn.setObjectName("info_button")
        self.info_btn.setToolTip("Info / Help")
        self.info_btn.setCursor(Qt.CursorShape.PointingHandCursor)
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
                provider = typing.cast(_HeaderTitleProvider, current)
                return str(provider.get_header_title() or "")
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
                provider = typing.cast(_HeaderSubtitleProvider, current)
                return str(provider.get_header_subtitle() or "")
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
        dialog.setWindowTitle(f"About {APP_NAME}")
        dialog.setMinimumSize(600, 500)
        dialog.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)

        layout = QVBoxLayout(dialog)

        # Title and version
        title_label = QLabel(f"<h2>{APP_NAME} v{APP_VERSION}</h2>")
        title_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(title_label)

        # Description
        desc_text = QTextEdit()
        desc_text.setReadOnly(True)
        desc_text.setHtml(
            f"""
        <h3>About this application</h3>
        <p>DBS Annotator is a specialized tool for clinicians and researchers
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
        <p><b>Repository:</b> <a href="{APP_REPOSITORY_URL}">{APP_REPOSITORY_URL}</a></p>
        <p>For bug reports and feature requests, use the
        <a href="{APP_ISSUES_URL}">issue tracker</a> or email
        <a href="mailto:{UPDATE_FEEDBACK_EMAIL}">{UPDATE_FEEDBACK_EMAIL}</a>.</p>

        <h3>License</h3>
        <p>This software is released under an open-source license. Please see the GitHub repository
        for detailed licensing information.</p>
        """
        )

        layout.addWidget(desc_text)

        auto_check_cb = QCheckBox(
            "Automatically check for updates (about once per day)"
        )
        auto_check_cb.setChecked(self._update_checker.auto_update_checks_enabled())
        auto_check_cb.toggled.connect(
            self._update_checker.set_auto_update_checks_enabled
        )
        layout.addWidget(auto_check_cb)

        # Footer buttons
        button_layout = QHBoxLayout()

        check_updates_btn = QPushButton("Check for updates")
        check_updates_btn.setMinimumWidth(160)
        check_updates_btn.clicked.connect(
            lambda: self._manual_update_check(check_updates_btn)
        )
        button_layout.addWidget(check_updates_btn)

        button_layout.addStretch()

        close_btn = QPushButton("Close")
        close_btn.setMinimumWidth(100)
        close_btn.clicked.connect(dialog.accept)
        button_layout.addWidget(close_btn)
        layout.addLayout(button_layout)

        dialog.exec()

    def _manual_update_check(self, button: QPushButton) -> None:
        """Force an update check and show the result, used by the Help dialog."""
        button.setEnabled(False)
        original_text = button.text()
        button.setText("Checking…")

        connections: list = []

        def cleanup() -> None:
            button.setEnabled(True)
            button.setText(original_text)
            for signal, slot in connections:
                try:
                    signal.disconnect(slot)
                except (RuntimeError, TypeError):
                    pass
            connections.clear()

        def on_available(release: ReleaseInfo) -> None:
            cleanup()
            self._on_update_available(release)

        def on_up_to_date() -> None:
            cleanup()
            QMessageBox.information(
                self,
                "No updates",
                f"You're running the latest version ({APP_VERSION}).",
            )

        def on_failed(error: str) -> None:
            cleanup()
            QMessageBox.warning(
                self,
                "Update check failed",
                f"Could not reach the update server:\n\n{error}",
            )

        connections.append((self._update_checker.update_available, on_available))
        connections.append((self._update_checker.up_to_date, on_up_to_date))
        connections.append((self._update_checker.failed, on_failed))
        for signal, slot in connections:
            signal.connect(slot)

        self._update_checker.check_async(force=True)

    def _on_update_available(self, release: ReleaseInfo) -> None:
        """Show a non-blocking dialog when a newer release is published."""
        box = QMessageBox(self)
        box.setTextFormat(Qt.TextFormat.RichText)
        box.setIcon(QMessageBox.Icon.Information)
        box.setWindowTitle(
            "Pre-release available" if release.is_prerelease else "Update available"
        )
        box.setText(
            f"A new version of {APP_NAME} is available: "
            f"<b>{html.escape(release.version)}</b> "
            f"(you have {html.escape(APP_VERSION)})."
        )
        info_parts: list[str] = []
        if release.is_prerelease:
            mail_href = html.escape(f"mailto:{UPDATE_FEEDBACK_EMAIL}", quote=True)
            issues_href = html.escape(APP_ISSUES_URL, quote=True)
            email_lbl = html.escape(UPDATE_FEEDBACK_EMAIL)
            info_parts.append(
                "<p><b>Note:</b> This is <u>not</u> a stable release; bugs may occur. "
                "If you try this version, please report issues to "
                f'<a href="{mail_href}">{email_lbl}</a> or on '
                f'<a href="{issues_href}">GitHub</a>.</p>'
            )
        notes = release.body.strip() if release.body else ""
        if notes:
            excerpt = notes if len(notes) <= 600 else notes[:600] + "…"
            excerpt_html = html.escape(excerpt).replace("\n", "<br>")
            info_parts.append(f"<p>Release notes:</p><p>{excerpt_html}</p>")
        if info_parts:
            box.setInformativeText("".join(info_parts))

        opt_out_cb = QCheckBox("Don't notify me automatically about new updates")
        opt_out_cb.setChecked(False)
        box.setCheckBox(opt_out_cb)

        download_btn = box.addButton(
            "Open download page", QMessageBox.ButtonRole.AcceptRole
        )
        box.addButton("Remind me later", QMessageBox.ButtonRole.RejectRole)
        box.exec()

        if opt_out_cb.isChecked():
            self._update_checker.set_auto_update_checks_enabled(False)

        if box.clickedButton() is download_btn and release.html_url:
            QDesktopServices.openUrl(QUrl(release.html_url))

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
        self.step0_view.annotations_only_button.clicked.connect(
            self._select_annotations_only_mode
        )
        self.step0_view.longitudinal_report_button.clicked.connect(
            self._select_longitudinal_report
        )

    def _select_full_mode(self) -> None:
        """Handle selection of full workflow mode."""
        self.workflow_mode = "full"
        self.current_step = 1
        self._load_full_workflow_views()
        if self.step1_view is not None:
            self.stack.setCurrentWidget(self.step1_view)
        self._update_window_size_for_main_workflow()  # Resize to normal size
        self._update_ui_state()

    def _select_annotations_only_mode(self) -> None:
        """Handle selection of annotations-only workflow mode."""
        self.workflow_mode = "annotations_only"
        self.current_step = 1
        self._load_annotations_only_views()
        if self.annotations_file_view is not None:
            self.stack.setCurrentWidget(self.annotations_file_view)
        self._update_window_size_for_main_workflow()  # Resize to normal size
        self._update_ui_state()

    def _select_longitudinal_report(self) -> None:
        """Handle selection of longitudinal report mode."""
        self.workflow_mode = "longitudinal"
        self.current_step = 1
        self._load_longitudinal_views()
        if self.longitudinal_file_view is not None:
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
        view = self.longitudinal_file_view
        assert view is not None
        view.export_word_action.triggered.connect(
            lambda: self._export_longitudinal_report("word")
        )
        view.export_pdf_action.triggered.connect(
            lambda: self._export_longitudinal_report("pdf")
        )

    def _export_longitudinal_report(self, fmt: str) -> None:
        """Handle longitudinal report export (Word or PDF)."""
        view = self.longitudinal_file_view
        if view is None:
            return
        files = view.get_loaded_files()
        if not files:
            QMessageBox.warning(
                self,
                "No Files",
                "Please load at least one annotation file before creating a report.",
            )
            return

        # Extract session scales from all files
        scales = LongitudinalFileView.extract_session_scales_from_files(files)
        if not scales:
            QMessageBox.warning(
                self,
                "No Session Scales",
                "No session scales (is_initial=0) were found in the loaded files.\n"
                "The report cannot determine the best entry without scale data.",
            )
            return

        # Extract clinical scales (is_initial=1) for the dialog
        clinical_scales = LongitudinalFileView.extract_clinical_scales_from_files(files)

        # Show scale optimization dialog
        from .export_dialog import (
            ReportSectionsDialog,
            ScaleTargetValuesDialog,
        )

        dialog = ScaleTargetValuesDialog(
            scales,
            self,
            clinical_scales=clinical_scales if clinical_scales else None,
        )
        if dialog.exec() != QDialog.DialogCode.Accepted:
            return

        prefs = dialog.get_scale_prefs()
        clinical_prefs = dialog.get_clinical_scale_prefs()

        # Show section selection dialog
        session_data_children = [
            ("session_data_graph", "Session Data Graph", True),
            ("session_data_table", "Session Data Table", False),
        ]
        section_defs = [
            ("sessions_overview", "Sessions Overview", True, None),
            ("session_data", "Session Data", False, session_data_children),
            ("electrode_config", "Electrode Configuration", False, None),
            ("programming_summary", "Programming Summary", False, None),
        ]
        sec_dialog = ReportSectionsDialog(section_defs, self, title="Report Sections")
        if sec_dialog.exec() != QDialog.DialogCode.Accepted:
            return
        sections = sec_dialog.get_selected_sections()

        # Generate report
        self.controller.export_longitudinal_report(
            file_paths=files,
            scale_prefs=prefs,
            clinical_scale_prefs=clinical_prefs,
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
            from .annotation_only_view import AnnotationsFileView

            self.annotations_file_view = AnnotationsFileView(self)
            self.stack.addWidget(self.annotations_file_view)
            self._connect_annotations_file_signals()

        if self.annotations_session_view is None:
            from .annotation_only_view import AnnotationsSessionView

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
            self.stack.setSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
            self.stack.setFixedWidth(compact_width - 40)  # Account for margins
            self.stack.setFixedHeight(
                compact_height - 100
            )  # Prevent vertical scrollbar
            self.stack.adjustSize()
        if hasattr(self, "stack_scroll_area"):
            self.stack_scroll_area.setSizePolicy(
                QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding
            )

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
            self.stack.setSizePolicy(
                QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum
            )
            self.stack.setMaximumWidth(16777215)  # Remove fixed width
            self.stack.setMaximumHeight(16777215)  # Remove fixed height
        if hasattr(self, "stack_scroll_area"):
            self.stack_scroll_area.setSizePolicy(
                QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding
            )

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
        self.setMaximumSize(
            screen_width, screen_height
        )  # Allow full screen maximization

        self._clamp_to_screen()

    def _clamp_to_screen(self) -> None:
        """Ensure the window stays within the available screen area."""
        if getattr(self, "_is_clamping", False):
            return
        self._is_clamping = True
        try:
            screen = (
                self.app.screenAt(self.frameGeometry().center())
                or self.app.primaryScreen()
            )
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
        step1 = self.step1_view
        assert step1 is not None
        # Connect preset buttons
        preset_manager = get_scale_preset_manager()
        clinical_presets = preset_manager.get_clinical_presets()
        for preset_name in clinical_presets.keys():
            btn = step1.get_preset_button(preset_name)
            if btn:
                btn.clicked.connect(
                    lambda checked, name=preset_name: (
                        self.controller.apply_clinical_preset(name, step1)
                    )
                )

        # Initialize empty clinical scales
        step1.update_clinical_scales(
            [],
            on_add_callback=lambda: self.controller.on_add_clinical_scale(step1),
            on_remove_callback=lambda row: self.controller.on_remove_clinical_scale(
                step1, row
            ),
        )

        # Connect next button
        step1.next_button.clicked.connect(self._go_to_step2)

    def _connect_step2_signals(self) -> None:
        """Connect Step 2 view signals to controller."""
        step2 = self.step2_view
        assert step2 is not None
        self.controller.prepare_step2(step2)
        # Connect preset buttons
        preset_manager = get_scale_preset_manager()
        session_presets = preset_manager.get_session_presets()
        for preset_name in session_presets.keys():
            btn = step2.get_preset_button(preset_name)
            if btn:
                btn.clicked.connect(
                    lambda checked, name=preset_name: (
                        self.controller.apply_session_preset(name, step2)
                    )
                )
        step2.next_button.clicked.connect(self._go_to_step3)

        # Auto-select session preset if clinical scales match
        # Moved to _go_to_step2 to be called every time navigating to step2

    def _connect_step3_signals(self) -> None:
        """Connect Step 3 view signals to controller."""
        step3 = self.step3_view
        assert step3 is not None
        self.controller.prepare_step3(step3)
        if hasattr(step3, "undo_button"):
            step3.undo_button.clicked.connect(step3._undo_last_entry)
        step3.undo_requested.connect(
            lambda: self.controller.undo_last_session_entry(step3)
        )
        step3.insert_button.clicked.connect(
            lambda: self.controller.insert_session_row(step3)
        )
        step3.close_button.clicked.connect(lambda: self.controller.close_session(self))
        step3.export_word_action.triggered.connect(
            lambda: self._export_session_report("word")
        )
        step3.export_pdf_action.triggered.connect(
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

        from .export_dialog import ScaleTargetValuesDialog

        dialog = ScaleTargetValuesDialog(scales, self)
        if dialog.exec() != QDialog.DialogCode.Accepted:
            return

        prefs = dialog.get_scale_prefs()

        # Show section selection dialog
        from .export_dialog import ReportSectionsDialog

        session_data_children = [
            ("session_data_graph", "Session Data Graph", True),
            ("session_data_table", "Session Data Table", True),
        ]
        section_defs = [
            ("initial_notes", "Initial Clinical Notes", True, None),
            ("session_data", "Session Data", True, session_data_children),
            ("electrode_config", "Electrode Configurations", True, None),
            ("programming_summary", "Programming Summary", True, None),
        ]
        sec_dialog = ReportSectionsDialog(section_defs, self, title="Report Sections")
        if sec_dialog.exec() != QDialog.DialogCode.Accepted:
            return
        sections = sec_dialog.get_selected_sections()

        if fmt == "word":
            self.controller.export_session_word(
                self, scale_prefs=prefs, sections=sections
            )
        else:
            self.controller.export_session_pdf(
                self, scale_prefs=prefs, sections=sections
            )

    def _create_nav_bar(self) -> QHBoxLayout:
        """
        Create the navigation bar with back button.

        Returns:
            QHBoxLayout containing navigation controls
        """
        nav_layout = QHBoxLayout()

        self.back_button = QPushButton("Back")
        self.back_button.setIcon(
            self.style().standardIcon(QStyle.StandardPixmap.SP_ArrowBack)
        )
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

        if hasattr(current, "undo_button"):
            widgets.append(current.undo_button)

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
        afv = self.annotations_file_view
        assert afv is not None
        # Backward-compatible: older AnnotationsFileView exposed browse_button.
        # Newer UI manages file open/new internally.
        browse_btn = getattr(afv, "browse_button", None)
        if isinstance(browse_btn, QAbstractButton):
            browse_btn.clicked.connect(
                lambda: self.controller.browse_save_location_simple(afv, self)
            )
        afv.next_button.clicked.connect(self._go_to_annotations_session)

    def _go_to_annotations_session(self) -> None:
        """Navigate to annotations session (annotations-only workflow)."""
        # Validate file info
        if not self.controller.validate_annotations_file(
            self.annotations_file_view, self
        ):
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
        asv = self.annotations_session_view
        assert asv is not None
        asv.insert_button.clicked.connect(
            lambda: self.controller.insert_simple_annotation(asv)
        )
        asv.close_button.clicked.connect(lambda: self.controller.close_session(self))

        if hasattr(asv, "export_word_action"):
            asv.export_word_action.triggered.connect(
                lambda: self.controller.export_annotations_word(self)
            )
        if hasattr(asv, "export_pdf_action"):
            asv.export_pdf_action.triggered.connect(
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

        # Auto-select session preset if clinical preset was selected
        self.controller.auto_select_session_preset(self.step2_view, self.step1_view)

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
        elif not getattr(self, "_step3_prepared", False):
            # Step 3 was created but preparation failed previously — retry
            try:
                self.controller.prepare_step3(self.step3_view)
                self._step3_prepared = True
            except Exception:
                logger.exception("Step 3 preparation retry failed")
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
