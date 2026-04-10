"""
Step 1 view - Initial settings and clinical scales.

This module contains the view for the first step of the wizard where users
configure initial settings, stimulation parameters, and clinical scales.
"""

import os
from collections.abc import Callable
from datetime import datetime

from PySide6.QtCore import QSize, Qt
from PySide6.QtGui import QDoubleValidator, QIntValidator
from PySide6.QtWidgets import (
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QFormLayout,
    QFrame,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
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
    PRESET_BUTTONS,
    STIMULATION_LIMITS,
)
from ..config_electrode_models import (
    ELECTRODE_MODELS,
    MANUFACTURERS,
    ContactState,
    get_all_manufacturers,
)
from ..models import ElectrodeCanvas
from ..ui import (
    AmplitudeSplitWidget,
    FileDropLineEdit,
    IncrementWidget,
    get_cathode_labels,
)
from ..ui.clinical_scales_settings_dialog import ClinicalScalesSettingsDialog
from ..utils.program_config_manager import (
    ProgramConfigManager,
    get_program_config_manager,
)
from ..utils.scale_preset_manager import get_scale_preset_manager
from .base_view import BaseStepView


class Step1View(BaseStepView):
    """
    First step view for initial configuration.

    This view handles:
    - File selection for TSV output
    - Initial stimulation parameters
    - Clinical scales configuration
    - Initial notes
    """

    def __init__(self, parent_style=None):
        """
        Initialize Step 1 view.

        Args:
            parent_style: Parent widget style for icon access (deprecated, kept for compatibility)
        """
        super().__init__()
        # parent_style is now set in BaseStepView.__init__
        self.clinical_scales_rows: list[tuple[QLineEdit, QLineEdit, QHBoxLayout]] = []
        self.current_file_mode = None  # Track file mode: 'existing', 'new', or None
        self.next_block_id: int | None = None
        self.active_preset_button: QPushButton | None = None  # Track active preset
        self.clinical_presets: dict[str, list[str]] = self._load_clinical_presets()

        self.left_canvas = ElectrodeCanvas()
        self.right_canvas = ElectrodeCanvas()

        # Electrode disable state
        self.left_electrode_enabled = True
        self.right_electrode_enabled = True
        self._left_selection_valid = True
        self._right_selection_valid = True
        self.left_canvas.validation_callback = self._on_left_canvas_validation
        self.right_canvas.validation_callback = self._on_right_canvas_validation

        self._setup_ui()

    def get_header_title(self) -> str:
        """Return the wizard header title for Step 1."""
        return "Clinical Programming Session Setup"

    def _is_single_grouped_directional(self, cathode_labels: list[str], canvas) -> bool:
        """Check if a single cathode label represents a grouped directional contact."""
        if len(cathode_labels) != 1 or not canvas or not canvas.model:
            return False

        lbl = cathode_labels[0]
        # Check if this is a grouped contact (no segment suffix) that could be directional
        if len(lbl) >= 2 and lbl[0] == "E" and lbl[1:].isdigit():
            try:
                contact_idx = int(lbl[1:])
                return (
                    canvas.model.is_directional
                    and canvas.model.is_level_directional(contact_idx)
                )
            except ValueError, IndexError:
                pass
        return False

    def _on_left_canvas_validation(self, is_valid: bool, error_msg: str) -> None:
        """Callback when left electrode canvas validation state changes."""
        self._left_selection_valid = is_valid
        self.update_configuration_display()
        if hasattr(self, "left_amp_split"):
            left_labels = get_cathode_labels(self.left_canvas)
            left_is_grouped = self._is_single_grouped_directional(
                left_labels, self.left_canvas
            )
            self.left_amp_split.update_cathodes(left_labels, left_is_grouped)

    def _on_right_canvas_validation(self, is_valid: bool, error_msg: str) -> None:
        """Callback when right electrode canvas validation state changes."""
        self._right_selection_valid = is_valid
        self.update_configuration_display()
        if hasattr(self, "right_amp_split"):
            right_labels = get_cathode_labels(self.right_canvas)
            right_is_grouped = self._is_single_grouped_directional(
                right_labels, self.right_canvas
            )
            self.right_amp_split.update_cathodes(right_labels, right_is_grouped)

    def _setup_ui(self) -> None:
        """Set up the UI layout."""

        # Left side: File + Initial settings
        left_widget = QWidget()
        left_layout = QVBoxLayout(left_widget)
        left_layout.setContentsMargins(0, 0, 0, 0)
        upload_group = self._create_upload_tsv_group()
        settings_group = self._create_settings_group()
        left_layout.addWidget(upload_group)
        left_layout.addWidget(settings_group)
        left_widget.setMinimumWidth(500)

        # Right side: Clinical scales and notes
        right_widget = QWidget()
        right_layout = QVBoxLayout(right_widget)
        right_layout.setContentsMargins(0, 0, 0, 0)
        clinical_group = self._create_clinical_scales_group()
        notes_group = self._create_notes_group()
        right_layout.addWidget(clinical_group)
        right_layout.addWidget(notes_group)
        right_widget.setMinimumWidth(400)

        # Splitter: right panel shrinks first (stretch=1), left stays stable (stretch=0)
        splitter = QSplitter(Qt.Horizontal)
        splitter.addWidget(left_widget)
        splitter.addWidget(right_widget)
        splitter.setStretchFactor(0, 0)  # left: does not absorb resize changes
        splitter.setStretchFactor(1, 1)  # right: absorbs resize changes first
        splitter.setChildrenCollapsible(False)

        self.main_layout.addWidget(splitter)

        self.next_button = QPushButton("Next")
        self.next_button.setIcon(self.parent_style.standardIcon(QStyle.SP_ArrowForward))
        self.next_button.setIconSize(QSize(16, 16))
        self.next_button.setMaximumWidth(120)

    def _create_settings_group(self) -> QGroupBox:
        """Create the initial settings group box."""
        gb_init = QGroupBox("Initial settings")
        gb_init.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)

        container_layout = QHBoxLayout()

        sidebar_layout = QVBoxLayout()

        model_group = QGroupBox("Electrode")
        model_layout = QVBoxLayout()

        manufacturer_label = QLabel("Manufacturer:")
        self.manufacturer_combo = QComboBox()
        self.manufacturer_combo.addItem("All Manufacturers")
        self.manufacturer_combo.addItems(get_all_manufacturers())
        self.manufacturer_combo.currentTextChanged.connect(self.on_manufacturer_changed)

        model_label = QLabel("Model:")
        self.model_combo = QComboBox()
        self.populate_models("All Manufacturers")
        # Default to Medtronic SenSight B33005
        idx = self.model_combo.findText("Medtronic SenSight B33005")
        if idx >= 0:
            self.model_combo.setCurrentIndex(idx)
        self.model_combo.currentTextChanged.connect(self.on_model_changed)

        model_layout.addWidget(manufacturer_label)
        model_layout.addWidget(self.manufacturer_combo)
        model_layout.addWidget(model_label)
        model_layout.addWidget(self.model_combo)
        model_group.setLayout(model_layout)

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
        self.group_combo.setCurrentText("None")
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
        self.left_stim_freq_edit = QLineEdit()
        self.left_stim_freq_edit.setMaximumWidth(80)
        self.left_stim_freq_edit.setPlaceholderText(PLACEHOLDERS["frequency"])
        self.left_stim_freq_edit.setValidator(
            QIntValidator(freq_limits["min"], freq_limits["max"])
        )
        left_freq_widget = IncrementWidget(
            self.left_stim_freq_edit,
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
        self.left_amp_edit = QLineEdit()
        self.left_amp_edit.setMaximumWidth(80)
        self.left_amp_edit.setPlaceholderText(PLACEHOLDERS["amplitude"])
        self.left_amp_edit.setValidator(
            QDoubleValidator(
                amp_limits["min"], amp_limits["max"], amp_limits["decimals"]
            )
        )
        left_amp_widget = IncrementWidget(
            self.left_amp_edit,
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
        self.left_pw_edit = QLineEdit()
        self.left_pw_edit.setMaximumWidth(80)
        self.left_pw_edit.setPlaceholderText(PLACEHOLDERS["pulse_width"])
        self.left_pw_edit.setValidator(
            QIntValidator(pw_limits["min"], pw_limits["max"])
        )
        left_pw_widget = IncrementWidget(
            self.left_pw_edit,
            step1=pw_limits["step1"],
            step2=pw_limits["step2"],
            decimals=0,
            min_value=pw_limits["min"],
            max_value=pw_limits["max"],
        )
        pw_row.addWidget(left_pw_widget)

        self.left_amp_split = AmplitudeSplitWidget(self.left_amp_edit)

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
        self.right_stim_freq_edit = QLineEdit()
        self.right_stim_freq_edit.setMaximumWidth(80)
        self.right_stim_freq_edit.setPlaceholderText(PLACEHOLDERS["frequency"])
        self.right_stim_freq_edit.setValidator(
            QIntValidator(freq_limits["min"], freq_limits["max"])
        )
        right_freq_widget = IncrementWidget(
            self.right_stim_freq_edit,
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
        self.right_amp_edit = QLineEdit()
        self.right_amp_edit.setMaximumWidth(80)
        self.right_amp_edit.setPlaceholderText(PLACEHOLDERS["amplitude"])
        self.right_amp_edit.setValidator(
            QDoubleValidator(
                amp_limits["min"], amp_limits["max"], amp_limits["decimals"]
            )
        )
        right_amp_widget = IncrementWidget(
            self.right_amp_edit,
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
        self.right_pw_edit = QLineEdit()
        self.right_pw_edit.setMaximumWidth(80)
        self.right_pw_edit.setPlaceholderText(PLACEHOLDERS["pulse_width"])
        self.right_pw_edit.setValidator(
            QIntValidator(pw_limits["min"], pw_limits["max"])
        )
        right_pw_widget = IncrementWidget(
            self.right_pw_edit,
            step1=pw_limits["step1"],
            step2=pw_limits["step2"],
            decimals=0,
            min_value=pw_limits["min"],
            max_value=pw_limits["max"],
        )
        pw_row.addWidget(right_pw_widget)

        self.right_amp_split = AmplitudeSplitWidget(self.right_amp_edit)

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

        sidebar_layout.addWidget(model_group)
        sidebar_layout.addWidget(group_row)
        sidebar_layout.addWidget(self.left_group)
        sidebar_layout.addWidget(self.right_group)
        sidebar_layout.addStretch(1)

        # Wrap sidebar in a scroll area so it scrolls when rows overflow
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

        layout = QVBoxLayout(gb_init)
        layout.addLayout(container_layout)

        if self.model_combo.count() > 0:
            self.on_model_changed(self.model_combo.currentText())

        return gb_init

    # functions for the electrode visualization
    def populate_models(self, manufacturer):
        """Populate model combo box based on selected manufacturer"""
        self.model_combo.blockSignals(
            True
        )  # Prevent triggering on_model_changed during population
        self.model_combo.clear()

        if manufacturer == "All Manufacturers":
            # Add all models sorted alphabetically
            all_models = sorted(ELECTRODE_MODELS.keys())
            self.model_combo.addItems(all_models)
        else:
            # Add models for specific manufacturer
            models = MANUFACTURERS.get(manufacturer, [])
            self.model_combo.addItems(models)

        self.model_combo.blockSignals(False)

    def on_manufacturer_changed(self, manufacturer):
        """Handle manufacturer selection change"""
        self.populate_models(manufacturer)
        if self.model_combo.count() > 0:
            self.on_model_changed(self.model_combo.currentText())

    def on_model_changed(self, model_name):
        """Handle model selection change"""
        if not model_name:
            return

        model = ELECTRODE_MODELS.get(model_name)
        if not model:
            return

        self.left_canvas.set_model(model)
        self.right_canvas.set_model(model)

        self.update_configuration_display()

    def update_configuration_display(self):
        """Update stimulation configuration display"""
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
                # Force complete style refresh
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
                # Force complete style refresh
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

                if model.is_directional and model.is_level_directional(contact_idx):
                    # This contact has segments - show segment label
                    segment_labels = ["a", "b", "c"]
                    contact_name = f"C{contact_idx}{segment_labels[seg_idx]}"
                else:
                    # This contact is a ring contact - no segment label
                    contact_name = f"C{contact_idx}"

                lines.append(f"  &bull; {contact_name}: {state_str}")
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
                    if all(s == ContactState.ANODIC for s in seg_states):
                        anode_items.append(f"E{contact_idx}")
                        continue
                    if all(s == ContactState.CATHODIC for s in seg_states):
                        cathode_items.append(f"E{contact_idx}")
                        continue

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

    def _apply_contact_text_to_canvas(
        self, canvas: ElectrodeCanvas, anode_text: str, cathode_text: str
    ) -> None:
        """Parse anode/cathode token strings and set the corresponding canvas states."""
        model = canvas.model
        if not model:
            return

        canvas.contact_states.clear()
        canvas.case_state = ContactState.OFF

        def apply_tokens(text: str, state: ContactState) -> None:
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
                    # Handle new E0, E1a format
                    try:
                        if token[-1].isalpha():
                            # Directional contact like E1a
                            idx = int(token[1:-1])
                            seg_char = token[-1].lower()
                            seg_map = {"a": 0, "b": 1, "c": 2}
                            if seg_char in seg_map:
                                canvas.contact_states[(idx, seg_map[seg_char])] = state
                        else:
                            # Ring contact like E0
                            idx = int(token[1:])
                            if model.is_directional:
                                for seg in range(3):
                                    canvas.contact_states[(idx, seg)] = state
                            else:
                                canvas.contact_states[(idx, 0)] = state
                    except Exception:
                        continue
                    continue

                # Legacy support for old format
                if token.endswith(" ring"):
                    idx_str = token.replace(" ring", "")
                    try:
                        idx = int(idx_str)
                    except Exception:
                        continue

                    if model.is_directional:
                        for seg in range(3):
                            canvas.contact_states[(idx, seg)] = state
                    else:
                        canvas.contact_states[(idx, 0)] = state
                    continue

                if model.is_directional and len(token) >= 2 and token[0].isdigit():
                    try:
                        idx = int(token[:-1])
                    except Exception:
                        continue
                    seg_char = token[-1].lower()
                    seg_map = {"a": 0, "b": 1, "c": 2}
                    if seg_char in seg_map:
                        canvas.contact_states[(idx, seg_map[seg_char])] = state

        apply_tokens(anode_text, ContactState.ANODIC)
        apply_tokens(cathode_text, ContactState.CATHODIC)

        canvas.update()
        # Refresh amplitude split widget for this canvas
        if canvas is self.left_canvas and hasattr(self, "left_amp_split"):
            left_labels = get_cathode_labels(self.left_canvas)
            left_is_grouped = self._is_single_grouped_directional(
                left_labels, self.left_canvas
            )
            self.left_amp_split.update_cathodes(left_labels, left_is_grouped)
        elif canvas is self.right_canvas and hasattr(self, "right_amp_split"):
            right_labels = get_cathode_labels(self.right_canvas)
            right_is_grouped = self._is_single_grouped_directional(
                right_labels, self.right_canvas
            )
            self.right_amp_split.update_cathodes(right_labels, right_is_grouped)

    def reset_all(self):
        """Reset all contacts and case"""
        self.left_canvas.contact_states.clear()
        self.left_canvas.case_state = ContactState.OFF
        self.right_canvas.contact_states.clear()
        self.right_canvas.case_state = ContactState.OFF
        self.left_canvas.update()
        self.right_canvas.update()
        self.update_configuration_display()
        if hasattr(self, "left_amp_split"):
            self.left_amp_split.update_cathodes([])
        if hasattr(self, "right_amp_split"):
            self.right_amp_split.update_cathodes([])

    def export_configuration(self):
        """Export current configuration to console"""
        left_model = self.left_canvas.model
        right_model = self.right_canvas.model
        if not left_model or not right_model:
            return

        print("\n" + "=" * 60)
        print("DBS STIMULATION CONFIGURATION")
        print("=" * 60)
        print(f"Model: {left_model.name}")
        print(f"Timestamp: {datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S')}")
        print()

        print(
            f"LEFT  Anode: {self.get_left_anode_text()} | Cathode: {self.get_left_cathode_text()}"
        )
        print(
            f"RIGHT Anode: {self.get_right_anode_text()} | Cathode: {self.get_right_cathode_text()}"
        )
        print("=" * 60 + "\n")

    def _create_upload_tsv_group(self) -> QGroupBox:
        """Create the file upload group with drop zone, Open, and New buttons."""
        gb_upload = QGroupBox("Upload TSV file")
        gb_upload.setFixedHeight(100)
        gb_upload.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)

        layout = QHBoxLayout(gb_upload)

        self.file_path_edit = FileDropLineEdit(self._on_file_dropped)
        self.file_path_edit.setFixedHeight(45)
        self.file_path_edit.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
        self.file_path_edit.setReadOnly(True)
        self.file_path_edit.setClearButtonEnabled(False)
        self.file_path_edit.textChanged.connect(self._on_file_path_changed)
        self.file_path_edit.setPlaceholderText(
            "Drop a .tsv annotation file or use the buttons"
        )

        open_button = QPushButton()
        open_button.setText("Open")
        open_button.setMaximumWidth(90)
        open_button.setFixedHeight(45)
        open_button.setToolTip("Open existing file")
        open_button.clicked.connect(self.open_existing_file)

        create_button = QPushButton()
        create_button.setText("New")
        create_button.setMaximumWidth(90)
        create_button.setFixedHeight(45)
        create_button.setToolTip("Create new file")
        create_button.clicked.connect(self.create_new_file)

        layout.addWidget(self.file_path_edit, 1)
        layout.addWidget(open_button)
        layout.addWidget(create_button)

        return gb_upload

    def _create_clinical_scales_group(self) -> QGroupBox:
        """Create the clinical scales group box."""
        gb_clinical = QGroupBox("Clinical scales")
        gb_clinical.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)

        layout = QVBoxLayout(gb_clinical)

        # Preset buttons
        preset_row = QHBoxLayout()
        self.preset_buttons = []
        # preset_row.addStretch(1)

        # Settings button
        settings_btn = QPushButton()
        settings_btn.setIcon(self._create_settings_icon())
        settings_btn.setObjectName("settings_clincal_scales")
        settings_btn.setToolTip("Settings clinical scales")
        settings_btn.clicked.connect(self._open_clinical_scales_settings)
        preset_row.addWidget(settings_btn)

        layout.addLayout(preset_row)

        # Store the layout for later updates
        self.preset_row_layout = preset_row

        # Build buttons from current presets (JSON) once the row exists
        self._refresh_preset_buttons()

        # Container for dynamic scale rows - expands to show all rows
        scroll_content = QWidget()
        # scroll_content.setStyleSheet("background: transparent; border: none;")
        scroll_content.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.clinical_scales_container = QVBoxLayout(scroll_content)
        self.clinical_scales_container.setContentsMargins(0, 0, 0, 0)

        # Scrollable area - will only scroll when user resizes window smaller
        scroll_area = QScrollArea()
        scroll_area.setStyleSheet("""
            QScrollArea {
                background: transparent;
                border: none;
            }
            QScrollArea > QWidget > QWidget {
                background: transparent;
            }
        """)
        # scroll_area.setAttribute(Qt.WA_TranslucentBackground, True)
        scroll_area.setWidgetResizable(True)
        scroll_area.setFrameShape(QScrollArea.NoFrame)
        scroll_area.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        scroll_area.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        scroll_area.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        scroll_area.setWidget(scroll_content)

        layout.addWidget(scroll_area)

        return gb_clinical

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
                    widget.setGraphicsEffect(None)
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
                    widget.setGraphicsEffect(None)

    def _create_notes_group(self) -> QGroupBox:
        """Create the initial notes group box."""
        gb_notes = QGroupBox("Initial notes")
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

        self.notes_edit = QTextEdit()
        self.notes_edit.setPlaceholderText("Type your notes here...")
        self.notes_edit.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.notes_edit.setMinimumHeight(100)
        layout.addWidget(self.notes_edit)

        return gb_notes

    def _edit_program_names(self) -> None:
        """Open dialog to edit custom program names."""
        from PySide6.QtWidgets import QLineEdit, QListWidget, QVBoxLayout

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
                self.group_combo.setCurrentText("None")

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

    def _on_file_dropped(self, file_path: str) -> None:
        """Handle a file dropped onto the line-edit widget."""
        if file_path:
            self._load_existing_file(file_path)

    def _on_file_path_changed(self, text: str) -> None:
        """Reset file mode when the path field is cleared."""
        if not text.strip():
            self.current_file_mode = None
            self.next_block_id = None

    def open_existing_file(self) -> None:
        """Open a file dialog to select an existing TSV file."""
        current_path = self.file_path_edit.text().strip()
        start_dir = os.path.dirname(current_path) if current_path else ""

        file_path, _ = QFileDialog.getOpenFileName(
            self,
            "Open Existing TSV File",
            start_dir,
            "TSV Files (*.tsv);;All Files (*)",
        )
        if file_path:
            self._load_existing_file(file_path)

    def _load_existing_file(self, file_path: str) -> None:
        """Load an existing TSV file and restore the latest session's settings."""
        import csv

        initial_rows = {}  # session_id -> row data
        max_session_id = -1
        max_block = -1

        try:
            with open(file_path, newline="", encoding="utf-8") as f:
                reader = csv.DictReader(f, delimiter="\t")
                for row in reader:
                    try:
                        bid_raw = row.get("block_id", "")
                        if bid_raw is None or bid_raw == "":
                            continue
                        bid = int(float(bid_raw))
                    except Exception:
                        continue

                    max_block = max(max_block, bid)

                    # Look for initial entries (is_initial = 1)
                    is_initial = row.get("is_initial", "0")
                    if is_initial == "1":
                        session_id_raw = row.get("session_ID", "")
                        if session_id_raw is None or session_id_raw == "":
                            continue
                        try:
                            session_id = int(float(session_id_raw))
                            # Keep the row with the highest session_id for each session
                            if (
                                session_id not in initial_rows
                                or bid > initial_rows[session_id]["block_id"]
                            ):
                                initial_rows[session_id] = {"row": row, "block_id": bid}
                            max_session_id = max(max_session_id, session_id)
                        except Exception:
                            continue

            self.file_path_edit.setText(file_path)
            self.current_file_mode = "existing"
            self.next_block_id = max_block + 1

            # Load data from the latest initial session (highest session_id)
            if max_session_id >= 0 and max_session_id in initial_rows:
                latest_initial = initial_rows[max_session_id]["row"]

                # Load electrode model (if present in file)
                model_name = latest_initial.get("electrode_model", None)
                if model_name not in (None, "") and hasattr(self, "model_combo"):
                    try:
                        self.model_combo.setCurrentText(str(model_name))
                        self.on_model_changed(self.model_combo.currentText())
                    except Exception:
                        pass

                # Load program (backward compatibility: use group_ID if program_ID not present)
                program_val = latest_initial.get("program_ID") or latest_initial.get(
                    "group_ID"
                )
                if program_val not in (None, "") and hasattr(self, "group_combo"):
                    try:
                        self.group_combo.setCurrentText(str(program_val))
                    except Exception:
                        pass

                # Load clinical scales
                block0_scales = []
                latest_block_id = initial_rows[max_session_id]["block_id"]
                # Re-read file to get scales from the latest initial block only
                with open(file_path, newline="", encoding="utf-8") as f:
                    reader = csv.DictReader(f, delimiter="\t")
                    for row in reader:
                        try:
                            bid = int(float(row.get("block_id", "")))
                            sid = int(float(row.get("session_ID", "")))
                        except ValueError, TypeError:
                            continue
                        if (
                            sid == max_session_id
                            and bid == latest_block_id
                            and row.get("is_initial") == "1"
                        ):
                            sname = row.get("scale_name", None)
                            sval = row.get("scale_value", None)
                            if sname not in (None, ""):
                                block0_scales.append(
                                    (str(sname), "" if sval is None else str(sval))
                                )

                # Deduplicate scales by name (keep last occurrence)
                seen_scales = set()
                deduplicated_scales = []
                for name, value in reversed(block0_scales):
                    if name not in seen_scales:
                        seen_scales.add(name)
                        deduplicated_scales.append((name, value))
                block0_scales = list(reversed(deduplicated_scales))

                # Load notes
                notes_val = latest_initial.get("notes", None)
                if notes_val not in (None, "") and hasattr(self, "notes_edit"):
                    try:
                        self.notes_edit.setPlainText(str(notes_val))
                    except Exception:
                        self.notes_edit.setText(str(notes_val))

                # Load stimulation parameters
                self._load_stimulation_parameters(latest_initial)

                # Update clinical scales UI
                # Store scales for later if callbacks not ready yet
                self._pending_scales = block0_scales if block0_scales else []

                if (
                    block0_scales
                    and hasattr(self, "on_add_callback")
                    and hasattr(self, "on_remove_callback")
                ):
                    for _, _, row_layout in self.clinical_scales_rows:
                        while row_layout.count():
                            item = row_layout.takeAt(0)
                            widget = item.widget()
                            if widget is not None:
                                widget.deleteLater()
                        self.clinical_scales_container.removeItem(row_layout)
                    self.clinical_scales_rows = []

                    # Remove any existing stretches from container
                    while self.clinical_scales_container.count():
                        item = self.clinical_scales_container.takeAt(0)
                        if item.spacerItem():
                            # Just remove the stretch, no widget to delete
                            continue
                        elif item.widget():
                            item.widget().deleteLater()

                    for scale_name, scale_value in block0_scales:
                        self._add_clinical_scale_row(
                            scale_name,
                            scale_value,
                            with_minus=True,
                            on_remove=self.on_remove_callback,
                        )

                    self._add_clinical_scale_row(
                        "", with_plus=True, on_add=self.on_add_callback
                    )
                    self.clinical_scales_container.addStretch()
                    self._pending_scales = []  # Clear pending since we loaded them

                    # Detect and select matching clinical preset
                    loaded_scale_names = [name for name, _ in block0_scales]
                    for preset_name, preset_scales in self.clinical_presets.items():
                        # Check if loaded scales match or are a subset of preset scales
                        if all(name in preset_scales for name in loaded_scale_names):
                            # Select the matching preset button
                            preset_btn = self.get_preset_button(preset_name)
                            if preset_btn:
                                self._set_active_preset_button(preset_btn)

                self.update_configuration_display()

        except Exception as e:
            QMessageBox.warning(self, "Error", f"Failed to load file: {str(e)}")

    def _parse_amplitude_for_display(self, amplitude_str: str) -> str:
        """Parse amplitude string for display: sum underscore-separated values.

        If the string contains underscores (e.g., "2.5_2.5"), sum the values
        and return the total ("5.0"). Otherwise return the original string.
        """
        if not amplitude_str:
            return amplitude_str

        # Check if this is a split amplitude (contains underscore)
        if "_" in amplitude_str:
            try:
                # Split and sum all numeric parts
                parts = amplitude_str.split("_")
                total = sum(float(p) for p in parts if p.strip())
                # Format with at least one decimal place
                return (
                    f"{total:.1f}".rstrip("0").rstrip(".")
                    if "." in f"{total:.1f}"
                    else str(int(total))
                )
            except ValueError, TypeError:
                # If parsing fails, return original
                return amplitude_str

        return amplitude_str

    def _load_stimulation_parameters(self, row: dict) -> None:
        """Restore stimulation edits + electrode selections from a TSV row."""
        # Text fields
        try:
            self.left_stim_freq_edit.setText(str(row.get("left_stim_freq", "") or ""))
            # Parse amplitude to show total sum if split
            left_amp_raw = str(row.get("left_amplitude", "") or "")
            self.left_amp_edit.setText(self._parse_amplitude_for_display(left_amp_raw))
            self.left_pw_edit.setText(str(row.get("left_pulse_width", "") or ""))
            self.right_stim_freq_edit.setText(str(row.get("right_stim_freq", "") or ""))
            # Parse amplitude to show total sum if split
            right_amp_raw = str(row.get("right_amplitude", "") or "")
            self.right_amp_edit.setText(
                self._parse_amplitude_for_display(right_amp_raw)
            )
            self.right_pw_edit.setText(str(row.get("right_pulse_width", "") or ""))
        except Exception:
            pass

        # Electrode selections
        left_anode = str(row.get("left_anode", "") or "")
        left_cathode = str(row.get("left_cathode", "") or "")
        right_anode = str(row.get("right_anode", "") or "")
        right_cathode = str(row.get("right_cathode", "") or "")

        try:
            self._apply_contact_text_to_canvas(
                self.left_canvas, left_anode, left_cathode
            )
            self._apply_contact_text_to_canvas(
                self.right_canvas, right_anode, right_cathode
            )
        except Exception:
            pass

        self.update_configuration_display()

        # Update amplitude split widgets with original split values if present
        left_amp_raw = str(row.get("left_amplitude", "") or "")
        right_amp_raw = str(row.get("right_amplitude", "") or "")

        if hasattr(self, "left_amp_split") and left_amp_raw and "_" in left_amp_raw:
            self.left_amp_split.set_amplitude_from_split(left_amp_raw)

        if hasattr(self, "right_amp_split") and right_amp_raw and "_" in right_amp_raw:
            self.right_amp_split.set_amplitude_from_split(right_amp_raw)

    def create_new_file(self) -> None:
        """Create new file with BIDS-style naming."""
        from datetime import datetime

        # First, ask for patient ID and session number
        dialog = QDialog(self)
        dialog.setWindowTitle("New Session Information")
        dialog.setMinimumWidth(300)

        layout = QFormLayout(dialog)

        patient_edit = QLineEdit()
        patient_edit.setText("01")

        run_edit = QLineEdit()
        run_edit.setText("01")

        layout.addRow("Patient ID:", patient_edit)
        layout.addRow("Run:", run_edit)

        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.accepted.connect(dialog.accept)
        buttons.rejected.connect(dialog.reject)
        layout.addRow(buttons)

        if dialog.exec() != QDialog.Accepted:
            return

        patient_id = patient_edit.text().strip() or "01"
        session_num = str(datetime.now().astimezone().strftime("%Y%m%d"))
        run_num = run_edit.text().strip() or "01"

        # Store for later use in report
        self.bids_patient_id = patient_id
        self.bids_session_num = session_num
        self.bids_run_num = run_num

        current_path = self.file_path_edit.text().strip()
        start_dir = os.path.dirname(current_path) if current_path else ""

        subject_id = f"sub-{patient_id}"
        session_id = f"ses-{session_num}"
        task = "task-programming"
        run_id = f"run-{run_num}"
        default_name = f"{subject_id}_{session_id}_{task}_{run_id}_events.tsv"

        default_path = (
            os.path.join(start_dir, default_name) if start_dir else default_name
        )

        file_path, _ = QFileDialog.getSaveFileName(
            self,
            "Create New TSV File",
            default_path,
            "TSV Files (*.tsv);;All Files (*)",
        )

        if file_path:
            if not file_path.endswith(".tsv"):
                file_path += ".tsv"
            self.file_path_edit.setText(file_path)
            self.current_file_mode = "new"
            self.next_block_id = None

    def get_preset_button(self, preset_name: str) -> QPushButton:
        """Get a preset button by name."""
        return self.findChild(QPushButton, f"preset_{preset_name}")

    def update_clinical_scales(
        self,
        preset_scales: list[str],
        on_add_callback: Callable,
        on_remove_callback: Callable,
    ) -> None:
        """
        Update the clinical scales UI with the given scales.

        Args:
            preset_scales: List of scale names to display
            on_add_callback: Callback for add button
            on_remove_callback: Callback for remove button
        """
        # Store callbacks for preset buttons
        self.on_add_callback = on_add_callback
        self.on_remove_callback = on_remove_callback

        # Check if we have pending scales from file load
        if hasattr(self, "_pending_scales") and self._pending_scales:
            # Use pending scales instead of preset_scales
            scales_to_load = self._pending_scales
            self._pending_scales = []
        else:
            # Convert preset_scales to tuples (name, value)
            scales_to_load = []
            for item in preset_scales:
                if isinstance(item, tuple):
                    scales_to_load.append(item)
                else:
                    # Legacy: just a name string, convert to tuple
                    scales_to_load.append((item, ""))

        # Clear existing rows
        for _, _, row_layout in self.clinical_scales_rows:
            while row_layout.count():
                item = row_layout.takeAt(0)
                widget = item.widget()
                if widget is not None:
                    widget.deleteLater()
            self.clinical_scales_container.removeItem(row_layout)
        self.clinical_scales_rows = []

        # Remove any existing stretches from container
        while self.clinical_scales_container.count():
            item = self.clinical_scales_container.takeAt(0)
            if item.spacerItem():
                # Just remove the stretch, no widget to delete
                continue
            elif item.widget():
                item.widget().deleteLater()

        # Add scales (either from pending or preset)
        for item in scales_to_load:
            if isinstance(item, tuple):
                name, value = item
                self._add_clinical_scale_row(
                    name,
                    value,
                    with_minus=True,
                    on_remove=on_remove_callback,
                )
            else:
                # Legacy: just a name string
                self._add_clinical_scale_row(
                    item, with_minus=True, on_remove=on_remove_callback
                )

        # Add empty row with add button
        self._add_clinical_scale_row("", with_plus=True, on_add=on_add_callback)

        # Add stretch at the bottom to push content up
        self.clinical_scales_container.addStretch()

        # Connect preset buttons to their respective scales (only now that callbacks are available)
        self._connect_preset_buttons()

    def _connect_preset_buttons(self):
        """Connect all preset buttons to their respective scales."""
        import warnings

        for btn in self.preset_buttons:
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", RuntimeWarning)
                try:
                    btn.clicked.disconnect()
                except RuntimeError:
                    pass

            # Get the preset name from object name
            preset_name = btn.objectName().replace("preset_", "")

            # Get the scales for this preset from clinical_presets
            if preset_name in self.clinical_presets:
                preset_scales = self.clinical_presets[preset_name]

                if preset_scales and isinstance(preset_scales, list):
                    # Create a proper closure using a function
                    def create_preset_handler(scales, button):
                        def handler():
                            self._set_active_preset_button(button)
                            self._apply_preset_scales(scales)

                        return handler

                    btn.clicked.connect(create_preset_handler(preset_scales, btn))
                else:
                    # Still connect with empty list as fallback
                    btn.clicked.connect(lambda: self._apply_preset_scales([]))

    def _set_active_preset_button(self, button: QPushButton) -> None:
        """Set the active preset button and update visual state."""
        # Clear previous active button
        if self.active_preset_button is not None:
            try:
                self.active_preset_button.setProperty("active", "false")
                self.active_preset_button.style().unpolish(self.active_preset_button)
                self.active_preset_button.style().polish(self.active_preset_button)
            except RuntimeError:
                pass
            self.active_preset_button = None

        # Set new active button
        self.active_preset_button = button
        if button is not None:
            button.setProperty("active", "true")
            button.style().unpolish(button)
            button.style().polish(button)

    def _apply_preset_scales(self, scales: list[str]):
        """Apply a preset's scales to the clinical scales section.

        If same preset is clicked: keep existing scales with values, add missing scales.
        If different preset is clicked: replace all scales with preset scales.
        """
        if not isinstance(scales, list):
            return

        if hasattr(self, "on_add_callback") and hasattr(self, "on_remove_callback"):
            # Get existing scale names - with and without values
            existing_scales_with_values = set()
            all_existing_scale_names = set()
            for name_edit, score_edit, _ in self.clinical_scales_rows:
                name = name_edit.text().strip()
                value = score_edit.text().strip()
                if name:
                    all_existing_scale_names.add(name)
                    if value:
                        existing_scales_with_values.add(name)

            # Find the empty row (with add button) index
            add_button_row_index = -1
            for i, (name_edit, _, _) in enumerate(self.clinical_scales_rows):
                if (
                    name_edit.text().strip() == ""
                ):  # Empty name indicates add button row
                    add_button_row_index = i
                    break

            # Remove only the add button row temporarily
            if add_button_row_index >= 0:
                name_edit, score_edit, row_layout = self.clinical_scales_rows[
                    add_button_row_index
                ]
                while row_layout.count():
                    item = row_layout.takeAt(0)
                    widget = item.widget()
                    if widget is not None:
                        widget.deleteLater()
                self.clinical_scales_container.removeItem(row_layout)
                self.clinical_scales_rows.pop(add_button_row_index)

            # Check if this is the same preset as before (by checking if all existing scales with values are in the new preset)
            is_same_preset = all(name in scales for name in existing_scales_with_values)

            if is_same_preset and existing_scales_with_values:
                # Same preset: keep existing scales, add only truly missing scales (not present at all)
                for scale_name in scales:
                    if scale_name not in all_existing_scale_names:
                        self._add_clinical_scale_row(
                            scale_name,
                            with_minus=True,
                            on_remove=self.on_remove_callback,
                        )
            else:
                # Different preset or no existing scales: clear all and add preset scales
                for _, _, row_layout in self.clinical_scales_rows:
                    while row_layout.count():
                        item = row_layout.takeAt(0)
                        widget = item.widget()
                        if widget is not None:
                            widget.deleteLater()
                    self.clinical_scales_container.removeItem(row_layout)
                self.clinical_scales_rows = []

                for scale_name in scales:
                    self._add_clinical_scale_row(
                        scale_name, with_minus=True, on_remove=self.on_remove_callback
                    )

            # Add empty row with add button back at the end
            self._add_clinical_scale_row(
                "", with_plus=True, on_add=self.on_add_callback
            )

            # Remove any existing stretches and add one at the very bottom
            for i in range(self.clinical_scales_container.count() - 1, -1, -1):
                item = self.clinical_scales_container.itemAt(i)
                if item and item.spacerItem():
                    self.clinical_scales_container.takeAt(i)
            self.clinical_scales_container.addStretch()

    def _add_clinical_scale_row(
        self,
        name: str = "",
        value: str = "",
        with_plus: bool = False,
        with_minus: bool = False,
        on_add: Callable = None,
        on_remove: Callable = None,
    ) -> None:
        """Add a single clinical scale row."""
        row = QHBoxLayout()

        name_edit = QLineEdit()
        name_edit.setPlaceholderText(PLACEHOLDERS["scale_name"])
        name_edit.setMaximumWidth(80)
        name_edit.setText(name)

        score_edit = QLineEdit()
        score_edit.setPlaceholderText(PLACEHOLDERS["scale_score"])
        score_edit.setMaximumWidth(50)
        score_edit.setValidator(QIntValidator())
        score_edit.setText(value)

        btn = None
        if with_plus:
            btn = QPushButton("+")
            btn.setToolTip("Add clinical scale")
            btn.setFixedSize(20, 20)
            btn.setObjectName("scale_add_btn")
            if on_add:
                btn.clicked.connect(on_add)
        elif with_minus:
            btn = QPushButton("-")
            btn.setToolTip("Remove clinical scale")
            btn.setFixedSize(20, 20)
            btn.setObjectName("scale_remove_btn")
            if on_remove:
                btn.clicked.connect(lambda: on_remove(row))
        else:
            # Fallback placeholder (prevents UnboundLocalError)
            btn = QLabel("")
            btn.setFixedSize(20, 20)

        # Add widgets to row
        row.addWidget(QLabel("Name:"))
        row.addWidget(name_edit)
        row.addSpacing(5)
        row.addWidget(QLabel("Score:"))
        row.addWidget(score_edit)
        row.addWidget(btn)
        row.addStretch(1)

        # Add row to container and track it
        self.clinical_scales_container.addLayout(row)
        self.clinical_scales_rows.append((name_edit, score_edit, row))

    def _load_clinical_presets(self) -> dict[str, list[str]]:
        """Load clinical presets from ScalePresetManager."""
        preset_manager = get_scale_preset_manager()
        return preset_manager.get_clinical_presets()

    def _open_clinical_scales_settings(self):
        """Open the clinical scales settings dialog."""
        dialog = ClinicalScalesSettingsDialog(
            self.clinical_presets, self, PRESET_BUTTONS
        )
        dialog.presets_changed.connect(self._on_presets_changed)
        dialog.exec()

    def _on_presets_changed(self, new_presets: dict[str, list[str]]):
        """Handle presets change from settings dialog."""
        old_presets = self.clinical_presets
        self.clinical_presets = new_presets

        # Save all presets using ScalePresetManager
        try:
            preset_manager = get_scale_preset_manager()
            preset_manager.save_clinical_presets(new_presets)
        except Exception as e:
            print(f"Error saving presets: {e}")

        # Check if any currently displayed preset was modified or deleted
        current_scales = []
        for name_edit, _, _ in self.clinical_scales_rows:
            scale_name = name_edit.text().strip()
            if scale_name:
                current_scales.append(scale_name)

        # Find which preset contains current scales
        current_preset = None
        if len(current_scales) > 0:
            for preset_name, preset_scales in old_presets.items():
                if all(scale in preset_scales for scale in current_scales):
                    current_preset = preset_name
                    break

        # Refresh preset buttons
        self._refresh_preset_buttons()

        # Reconnect buttons with new scales
        if hasattr(self, "on_add_callback") and hasattr(self, "on_remove_callback"):
            self._connect_preset_buttons()

            # If we found a current preset, check if it was modified
            if current_preset:
                if current_preset in new_presets:
                    # Check if scales actually changed
                    old_scales = old_presets[current_preset]
                    new_scales = new_presets[current_preset]

                    if old_scales != new_scales:
                        # Preset was modified - apply new scales
                        self._apply_preset_scales(new_scales)
                else:
                    # Preset was deleted - clear scales
                    self._apply_preset_scales([])

    def _refresh_preset_buttons(self):
        """Refresh preset buttons with new presets."""
        # Clear existing preset buttons
        for btn in self.preset_buttons:
            btn.setParent(None)
            btn.deleteLater()
        self.preset_buttons.clear()

        # Use the stored preset row layout
        preset_row = self.preset_row_layout

        if preset_row:
            # Remove all existing widgets from preset row (except stretch and settings button)
            widgets_to_remove = []
            for i in range(preset_row.count()):
                item = preset_row.itemAt(i)
                if item and item.widget():
                    widget = item.widget()
                    if widget and widget.objectName() != "settings_clincal_scales":
                        widgets_to_remove.append(widget)

            for widget in widgets_to_remove:
                preset_row.removeWidget(widget)
                widget.setParent(None)
                widget.deleteLater()

            # Find the settings button and its position
            settings_btn = None
            settings_index = -1
            for i in range(preset_row.count()):
                item = preset_row.itemAt(i)
                if item and item.widget():
                    widget = item.widget()
                    if widget and widget.objectName() == "settings_clincal_scales":
                        settings_btn = widget
                        settings_index = i
                        break

            if settings_btn is None:
                return

            # Ensure exactly one stretch before the settings button
            stretch_index = settings_index - 1
            if stretch_index < 0 or not (
                preset_row.itemAt(stretch_index)
                and preset_row.itemAt(stretch_index).spacerItem()
            ):
                preset_row.insertStretch(settings_index, 1)
                settings_index += 1
                stretch_index = settings_index - 1

            # # Remove any other stretches before the settings button (keep only the one right before it)
            # for i in range(stretch_index):
            #     item = preset_row.itemAt(i)
            #     if item and item.spacerItem():
            #         preset_row.takeAt(i)
            #         break

            # Insert new preset buttons before the stretch
            insert_index = stretch_index

            # Prefer showing defaults first IF they exist in the current presets
            ordered_names: list[str] = []
            for name in PRESET_BUTTONS:
                if name in self.clinical_presets:
                    ordered_names.append(name)
            for name in self.clinical_presets.keys():
                if name not in ordered_names:
                    ordered_names.append(name)

            for preset_name in ordered_names:
                btn = QPushButton(preset_name)
                btn.setObjectName(f"preset_{preset_name}")
                self.preset_buttons.append(btn)
                preset_row.insertWidget(insert_index, btn)
                insert_index += 1
                settings_index += 1
                stretch_index += 1

            # Reconnect all preset buttons after refresh
            if hasattr(self, "on_add_callback") and hasattr(self, "on_remove_callback"):
                self._connect_preset_buttons()
