"""
Step 3 view - Active session recording.

This module contains the view for the third step where users actively record
session data including stimulation parameters and scale values.
"""


from PySide6.QtCore import Qt
from PySide6.QtGui import QDoubleValidator, QIntValidator
from PySide6.QtWidgets import (
    QComboBox,
    QFormLayout,
    QFrame,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMenu,
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
from .base_view import BaseStepView


class Step3View(BaseStepView):
    """
    Third step view for active session recording.

    This view handles:
    - Real-time stimulation parameter adjustment
    - Session scale value recording
    - Session notes
    - Data insertion and session closing
    """

    def __init__(self, parent_style):
        """
        Initialize Step 3 view.

        Args:
            parent_style: Parent widget style for icon access
        """
        super().__init__()
        self.parent_style = parent_style
        self.session_scale_value_edits = []
        self.step3_session_scales_form: QFormLayout = None

        self.left_canvas = ElectrodeCanvas()
        self.right_canvas = ElectrodeCanvas()
        self.left_canvas.validation_callback = self._on_left_canvas_validation
        self.right_canvas.validation_callback = self._on_right_canvas_validation
        self._left_selection_valid = True
        self._right_selection_valid = True

        self._current_model = None
        self._setup_ui()

    def get_header_title(self) -> str:
        """Return the wizard header title for Step 3."""
        return "Programming Session Ongoing"

    def _setup_ui(self) -> None:
        """Set up the UI layout."""

        # Left macro-panel: Stimulation params + electrodes
        left_container = QGroupBox("Session settings")
        left_container.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        left_container_layout = QHBoxLayout(left_container)
        left_container_layout.setContentsMargins(0, 0, 0, 0)

        params_group = self._create_stimulation_params_group()

        # Wrap sidebar in a scroll area like step1_view
        sidebar_widget = params_group
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
        sidebar_scroll.setWidget(sidebar_widget)

        left_container_layout.addWidget(sidebar_scroll, 1)

        electrodes_layout = QVBoxLayout()
        electrodes_row = QHBoxLayout()

        left_canvas_group = QGroupBox("Left electrode")
        left_canvas_layout = QVBoxLayout()
        left_canvas_layout.addWidget(self.left_canvas, 1)
        left_canvas_group.setLayout(left_canvas_layout)

        right_canvas_group = QGroupBox("Right electrode")
        right_canvas_layout = QVBoxLayout()
        right_canvas_layout.addWidget(self.right_canvas, 1)
        right_canvas_group.setLayout(right_canvas_layout)

        electrodes_row.addWidget(left_canvas_group, 1)
        electrodes_row.addWidget(right_canvas_group, 1)

        electrodes_layout.addLayout(electrodes_row)
        electrodes_layout.addLayout(self._create_electrode_legend_layout())
        left_container_layout.addLayout(electrodes_layout, 2)

        # Right macro-panel: Scales and notes
        right_widget = QWidget()
        right_layout = QVBoxLayout(right_widget)
        right_layout.setContentsMargins(0, 0, 0, 0)
        scales_group = self._create_session_scales_group()
        right_layout.addWidget(scales_group)
        right_layout.addWidget(create_horizontal_line())
        notes_group = self._create_notes_group()
        right_layout.addWidget(notes_group)

        #left_container.setMinimumWidth(500)
        right_widget.setMinimumWidth(400)

        # Splitter: right panel shrinks first (stretch=1), left stays stable (stretch=0)
        splitter = QSplitter(Qt.Horizontal)
        splitter.addWidget(left_container)
        splitter.addWidget(right_widget)
        splitter.setStretchFactor(0, 0)
        splitter.setStretchFactor(1, 1)
        splitter.setChildrenCollapsible(False)

        self.main_layout.addWidget(splitter)
        #self.main_layout.addStretch(1)

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

    def _create_stimulation_params_group(self) -> QWidget:
        """Create the stimulation parameters container."""
        container = QWidget()
        container.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        #container.setMinimumWidth(380)
        sidebar_layout = QVBoxLayout(container)

        group_row = QGroupBox("Group")
        group_row_layout = QHBoxLayout()
        self.group_combo = QComboBox()
        self.group_combo.addItems(["A", "B", "C", "D", "None"])
        self.group_combo.setCurrentIndex(0)
        group_row_layout.addWidget(self.group_combo)
        group_row.setLayout(group_row_layout)

        freq_limits = STIMULATION_LIMITS["frequency"]
        amp_limits = STIMULATION_LIMITS["amplitude"]
        pw_limits = STIMULATION_LIMITS["pulse_width"]

        left_group = QGroupBox("Left")
        left_group.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        left_group_layout = QVBoxLayout()

        freq_row = QHBoxLayout()
        freq_row.addWidget(QLabel("Frequency:"))
        freq_row.addStretch()
        self.session_left_stim_freq_edit = QLineEdit()
        self.session_left_stim_freq_edit.setMaximumWidth(80)
        self.session_left_stim_freq_edit.setPlaceholderText(PLACEHOLDERS["frequency"])
        self.session_left_stim_freq_edit.setValidator(QIntValidator(freq_limits["min"], freq_limits["max"]))
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
        self.session_left_amp_edit.setValidator(QDoubleValidator(amp_limits["min"], amp_limits["max"], amp_limits["decimals"]))
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
        self.session_left_pw_edit.setValidator(QIntValidator(pw_limits["min"], pw_limits["max"]))
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
        left_group.setLayout(left_group_layout)

        right_group = QGroupBox("Right")
        right_group.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        right_group_layout = QVBoxLayout()

        freq_row = QHBoxLayout()
        freq_row.addWidget(QLabel("Frequency:"))
        freq_row.addStretch()
        self.session_right_stim_freq_edit = QLineEdit()
        self.session_right_stim_freq_edit.setMaximumWidth(80)
        self.session_right_stim_freq_edit.setPlaceholderText(PLACEHOLDERS["frequency"])
        self.session_right_stim_freq_edit.setValidator(QIntValidator(freq_limits["min"], freq_limits["max"]))
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
        self.session_right_amp_edit.setValidator(QDoubleValidator(amp_limits["min"], amp_limits["max"], amp_limits["decimals"]))
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
        self.session_right_pw_edit.setValidator(QIntValidator(pw_limits["min"], pw_limits["max"]))
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
        self.right_config_box.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        right_config_layout = QVBoxLayout(self.right_config_box)
        right_config_layout.setContentsMargins(6, 4, 6, 4)
        self.right_config_label = QLabel()
        self.right_config_label.setWordWrap(True)
        self.right_config_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.right_config_label.setTextFormat(Qt.RichText)
        right_config_layout.addWidget(self.right_config_label)
        right_group_layout.addWidget(self.right_config_box)
        right_group_layout.addStretch(1)
        right_group.setLayout(right_group_layout)

        sidebar_layout.addWidget(group_row)
        sidebar_layout.addWidget(left_group)
        sidebar_layout.addWidget(right_group)
        sidebar_layout.addStretch(1)

        return container

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
            swatch.setStyleSheet(f"background-color: {color}; border: 1px solid {border};")
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

    def _on_left_canvas_validation(self, is_valid: bool, error_msg: str) -> None:
        """Callback when left electrode canvas validation state changes."""
        self._left_selection_valid = bool(is_valid)
        self.update_configuration_display()
        if hasattr(self, "left_amp_split"):
            self.left_amp_split.update_cathodes(get_cathode_labels(self.left_canvas))

    def _on_right_canvas_validation(self, is_valid: bool, error_msg: str) -> None:
        """Callback when right electrode canvas validation state changes."""
        self._right_selection_valid = bool(is_valid)
        self.update_configuration_display()
        if hasattr(self, "right_amp_split"):
            self.right_amp_split.update_cathodes(get_cathode_labels(self.right_canvas))

    def set_electrode_model(self, model) -> None:
        """Set the electrode model on both canvases and refresh display."""
        self._current_model = model
        self.left_canvas.set_model(model)
        self.right_canvas.set_model(model)
        self.update_configuration_display()

    def update_configuration_display(self) -> None:
        """Refresh the configuration validity labels for both sides."""
        if not hasattr(self, "left_config_label") or not hasattr(self, "right_config_label"):
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
                self.left_config_label.setText("Invalid configuration: violates selection rules")
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
                self.right_config_label.setText("Invalid configuration: violates selection rules")
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
                state_str = "Anodic (+)" if state == ContactState.ANODIC else "Cathodic (-)"

                if model.is_directional:
                    segment_labels = ['a', 'b', 'c']
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
                seg_states = [canvas.contact_states.get((contact_idx, seg), ContactState.OFF) for seg in range(3)]
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
            for contact_idx in range(model.num_contacts):
                state = canvas.contact_states.get((contact_idx, 0), ContactState.OFF)
                if state == ContactState.ANODIC:
                    anode_items.append(f"E{contact_idx}")
                elif state == ContactState.CATHODIC:
                    cathode_items.append(f"E{contact_idx}")

        return "_".join(anode_items), "_".join(cathode_items)

    def _create_session_scales_group(self) -> QGroupBox:
        """Create the session scales group box."""
        gb_session = QGroupBox("Session scales")

        self.step3_session_scales_form = QFormLayout(gb_session)
        self.step3_session_scales_form.setLabelAlignment(Qt.AlignRight)
        self.step3_session_scales_form.setFormAlignment(Qt.AlignTop)
        self.step3_session_scales_form.setHorizontalSpacing(18)
        self.step3_session_scales_form.setVerticalSpacing(10)

        return gb_session

    def _create_notes_group(self) -> QGroupBox:
        """Create the session notes group box."""
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
        self.session_notes_edit.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
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
        for item in (scale_names or []):
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
        group: str,
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

        if hasattr(self, "group_combo") and group:
            try:
                self.group_combo.setCurrentText(str(group))
            except Exception:
                pass

        if self.left_canvas.model:
            self._apply_contact_text_to_canvas(self.left_canvas, left_anode, left_cathode)
        if self.right_canvas.model:
            self._apply_contact_text_to_canvas(self.right_canvas, right_anode, right_cathode)

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
        except (ValueError, TypeError):
            return amp_str

    def _apply_contact_text_to_canvas(self, canvas: ElectrodeCanvas, anode_text: str, cathode_text: str) -> None:
        """Parse anode/cathode token strings and set the corresponding canvas states."""
        model = canvas.model
        if not model:
            return

        canvas.contact_states.clear()
        canvas.case_state = ContactState.OFF

        def apply_tokens(text: str, state: int) -> None:
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
                        continue
                    continue

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

                if model.is_directional and len(token) >= 2:
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

        is_valid, _ = StimulationRule.validate_configuration(canvas.contact_states, canvas.case_state)
        if not is_valid:
            canvas.contact_states.clear()
            canvas.case_state = ContactState.OFF

        canvas.update()
        # Refresh amplitude split widget for this canvas
        if canvas is self.left_canvas and hasattr(self, "left_amp_split"):
            self.left_amp_split.update_cathodes(get_cathode_labels(self.left_canvas))
        elif canvas is self.right_canvas and hasattr(self, "right_amp_split"):
            self.right_amp_split.update_cathodes(get_cathode_labels(self.right_canvas))
