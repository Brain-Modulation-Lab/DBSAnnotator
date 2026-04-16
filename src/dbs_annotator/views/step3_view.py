"""
Step 3 view - Active session recording.

This module contains the view for the third step where users actively record
session data including stimulation parameters and scale values.
"""

import logging
from typing import cast

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QDoubleValidator, QIntValidator
from PySide6.QtWidgets import (
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QFormLayout,
    QFrame,
    QGraphicsEffect,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QMenu,
    QMessageBox,
    QPushButton,
    QScrollArea,
    QSizePolicy,
    QSplitter,
    QStyle,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from ..config import (
    PLACEHOLDERS,
    STIMULATION_LIMITS,
)
from ..config_electrode_models import ContactState, StimulationRule
from ..models import ElectrodeCanvas
from ..ui import (
    AmplitudeSplitWidget,
    IncrementWidget,
    ScaleProgressWidget,
    create_horizontal_line,
    get_cathode_labels,
)
from ..utils.program_config_manager import (
    ProgramConfigManager,
    get_program_config_manager,
)
from .base_view import BaseStepView

logger = logging.getLogger(__name__)


class Step3View(BaseStepView):
    """
    Third step view for active session recording.

    This view handles:
    - Real-time stimulation parameter adjustment
    - Session scale value recording
    - Session notes
    - Data insertion and session closing
    """

    undo_requested = Signal()

    def __init__(self, parent_style=None):
        """
        Initialize Step 3 view.

        Args:
            parent_style: Parent widget style for icon access (deprecated, kept for compatibility)
        """
        super().__init__()
        # parent_style is now set in BaseStepView.__init__
        self.session_scale_value_edits = []
        self.step3_session_scales_form: QFormLayout | None = None

        self.left_canvas = ElectrodeCanvas()
        self.right_canvas = ElectrodeCanvas()

        # Electrode disable state
        self.left_electrode_enabled = True
        self.right_electrode_enabled = True
        self.left_canvas.validation_callback = self._on_left_canvas_validation
        self.right_canvas.validation_callback = self._on_right_canvas_validation
        self._left_selection_valid = True
        self._right_selection_valid = True

        self._current_model = None
        self._setup_ui()

    def get_header_title(self) -> str:
        """Return the wizard header title for Step 3."""
        return "Programming Session Ongoing"

    def _undo_last_entry(self) -> None:
        """Show confirmation dialog and delete the last block_ID entry from TSV."""
        reply = QMessageBox.question(
            self,
            "Confirm Undo",
            "Are you sure you want to delete the last session entry?",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No,
        )

        if reply == QMessageBox.Yes:
            # Emit signal to request undo
            self.undo_requested.emit()

    def _setup_ui(self) -> None:
        """Set up the UI layout."""

        # Left side: Session settings (params + electrodes)
        left_widget = QWidget()
        left_layout = QVBoxLayout(left_widget)
        left_layout.setContentsMargins(0, 0, 0, 0)
        settings_group = self._create_session_settings_group()
        left_layout.addWidget(settings_group)
        left_widget.setMinimumWidth(500)

        # Right side: Scales and notes
        right_widget = QWidget()
        right_layout = QVBoxLayout(right_widget)
        right_layout.setContentsMargins(0, 0, 0, 0)
        scales_group = self._create_session_scales_group()
        right_layout.addWidget(scales_group)
        right_layout.addWidget(create_horizontal_line())
        notes_group = self._create_session_notes_group()
        right_layout.addWidget(notes_group)
        right_widget.setMinimumWidth(400)

        # Splitter: right panel shrinks first (stretch=1), left stays stable (stretch=0)
        splitter = QSplitter(Qt.Horizontal)
        splitter.addWidget(left_widget)
        splitter.addWidget(right_widget)
        splitter.setStretchFactor(0, 0)
        splitter.setStretchFactor(1, 1)
        splitter.setChildrenCollapsible(False)

        self.main_layout.addWidget(splitter)

        self.undo_button = QPushButton("Undo")
        self.undo_button.setIcon(
            self.parent_style.standardIcon(QStyle.SP_DialogCancelButton)
        )
        self.undo_button.setMinimumWidth(100)
        self.undo_button.setEnabled(False)

        self.insert_button = QPushButton("Insert")
        self.insert_button.setIcon(
            self.parent_style.standardIcon(QStyle.SP_DialogApplyButton)
        )
        self.insert_button.setMinimumWidth(170)

        self.export_button = QPushButton("Export Report")
        self.export_button.setIcon(
            self.parent_style.standardIcon(QStyle.SP_DialogSaveButton)
        )
        self.export_button.setMinimumWidth(170)

        self.close_button = QPushButton("Close session")
        self.close_button.setIcon(
            self.parent_style.standardIcon(QStyle.SP_DialogCloseButton)
        )
        self.close_button.setMinimumWidth(170)

        # Create dropdown menu for export options
        self.export_menu = QMenu(self)

        # Word export action
        self.export_word_action = self.export_menu.addAction("📄 Word Report")
        self.export_word_action.setToolTip("Export to Word (.docx) document")

        # PDF export action
        self.export_pdf_action = self.export_menu.addAction("📋 PDF Report")
        self.export_pdf_action.setToolTip("Export to PDF document")

        # Set menu to button
        self.export_button.setMenu(self.export_menu)

    def _create_session_settings_group(self) -> QGroupBox:
        """Create the session settings group box."""
        gb_session = QGroupBox("Session settings")
        gb_session.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)

        container_layout = QHBoxLayout()

        sidebar_layout = QVBoxLayout()

        group_row = QGroupBox("Program")
        group_row_layout = QHBoxLayout()
        self.group_combo = QComboBox()
        self.group_combo.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
        # Prevent focus rectangle on dropdown
        self.group_combo.view().window().setAttribute(
            Qt.WA_TranslucentBackground, False
        )
        self.group_combo.view().setStyleSheet("QAbstractItemView { outline: none; }")
        # Load program names from config
        program_config = get_program_config_manager()
        programs = program_config.get_all_programs()
        self.group_combo.addItems(programs)
        self.group_combo.setCurrentIndex(0)
        group_row_layout.addWidget(self.group_combo)

        # Add edit button for program names
        edit_programs_btn = QPushButton()
        edit_programs_btn.setIcon(self._create_settings_icon())
        edit_programs_btn.setToolTip("Edit program names")
        edit_programs_btn.setObjectName("programSettingsButton")
        edit_programs_btn.clicked.connect(self._edit_program_names)
        group_row_layout.addWidget(edit_programs_btn)

        group_row.setLayout(group_row_layout)

        freq_limits = STIMULATION_LIMITS["frequency"]
        amp_limits = STIMULATION_LIMITS["amplitude"]
        pw_limits = STIMULATION_LIMITS["pulse_width"]

        self.left_group = QGroupBox("Left")
        self.left_group.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        left_group_layout = QVBoxLayout()

        freq_row = QHBoxLayout()
        freq_row.addWidget(QLabel("Frequency:"))
        freq_row.addStretch()
        self.session_left_stim_freq_edit = QLineEdit()
        self.session_left_stim_freq_edit.setMaximumWidth(80)
        self.session_left_stim_freq_edit.setPlaceholderText(PLACEHOLDERS["frequency"])
        self.session_left_stim_freq_edit.setValidator(
            QIntValidator(int(freq_limits["min"]), int(freq_limits["max"]))
        )
        left_freq_widget = IncrementWidget(
            self.session_left_stim_freq_edit,
            step1=freq_limits["step1"],
            step2=freq_limits["step2"],
            decimals=0,
            min_value=freq_limits["min"],
            max_value=freq_limits["max"],
        )
        freq_row.addWidget(left_freq_widget)

        amp_row = QHBoxLayout()
        amp_row.addWidget(QLabel("Amplitude:"))
        amp_row.addStretch()
        self.session_left_amp_edit = QLineEdit()
        self.session_left_amp_edit.setMaximumWidth(80)
        self.session_left_amp_edit.setPlaceholderText(PLACEHOLDERS["amplitude"])
        self.session_left_amp_edit.setValidator(
            QDoubleValidator(
                float(amp_limits["min"]),
                float(amp_limits["max"]),
                int(amp_limits["decimals"]),
            )
        )
        left_amp_widget = IncrementWidget(
            self.session_left_amp_edit,
            step1=amp_limits["step1"],
            step2=amp_limits["step2"],
            decimals=1,
            min_value=amp_limits["min"],
            max_value=amp_limits["max"],
        )
        amp_row.addWidget(left_amp_widget)

        pw_row = QHBoxLayout()
        pw_row.addWidget(QLabel("Pulse width:"))
        pw_row.addStretch()
        self.session_left_pw_edit = QLineEdit()
        self.session_left_pw_edit.setMaximumWidth(80)
        self.session_left_pw_edit.setPlaceholderText(PLACEHOLDERS["pulse_width"])
        self.session_left_pw_edit.setValidator(
            QIntValidator(int(pw_limits["min"]), int(pw_limits["max"]))
        )
        left_pw_widget = IncrementWidget(
            self.session_left_pw_edit,
            step1=pw_limits["step1"],
            step2=pw_limits["step2"],
            decimals=0,
            min_value=pw_limits["min"],
            max_value=pw_limits["max"],
        )
        pw_row.addWidget(left_pw_widget)

        self.left_amp_split = AmplitudeSplitWidget(self.session_left_amp_edit)

        left_group_layout.addLayout(freq_row)
        left_group_layout.addLayout(amp_row)
        left_group_layout.addWidget(self.left_amp_split)
        left_group_layout.addLayout(pw_row)

        self.left_config_box = QFrame()
        self.left_config_box.setStyleSheet("background: transparent; border: none;")
        self.left_config_box.setAttribute(Qt.WA_TranslucentBackground, True)
        self.left_config_box.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        left_config_layout = QVBoxLayout(self.left_config_box)
        left_config_layout.setContentsMargins(6, 4, 6, 4)
        self.left_config_label = QLabel()
        self.left_config_label.setWordWrap(True)
        self.left_config_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.left_config_label.setTextFormat(Qt.RichText)
        left_config_layout.addWidget(self.left_config_label)
        left_group_layout.addWidget(self.left_config_box)
        left_group_layout.addStretch(1)
        self.left_group.setLayout(left_group_layout)

        self.right_group = QGroupBox("Right")
        self.right_group.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        right_group_layout = QVBoxLayout()

        freq_row = QHBoxLayout()
        freq_row.addWidget(QLabel("Frequency:"))
        freq_row.addStretch()
        self.session_right_stim_freq_edit = QLineEdit()
        self.session_right_stim_freq_edit.setMaximumWidth(80)
        self.session_right_stim_freq_edit.setPlaceholderText(PLACEHOLDERS["frequency"])
        self.session_right_stim_freq_edit.setValidator(
            QIntValidator(int(freq_limits["min"]), int(freq_limits["max"]))
        )
        right_freq_widget = IncrementWidget(
            self.session_right_stim_freq_edit,
            step1=freq_limits["step1"],
            step2=freq_limits["step2"],
            decimals=0,
            min_value=freq_limits["min"],
            max_value=freq_limits["max"],
        )
        freq_row.addWidget(right_freq_widget)

        amp_row = QHBoxLayout()
        amp_row.addWidget(QLabel("Amplitude:"))
        amp_row.addStretch()
        self.session_right_amp_edit = QLineEdit()
        self.session_right_amp_edit.setMaximumWidth(80)
        self.session_right_amp_edit.setPlaceholderText(PLACEHOLDERS["amplitude"])
        self.session_right_amp_edit.setValidator(
            QDoubleValidator(
                float(amp_limits["min"]),
                float(amp_limits["max"]),
                int(amp_limits["decimals"]),
            )
        )
        right_amp_widget = IncrementWidget(
            self.session_right_amp_edit,
            step1=amp_limits["step1"],
            step2=amp_limits["step2"],
            decimals=1,
            min_value=amp_limits["min"],
            max_value=amp_limits["max"],
        )
        amp_row.addWidget(right_amp_widget)

        pw_row = QHBoxLayout()
        pw_row.addWidget(QLabel("Pulse width:"))
        pw_row.addStretch()
        self.session_right_pw_edit = QLineEdit()
        self.session_right_pw_edit.setMaximumWidth(80)
        self.session_right_pw_edit.setPlaceholderText(PLACEHOLDERS["pulse_width"])
        self.session_right_pw_edit.setValidator(
            QIntValidator(int(pw_limits["min"]), int(pw_limits["max"]))
        )
        right_pw_widget = IncrementWidget(
            self.session_right_pw_edit,
            step1=pw_limits["step1"],
            step2=pw_limits["step2"],
            decimals=0,
            min_value=pw_limits["min"],
            max_value=pw_limits["max"],
        )
        pw_row.addWidget(right_pw_widget)

        self.right_amp_split = AmplitudeSplitWidget(self.session_right_amp_edit)

        right_group_layout.addLayout(freq_row)
        right_group_layout.addLayout(amp_row)
        right_group_layout.addWidget(self.right_amp_split)
        right_group_layout.addLayout(pw_row)

        self.right_config_box = QFrame()
        self.right_config_box.setStyleSheet("background: transparent; border: none;")
        self.right_config_box.setAttribute(Qt.WA_TranslucentBackground, True)
        self.right_config_box.setSizePolicy(
            QSizePolicy.Expanding, QSizePolicy.Expanding
        )
        right_config_layout = QVBoxLayout(self.right_config_box)
        right_config_layout.setContentsMargins(6, 4, 6, 4)
        self.right_config_label = QLabel()
        self.right_config_label.setWordWrap(True)
        self.right_config_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.right_config_label.setTextFormat(Qt.RichText)
        right_config_layout.addWidget(self.right_config_label)
        right_group_layout.addWidget(self.right_config_box)
        right_group_layout.addStretch(1)
        self.right_group.setLayout(right_group_layout)

        sidebar_layout.addWidget(group_row)
        sidebar_layout.addWidget(self.left_group)
        sidebar_layout.addWidget(self.right_group)
        sidebar_layout.addStretch(1)

        sidebar_widget = QWidget()
        sidebar_widget.setLayout(sidebar_layout)
        sidebar_scroll = QScrollArea()
        sidebar_scroll.setStyleSheet("""
            QScrollArea {
                background: transparent;
                border: none;
            }
            QScrollArea > QWidget > QWidget {
                background: transparent;
            }
        """)
        sidebar_scroll.setWidgetResizable(True)
        sidebar_scroll.setFrameShape(QFrame.NoFrame)
        sidebar_scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        sidebar_scroll.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        sidebar_scroll.setMinimumWidth(380)
        sidebar_scroll.setWidget(sidebar_widget)

        electrodes_layout = QVBoxLayout()
        electrodes_row = QHBoxLayout()

        self.left_canvas_group = QGroupBox("Left electrode")
        self.left_canvas_group.setCheckable(True)
        self.left_canvas_group.setChecked(True)
        self.left_canvas_group.toggled.connect(
            lambda checked: self._toggle_electrode("left", checked)
        )
        left_canvas_layout = QVBoxLayout()
        left_canvas_layout.addWidget(self.left_canvas, 1)
        self.left_canvas_group.setLayout(left_canvas_layout)

        self.right_canvas_group = QGroupBox("Right electrode")
        self.right_canvas_group.setCheckable(True)
        self.right_canvas_group.setChecked(True)
        self.right_canvas_group.toggled.connect(
            lambda checked: self._toggle_electrode("right", checked)
        )
        right_canvas_layout = QVBoxLayout()
        right_canvas_layout.addWidget(self.right_canvas, 1)
        self.right_canvas_group.setLayout(right_canvas_layout)

        electrodes_row.addWidget(self.left_canvas_group, 1)
        electrodes_row.addWidget(self.right_canvas_group, 1)

        electrodes_layout.addLayout(electrodes_row)
        electrodes_layout.addLayout(self._create_electrode_legend_layout())

        container_layout.addWidget(sidebar_scroll, 0)
        container_layout.addLayout(electrodes_layout, 1)

        layout = QVBoxLayout(gb_session)
        layout.addLayout(container_layout)

        return gb_session

    def _on_left_canvas_validation(self, is_valid: bool, error_msg: str) -> None:
        """Callback when left electrode canvas validation state changes."""
        self._left_selection_valid = bool(is_valid)
        self.update_configuration_display()
        if hasattr(self, "left_amp_split"):
            cathode_labels = get_cathode_labels(self.left_canvas)
            is_single_grouped = self._is_single_grouped_directional(
                cathode_labels, self.left_canvas
            )
            self.left_amp_split.update_cathodes(cathode_labels, is_single_grouped)

    def _on_right_canvas_validation(self, is_valid: bool, error_msg: str) -> None:
        """Callback when right electrode canvas validation state changes."""
        self._right_selection_valid = bool(is_valid)
        self.update_configuration_display()
        if hasattr(self, "right_amp_split"):
            cathode_labels = get_cathode_labels(self.right_canvas)
            is_single_grouped = self._is_single_grouped_directional(
                cathode_labels, self.right_canvas
            )
            self.right_amp_split.update_cathodes(cathode_labels, is_single_grouped)

    def set_electrode_model(self, model) -> None:
        """Set the electrode model on both canvases and refresh display."""
        self._current_model = model
        self.left_canvas.set_model(model)
        self.right_canvas.set_model(model)
        self.update_configuration_display()

    def update_configuration_display(self) -> None:
        """Refresh the configuration validity labels for both sides."""
        if not hasattr(self, "left_config_label") or not hasattr(
            self, "right_config_label"
        ):
            return
        self.left_config_label.setText("✓ Configuration valid")
        self.right_config_label.setText("✓ Configuration valid")

        self._apply_config_validation_styles()

    def _apply_config_validation_styles(self) -> None:
        """Apply red/green styling to config labels based on validation state."""
        if hasattr(self, "left_config_box") and hasattr(self, "left_config_label"):
            if not self._left_selection_valid:
                self.left_config_box.setStyleSheet("border: 2px solid #cc0000;")
                self.left_config_label.setStyleSheet("color: #cc0000;")
                self.left_config_label.setProperty("class", "")
                self.left_config_label.setText(
                    "Invalid configuration: violates selection rules"
                )
            else:
                self.left_config_box.setStyleSheet("")
                self.left_config_label.setStyleSheet("")
                self.left_config_label.setProperty("class", "validation-success")
                self.left_config_label.setText("✓ Configuration valid")
                self.left_config_label.style().unpolish(self.left_config_label)
                self.left_config_label.style().polish(self.left_config_label)
                self.left_config_label.update()
                self.left_config_label.repaint()

        if hasattr(self, "right_config_box") and hasattr(self, "right_config_label"):
            if not self._right_selection_valid:
                self.right_config_box.setStyleSheet("border: 2px solid #cc0000;")
                self.right_config_label.setStyleSheet("color: #cc0000;")
                self.right_config_label.setProperty("class", "")
                self.right_config_label.setText(
                    "Invalid configuration: violates selection rules"
                )
            else:
                self.right_config_box.setStyleSheet("")
                self.right_config_label.setStyleSheet("")
                self.right_config_label.setProperty("class", "validation-success")
                self.right_config_label.setText("✓ Configuration valid")
                self.right_config_label.style().unpolish(self.right_config_label)
                self.right_config_label.style().polish(self.right_config_label)
                self.right_config_label.update()
                self.right_config_label.repaint()

    def _format_configuration_html(self, canvas: ElectrodeCanvas) -> str:
        """Return an HTML summary of the electrode contact configuration."""
        model = canvas.model
        if not model:
            return ""

        lines = []
        case_state_str = {
            ContactState.OFF: "OFF",
            ContactState.ANODIC: "Anodic (+)",
            ContactState.CATHODIC: "Cathodic (-)",
        }
        lines.append(f"<b>CASE (Ground):</b> {case_state_str[canvas.case_state]}")
        lines.append("")

        if canvas.contact_states:
            lines.append("<b>Active contacts:</b>")
            for contact_id in sorted(canvas.contact_states.keys()):
                contact_idx, seg_idx = contact_id
                state = canvas.contact_states[contact_id]
                state_str = (
                    "Anodic (+)" if state == ContactState.ANODIC else "Cathodic (-)"
                )

                if model.is_directional:
                    segment_labels = ["a", "b", "c"]
                    contact_name = f"C{contact_idx}{segment_labels[seg_idx]}"
                else:
                    contact_name = f"C{contact_idx}"
                lines.append(f"  • {contact_name}: {state_str}")
        else:
            lines.append("<i>No active contacts</i>")

        return "<br>".join(lines)

    def get_left_anode_text(self) -> str:
        """Return underscore-separated anode token string for the left electrode."""
        return self._get_anode_cathode_texts(self.left_canvas)[0]

    def get_left_cathode_text(self) -> str:
        """Return underscore-separated cathode token string for the left electrode."""
        return self._get_anode_cathode_texts(self.left_canvas)[1]

    def get_right_anode_text(self) -> str:
        """Return underscore-separated anode token string for the right electrode."""
        return self._get_anode_cathode_texts(self.right_canvas)[0]

    def get_right_cathode_text(self) -> str:
        """Return underscore-separated cathode token string for the right electrode."""
        return self._get_anode_cathode_texts(self.right_canvas)[1]

    def _get_anode_cathode_texts(self, canvas: ElectrodeCanvas) -> tuple[str, str]:
        """Build anode and cathode token strings from the canvas contact states."""
        model = canvas.model
        if not model:
            return "", ""

        anode_items = []
        cathode_items = []

        if canvas.case_state == ContactState.ANODIC:
            anode_items.append("case")
        elif canvas.case_state == ContactState.CATHODIC:
            cathode_items.append("case")

        if model.is_directional:
            for contact_idx in range(model.num_contacts):
                # Check if this contact level is directional (has segments)
                is_contact_directional = model.is_level_directional(contact_idx)

                if is_contact_directional:
                    # This contact has segments - check individual segments
                    seg_states = [
                        canvas.contact_states.get((contact_idx, seg), ContactState.OFF)
                        for seg in range(3)
                    ]

                    # Always show individual segments, never group them
                    seg_labels = ["a", "b", "c"]
                    for seg, seg_state in enumerate(seg_states):
                        if seg_state == ContactState.ANODIC:
                            anode_items.append(f"E{contact_idx}{seg_labels[seg]}")
                        elif seg_state == ContactState.CATHODIC:
                            cathode_items.append(f"E{contact_idx}{seg_labels[seg]}")
                else:
                    # This contact is a ring contact - no segments
                    state = canvas.contact_states.get(
                        (contact_idx, 0), ContactState.OFF
                    )
                    if state == ContactState.ANODIC:
                        anode_items.append(f"E{contact_idx}")
                    elif state == ContactState.CATHODIC:
                        cathode_items.append(f"E{contact_idx}")
        else:
            # Non-directional model - all contacts are ring contacts
            for contact_idx in range(model.num_contacts):
                state = canvas.contact_states.get((contact_idx, 0), ContactState.OFF)
                if state == ContactState.ANODIC:
                    anode_items.append(f"E{contact_idx}")
                elif state == ContactState.CATHODIC:
                    cathode_items.append(f"E{contact_idx}")

        return "_".join(anode_items), "_".join(cathode_items)

    def _is_single_grouped_directional(self, cathode_labels: list[str], canvas) -> bool:
        """Check if we have a single grouped directional contact (all 3 segments selected)."""
        if len(cathode_labels) != 1:
            return False

        lbl = cathode_labels[0]
        # Check if this is a grouped contact (E1, E2, etc., not E1a, E1b)
        is_grouped = len(lbl) >= 2 and lbl[0] == "E" and lbl[1:].isdigit()

        if not is_grouped:
            return False

        # Verify that this contact actually has all 3 segments selected on the canvas
        try:
            contact_idx = int(lbl[1:])
            model = canvas.model
            if not model or not model.is_directional:
                return False

            # Check if this contact level is directional
            if not model.is_level_directional(contact_idx):
                return False

            # Check if all 3 segments are cathodic
            seg_states = [
                canvas.contact_states.get((contact_idx, seg), ContactState.OFF)
                for seg in range(3)
            ]
            return all(state == ContactState.CATHODIC for state in seg_states)
        except ValueError, IndexError:
            return False

    def _create_session_scales_group(self) -> QGroupBox:
        """Create the session scales group box."""
        gb_scales = QGroupBox("Session scales")
        gb_scales.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)

        layout = QVBoxLayout(gb_scales)
        layout.setSpacing(10)

        # Scales form
        self.step3_session_scales_form = QFormLayout()
        self.step3_session_scales_form.setLabelAlignment(Qt.AlignRight)
        self.step3_session_scales_form.setFormAlignment(Qt.AlignTop)
        layout.addLayout(self.step3_session_scales_form)
        layout.addStretch()

        return gb_scales

    def _toggle_electrode(self, side: str, checked: bool) -> None:
        """Toggle electrode enable/disable state for canvas and settings."""
        from PySide6.QtWidgets import QGraphicsOpacityEffect

        if side == "left":
            self.left_electrode_enabled = checked
            self.left_group.setEnabled(checked)
            self.left_canvas.setEnabled(checked)
            # Apply opacity to visually dim canvas and settings
            for widget in (self.left_canvas, self.left_group):
                if not checked:
                    effect = QGraphicsOpacityEffect(widget)
                    effect.setOpacity(0.3)
                    widget.setGraphicsEffect(effect)
                else:
                    widget.setGraphicsEffect(cast("QGraphicsEffect", None))
        elif side == "right":
            self.right_electrode_enabled = checked
            self.right_group.setEnabled(checked)
            self.right_canvas.setEnabled(checked)
            for widget in (self.right_canvas, self.right_group):
                if not checked:
                    effect = QGraphicsOpacityEffect(widget)
                    effect.setOpacity(0.3)
                    widget.setGraphicsEffect(effect)
                else:
                    widget.setGraphicsEffect(cast("QGraphicsEffect", None))

    def _create_session_notes_group(self) -> QGroupBox:
        gb_notes = QGroupBox("Session notes")
        gb_notes.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)

        layout = QVBoxLayout(gb_notes)
        layout.setSpacing(10)

        # Instructions
        instructions = QLabel(
            "Enter your observations and notes below. "
            "Annotations will be saved with timestamp, parameters, and scale scores."
        )
        instructions.setWordWrap(True)
        instructions.setStyleSheet("color: #64748b; padding: 5px;")
        layout.addWidget(instructions)

        # Annotation text area
        self.session_notes_edit = QTextEdit()
        self.session_notes_edit.setPlaceholderText("Type your notes here...")
        self.session_notes_edit.setSizePolicy(
            QSizePolicy.Expanding, QSizePolicy.Expanding
        )
        self.session_notes_edit.setMinimumHeight(100)
        layout.addWidget(self.session_notes_edit)

        return gb_notes

    def update_session_scales(self, scale_names) -> None:
        """
        Update the session scales form with the given scale names.

        Args:
            scale_names: List of scale names to display
        """
        # Clear existing form
        while self.step3_session_scales_form.rowCount():
            self.step3_session_scales_form.removeRow(0)

        self.session_scale_value_edits = []

        # Add scale inputs
        # Step2 provides tuples: (name, min, max). We also support a plain list of names.
        for item in scale_names or []:
            if isinstance(item, (tuple, list)) and len(item) >= 1:
                name = item[0]
                min_val = item[1] if len(item) >= 2 else ""
                max_val = item[2] if len(item) >= 3 else ""
            else:
                name = item
                min_val = ""
                max_val = ""

            try:
                name = str(name)
            except Exception:
                name = ""
            if not name.strip():
                continue

            # Use progress bar style (0.25 steps). Convert min/max to internal int units.
            try:
                min_f = float(min_val)
            except Exception:
                min_f = 0.0
            try:
                max_f = float(max_val)
            except Exception:
                # Fallback to a sensible default span
                max_f = max(min_f, 10.0)

            if max_f < min_f:
                min_f, max_f = max_f, min_f

            w = ScaleProgressWidget()
            w.setMinimum(int(round(min_f * 4)))
            w.setMaximum(int(round(max_f * 4)))
            w.setValue(int(round(min_f * 4)))

            self.step3_session_scales_form.addRow(QLabel(name + ":"), w)
            self.session_scale_value_edits.append((name, w))

    def set_initial_stimulation_params(
        self,
        left_frequency: str,
        left_cathode: str,
        left_anode: str,
        left_amp: str,
        left_pw: str,
        right_frequency: str,
        right_cathode: str,
        right_anode: str,
        right_amp: str,
        right_pw: str,
        program: str,
    ) -> None:
        """
        Set initial stimulation parameters from previous step.

        Args:
            left_frequency: Left stimulation frequency
            left_cathode: Left electrode cathode configuration
            left_anode: Left electrode anode configuration
            left_amp: Left amplitude
            left_pw: Left pulse width
            right_frequency: Right stimulation frequency
            right_cathode: Right electrode cathode configuration
            right_anode: Right electrode anode configuration
            right_amp: Right amplitude
            right_pw: Right pulse width
        """
        self.session_left_stim_freq_edit.setText(left_frequency)
        self.session_left_pw_edit.setText(left_pw)
        self.session_right_stim_freq_edit.setText(right_frequency)
        self.session_right_pw_edit.setText(right_pw)

        # Handle amplitude: if split (contains _), calculate total and set total in field
        # The AmplitudeSplitWidget will handle distribution based on cathode contacts
        left_total_amp = self._parse_amplitude_total(left_amp)
        right_total_amp = self._parse_amplitude_total(right_amp)
        self.session_left_amp_edit.setText(left_total_amp)
        self.session_right_amp_edit.setText(right_total_amp)

        if hasattr(self, "_current_model") and self._current_model:
            self.set_electrode_model(self._current_model)

        if hasattr(self, "group_combo") and program:
            try:
                self.group_combo.setCurrentText(str(program))
            except Exception:
                logger.warning(
                    "Failed to restore Step 3 program selection: %s",
                    program,
                    exc_info=True,
                )

        if self.left_canvas.model:
            self._apply_contact_text_to_canvas(
                self.left_canvas, left_anode, left_cathode
            )
        if self.right_canvas.model:
            self._apply_contact_text_to_canvas(
                self.right_canvas, right_anode, right_cathode
            )

        self.update_configuration_display()

    def _parse_amplitude_total(self, amp_str: str) -> str:
        """
        Parse amplitude string and return the total value.

        If the string contains underscores (e.g., "1.5_1.0"), calculate the sum.
        Otherwise, return the string as-is.
        """
        if not amp_str or "_" not in amp_str:
            return amp_str

        try:
            parts = amp_str.split("_")
            total = sum(float(p) for p in parts)
            # Format to 2 decimal places, removing trailing zeros
            return f"{total:.2f}".rstrip("0").rstrip(".")
        except ValueError, TypeError:
            return amp_str

    def _apply_contact_text_to_canvas(
        self, canvas: ElectrodeCanvas, anode_text: str, cathode_text: str
    ) -> None:
        """Parse anode/cathode token strings and set the corresponding canvas states."""
        model = canvas.model
        if not model:
            return

        canvas.contact_states.clear()
        canvas.case_state = ContactState.OFF
        parse_errors = 0

        def apply_tokens(text: str, state: int) -> None:
            nonlocal parse_errors
            if not text:
                return
            for token in text.split("_"):
                token = token.strip()
                if not token:
                    continue

                if token == "case":
                    canvas.case_state = state
                    continue

                if token.startswith("E") and len(token) >= 2:
                    try:
                        if token[-1].isalpha():
                            idx = int(token[1:-1])
                            seg_char = token[-1].lower()
                            seg_map = {"a": 0, "b": 1, "c": 2}
                            if seg_char in seg_map:
                                canvas.contact_states[(idx, seg_map[seg_char])] = state
                        else:
                            idx = int(token[1:])
                            if model.is_directional:
                                for seg in range(3):
                                    canvas.contact_states[(idx, seg)] = state
                            else:
                                canvas.contact_states[(idx, 0)] = state
                    except Exception:
                        parse_errors += 1
                        continue
                    continue

                if token.endswith(" ring"):
                    idx_str = token.replace(" ring", "")
                    try:
                        idx = int(idx_str)
                    except Exception:
                        parse_errors += 1
                        continue

                    if model.is_directional:
                        for seg in range(3):
                            canvas.contact_states[(idx, seg)] = state
                    else:
                        canvas.contact_states[(idx, 0)] = state
                    continue

                if model.is_directional and len(token) >= 2:
                    try:
                        idx = int(token[:-1])
                    except Exception:
                        parse_errors += 1
                        continue
                    seg_char = token[-1].lower()
                    seg_map = {"a": 0, "b": 1, "c": 2}
                    if seg_char in seg_map:
                        canvas.contact_states[(idx, seg_map[seg_char])] = state

        apply_tokens(anode_text, ContactState.ANODIC)
        apply_tokens(cathode_text, ContactState.CATHODIC)
        if parse_errors:
            logger.warning(
                "Skipped %d invalid contact tokens while restoring stimulation configuration",
                parse_errors,
            )

        is_valid, _ = StimulationRule.validate_configuration(
            canvas.contact_states, canvas.case_state
        )
        if not is_valid:
            canvas.contact_states.clear()
            canvas.case_state = ContactState.OFF

        canvas.update()
        # Refresh amplitude split widget for this canvas
        if canvas is self.left_canvas and hasattr(self, "left_amp_split"):
            cathode_labels = get_cathode_labels(self.left_canvas)
            is_single_grouped = self._is_single_grouped_directional(
                cathode_labels, self.left_canvas
            )
            self.left_amp_split.update_cathodes(cathode_labels, is_single_grouped)
        elif canvas is self.right_canvas and hasattr(self, "right_amp_split"):
            cathode_labels = get_cathode_labels(self.right_canvas)
            is_single_grouped = self._is_single_grouped_directional(
                cathode_labels, self.right_canvas
            )
            self.right_amp_split.update_cathodes(cathode_labels, is_single_grouped)

    def _edit_program_names(self) -> None:
        """Open dialog to edit custom program names."""
        program_config = get_program_config_manager()
        custom_programs = program_config.get_custom_programs()
        default_programs = ProgramConfigManager.DEFAULT_PROGRAMS

        dialog = QDialog(self)
        dialog.setWindowTitle("Edit Program Names")
        dialog.setMinimumWidth(400)

        layout = QVBoxLayout(dialog)

        # List widget to show custom programs
        list_widget = QListWidget()
        list_widget.addItems(custom_programs)
        layout.addWidget(list_widget)

        # Input for new program name
        input_layout = QHBoxLayout()
        new_program_edit = QLineEdit()
        new_program_edit.setPlaceholderText("New program name...")
        input_layout.addWidget(new_program_edit)

        add_btn = QPushButton("Add")
        add_btn.clicked.connect(
            lambda: self._add_program_to_list(
                new_program_edit.text(), list_widget, program_config
            )
        )
        input_layout.addWidget(add_btn)
        layout.addLayout(input_layout)

        # Edit and remove buttons
        button_layout = QHBoxLayout()
        edit_btn = QPushButton("Edit Selected")
        remove_btn = QPushButton("Remove Selected")
        button_layout.addWidget(edit_btn)
        button_layout.addWidget(remove_btn)
        layout.addLayout(button_layout)

        # Connect edit/remove buttons
        edit_btn.clicked.connect(
            lambda: self._edit_selected_program(
                list_widget, program_config, default_programs
            )
        )
        remove_btn.clicked.connect(
            lambda: self._remove_selected_program(
                list_widget, program_config, default_programs
            )
        )

        # Dialog buttons
        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.accepted.connect(dialog.accept)
        buttons.rejected.connect(dialog.reject)
        layout.addWidget(buttons)

        if dialog.exec() == QDialog.Accepted:
            # Refresh combo box with updated programs
            current_text = self.group_combo.currentText()
            programs = program_config.get_all_programs()
            self.group_combo.clear()
            self.group_combo.addItems(programs)
            if current_text in programs:
                self.group_combo.setCurrentText(current_text)
            else:
                self.group_combo.setCurrentIndex(0)

    def _add_program_to_list(
        self, name: str, list_widget: QListWidget, program_config: ProgramConfigManager
    ) -> None:
        """Add a new program to the list."""
        if not name or name in ProgramConfigManager.DEFAULT_PROGRAMS:
            QMessageBox.warning(
                self, "Error", "Program name cannot be empty or match default programs."
            )
            return

        if program_config.add_program(name):
            list_widget.addItem(name)
        else:
            QMessageBox.warning(self, "Error", "Program name already exists.")

    def _edit_selected_program(
        self,
        list_widget: QListWidget,
        program_config: ProgramConfigManager,
        default_programs: list[str],
    ) -> None:
        """Edit the selected program name."""
        current_item = list_widget.currentItem()
        if not current_item:
            QMessageBox.warning(self, "Error", "No program selected.")
            return

        old_name = current_item.text()
        from PySide6.QtWidgets import QInputDialog

        new_name, ok = QInputDialog.getText(
            self, "Edit Program", "New program name:", QLineEdit.Normal, old_name
        )
        if ok and new_name:
            if new_name in default_programs:
                QMessageBox.warning(
                    self, "Error", "Cannot rename to a default program name."
                )
                return

            if program_config.update_program(old_name, new_name):
                current_item.setText(new_name)
            else:
                QMessageBox.warning(self, "Error", "Failed to update program name.")

    def _remove_selected_program(
        self,
        list_widget: QListWidget,
        program_config: ProgramConfigManager,
        default_programs: list[str],
    ) -> None:
        """Remove the selected program name."""
        current_item = list_widget.currentItem()
        if not current_item:
            QMessageBox.warning(self, "Error", "No program selected.")
            return

        name = current_item.text()
        if name in default_programs:
            QMessageBox.warning(self, "Error", "Cannot remove default programs.")
            return

        reply = QMessageBox.question(
            self,
            "Confirm",
            f"Remove program '{name}'?",
            QMessageBox.Yes | QMessageBox.No,
        )
        if reply == QMessageBox.Yes:
            if program_config.remove_program(name):
                list_widget.takeItem(list_widget.row(current_item))
            else:
                QMessageBox.warning(self, "Error", "Failed to remove program.")
