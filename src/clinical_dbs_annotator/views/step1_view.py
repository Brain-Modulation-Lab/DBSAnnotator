"""
Step 1 view - Initial settings and clinical scales.

This module contains the view for the first step of the wizard where users
configure initial settings, stimulation parameters, and clinical scales.
"""

from typing import Callable, List, Tuple, Dict
import json
import os

from PyQt5.QtCore import QSize, Qt
from PyQt5.QtGui import QDoubleValidator, QFont, QIntValidator, QPixmap
from PyQt5.QtWidgets import (
    QComboBox,
    QFileDialog,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QScrollArea,
    QSizePolicy,
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
from ..ui import create_horizontal_line, MultiSelectComboBoxWithDisplay
from ..ui.clinical_scales_settings_dialog import ClinicalScalesSettingsDialog
from ..utils.resources import resource_path
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

    def __init__(self, logo_pixmap: QPixmap, parent_style):
        """
        Initialize Step 1 view.

        Args:
            logo_pixmap: Application logo
            parent_style: Parent widget style for icon access
        """
        super().__init__(logo_pixmap)
        self.parent_style = parent_style
        self.clinical_scales_rows: List[Tuple[QLineEdit, QLineEdit, QHBoxLayout]] = []
        
        # Load custom presets
        self.clinical_presets = self._load_clinical_presets()
        
        self._setup_ui()

    def _setup_ui(self) -> None:
        """Set up the UI layout."""
        # Header
        header = self.create_step1_header(
            "Welcome to the BML Annotator for Percept clinical programming sessions!"
        )
        self.main_layout.addWidget(header)

        # Main content area
        content_layout = QHBoxLayout()

        # Left side: Initial settings
        settings_group = self._create_settings_group()
        content_layout.addWidget(settings_group)

        # Right side: Clinical scales and notes
        right_layout = QVBoxLayout()
        clinical_group = self._create_clinical_scales_group()
        notes_group = self._create_notes_group()
        right_layout.addWidget(clinical_group)
        right_layout.addWidget(notes_group)
        content_layout.addLayout(right_layout)

        self.main_layout.addLayout(content_layout)

        # Next button
        self.next_button = QPushButton("Next")
        self.next_button.setIcon(self.parent_style.standardIcon(QStyle.SP_ArrowForward))
        self.next_button.setIconSize(QSize(16, 16))
        self.next_button.setMaximumWidth(120)
        self.main_layout.addWidget(self.next_button, alignment=Qt.AlignRight)

    def _create_settings_group(self) -> QGroupBox:
        """Create the initial settings group box."""
        gb_init = QGroupBox("Initial settings")
        gb_init.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Preferred)
        gb_init.setFont(QFont("Segoe UI", 12, QFont.Bold))
        gb_init.setStyleSheet(
            "QGroupBox { margin-top: 16pt; } "
            "QGroupBox::title { color: #ff8800; margin-left: 4pt; "
            "font-size: 16pt; font-weight: 600; }"
        )

        layout = QFormLayout(gb_init)
        layout.setLabelAlignment(Qt.AlignRight)

        # File selection
        file_row = QHBoxLayout()
        self.file_path_edit = QLineEdit()
        browse_button = QPushButton()
        browse_button.setMaximumWidth(32)
        browse_button.setIcon(self.parent_style.standardIcon(QStyle.SP_DirOpenIcon))
        browse_button.setToolTip("Browse for file")
        browse_button.clicked.connect(self.browse_file)
        file_row.addWidget(self.file_path_edit)
        file_row.addWidget(browse_button)
        file_container = QWidget()
        file_container.setStyleSheet("background-color: transparent;")
        file_container.setLayout(file_row)
        layout.addRow(QLabel("File:"), file_container)

        layout.addWidget(create_horizontal_line())

        # Left electrode section
        layout.addRow(QLabel(""), QLabel(""))  # Empty row for spacing
        left_electrode_label = QLabel("Left electrode")
        left_electrode_label.setStyleSheet("font-weight: bold; font-size: 12pt;")
        layout.addRow(left_electrode_label, QLabel(""))

        # Left stimulation frequency
        self.left_stim_freq_edit = QLineEdit()
        self.left_stim_freq_edit.setMaximumWidth(80)
        self.left_stim_freq_edit.setPlaceholderText(PLACEHOLDERS["frequency"])
        freq_limits = STIMULATION_LIMITS["frequency"]
        self.left_stim_freq_edit.setValidator(
            QIntValidator(freq_limits["min"], freq_limits["max"])
        )
        layout.addRow(QLabel("Stimulation frequency:"), self.left_stim_freq_edit)

        # Left Anode (+)
        self.left_anode_combo = MultiSelectComboBoxWithDisplay()
        self.left_anode_combo.setMinimumWidth(150)
        self.left_anode_combo.addItems([
            "case", "0 ring", "1 ring", "1a", "1b", "1c",
            "2 ring", "2a", "2b", "2c", "3 ring"
        ])
        anode_label = QLabel("Anode (+):")
        layout.addRow(anode_label, self.left_anode_combo)

        # Left Cathode (-)
        self.left_cathode_combo = MultiSelectComboBoxWithDisplay()
        self.left_cathode_combo.setMinimumWidth(150)
        self.left_cathode_combo.addItems([
            "case", "0 ring", "1 ring", "1a", "1b", "1c",
            "2 ring", "2a", "2b", "2c", "3 ring"
        ])
        # # Set ground as default for cathode
        cathode_label = QLabel("Cathode (-):")
        layout.addRow(cathode_label, self.left_cathode_combo)

        # Left amplitude
        self.left_amp_edit = QLineEdit()
        self.left_amp_edit.setMaximumWidth(80)
        self.left_amp_edit.setPlaceholderText(PLACEHOLDERS["amplitude"])
        amp_limits = STIMULATION_LIMITS["amplitude"]
        self.left_amp_edit.setValidator(
            QDoubleValidator(amp_limits["min"], amp_limits["max"], amp_limits["decimals"])
        )
        layout.addRow(QLabel("Amplitude:"), self.left_amp_edit)

        # Left pulse width
        self.left_pw_edit = QLineEdit()
        self.left_pw_edit.setMaximumWidth(80)
        self.left_pw_edit.setPlaceholderText(PLACEHOLDERS["pulse_width"])
        pw_limits = STIMULATION_LIMITS["pulse_width"]
        self.left_pw_edit.setValidator(QIntValidator(pw_limits["min"], pw_limits["max"]))
        layout.addRow(QLabel("Pulse width:"), self.left_pw_edit)

        layout.addWidget(create_horizontal_line())



        # Right electrode section
        layout.addRow(QLabel(""), QLabel(""))  # Empty row for spacing
        right_electrode_label = QLabel("Right electrode")
        right_electrode_label.setStyleSheet("font-weight: bold; font-size: 12pt;")
        layout.addRow(right_electrode_label, QLabel(""))

        # Right stimulation frequency
        self.right_stim_freq_edit = QLineEdit()
        self.right_stim_freq_edit.setMaximumWidth(80)
        self.right_stim_freq_edit.setPlaceholderText(PLACEHOLDERS["frequency"])
        self.right_stim_freq_edit.setValidator(
            QIntValidator(freq_limits["min"], freq_limits["max"])
        )
        layout.addRow(QLabel("Stimulation frequency:"), self.right_stim_freq_edit)

        # Right Anode (+)
        self.right_anode_combo = MultiSelectComboBoxWithDisplay()
        self.right_anode_combo.setMaximumWidth(150)
        self.right_anode_combo.addItems([
            "case", "0 ring", "1 ring", "1a", "1b", "1c",
            "2 ring", "2a", "2b", "2c", "3 ring"
        ])
        anode_label_r = QLabel("Anode (+):")
        layout.addRow(anode_label_r, self.right_anode_combo)

        # Right Cathode (-)
        self.right_cathode_combo = MultiSelectComboBoxWithDisplay()
        self.right_cathode_combo.setMaximumWidth(150)
        self.right_cathode_combo.addItems([
            "case", "0 ring", "1 ring", "1a", "1b", "1c",
            "2 ring", "2a", "2b", "2c", "3 ring"
        ])
        # # Set ground as default for cathode
        cathode_label_r = QLabel("Cathode (-):")
        layout.addRow(cathode_label_r, self.right_cathode_combo)

        # Right amplitude
        self.right_amp_edit = QLineEdit()
        self.right_amp_edit.setMaximumWidth(80)
        self.right_amp_edit.setPlaceholderText(PLACEHOLDERS["amplitude"])
        self.right_amp_edit.setValidator(
            QDoubleValidator(amp_limits["min"], amp_limits["max"], amp_limits["decimals"])
        )
        layout.addRow(QLabel("Amplitude:"), self.right_amp_edit)

        # Right plse width
        self.right_pw_edit = QLineEdit()
        self.right_pw_edit.setMaximumWidth(80)
        self.right_pw_edit.setPlaceholderText(PLACEHOLDERS["pulse_width"])
        self.right_pw_edit.setValidator(QIntValidator(pw_limits["min"], pw_limits["max"]))
        layout.addRow(QLabel("Pulse width:"), self.right_pw_edit)

        return gb_init

    def _create_clinical_scales_group(self) -> QGroupBox:
        """Create the clinical scales group box."""
        gb_clinical = QGroupBox("Clinical scales")
        gb_clinical.setStyleSheet(
            "QGroupBox::title { color: #ff8800; font-size: 11pt; font-weight: 600; }"
        )
        gb_clinical.setFont(QFont("Segoe UI", 10, QFont.Bold))
        gb_clinical.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Preferred)

        layout = QVBoxLayout(gb_clinical)

        # Preset buttons
        preset_row = QHBoxLayout()
        self.preset_buttons = []
        preset_row.addStretch(1)
        
        # Settings button
        settings_btn = QPushButton('⚙️')
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
        scroll_content.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.clinical_scales_container = QVBoxLayout(scroll_content)
        self.clinical_scales_container.setContentsMargins(0, 0, 0, 0)

        # Scrollable area - will only scroll when user resizes window smaller
        scroll_area = QScrollArea()
        scroll_area.setWidgetResizable(True)
        scroll_area.setFrameShape(QScrollArea.NoFrame)
        scroll_area.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        scroll_area.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        scroll_area.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        scroll_area.setWidget(scroll_content)

        layout.addWidget(scroll_area)

        return gb_clinical

    def _create_notes_group(self) -> QGroupBox:
        """Create the initial notes group box."""
        gb_notes = QGroupBox("Initial notes")
        gb_notes.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Expanding)
        gb_notes.setFont(QFont("Segoe UI", 10, QFont.Bold))
        gb_notes.setStyleSheet(
            "QGroupBox::title { color: #ff8800; font-size: 11pt; font-weight: 600; }"
        )

        layout = QHBoxLayout(gb_notes)
        self.notes_edit = QTextEdit()
        self.notes_edit.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.notes_edit.setMinimumHeight(80)
        layout.addWidget(self.notes_edit)

        return gb_notes

    def browse_file(self) -> None:
        """Open file dialog for TSV file selection."""
        import os

        # Get current path if available
        current_path = self.file_path_edit.text()
        if current_path:
            start_dir = os.path.dirname(current_path)
            default_name = os.path.basename(current_path)
        else:
            start_dir = ""
            default_name = "annot.tsv"

        # Combine directory and default filename
        default_path = os.path.join(start_dir, default_name) if start_dir else default_name

        file_path, _ = QFileDialog.getSaveFileName(
            self, "Save TSV File", default_path, "TSV Files (*.tsv);;All Files (*)"
        )
        if file_path:
            if not file_path.endswith(".tsv"):
                file_path += ".tsv"
            self.file_path_edit.setText(file_path)

    def get_preset_button(self, preset_name: str) -> QPushButton:
        """Get a preset button by name."""
        return self.findChild(QPushButton, f"preset_{preset_name}")

    def update_clinical_scales(
        self, preset_scales: List[str], on_add_callback: Callable, on_remove_callback: Callable
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
        
        # Clear existing rows
        for _, _, row_layout in self.clinical_scales_rows:
            while row_layout.count():
                item = row_layout.takeAt(0)
                widget = item.widget()
                if widget is not None:
                    widget.deleteLater()
            self.clinical_scales_container.removeItem(row_layout)
        self.clinical_scales_rows = []

        # Add preset scales
        for name in preset_scales:
            self._add_clinical_scale_row(name, with_minus=True, on_remove=on_remove_callback)

        # Add empty row with add button
        self._add_clinical_scale_row("", with_plus=True, on_add=on_add_callback)
        
        # Add stretch at the bottom to push content up
        self.clinical_scales_container.addStretch()
        
        # Store callbacks for preset buttons
        self.on_add_callback = on_add_callback
        self.on_remove_callback = on_remove_callback
        
        # Connect preset buttons to their respective scales (only now that callbacks are available)
        self._connect_preset_buttons()

    def _connect_preset_buttons(self):
        """Connect all preset buttons to their respective scales."""
        for btn in self.preset_buttons:
            # Disconnect any existing connections
            try:
                btn.clicked.disconnect()
            except:
                pass
            
            # Get the preset name from object name
            preset_name = btn.objectName().replace("preset_", "")
            
            # Get the scales for this preset from clinical_presets
            if preset_name in self.clinical_presets:
                preset_scales = self.clinical_presets[preset_name]
                
                if preset_scales and isinstance(preset_scales, list):
                    # Create a proper closure using a function
                    def create_preset_handler(scales):
                        return lambda: self._apply_preset_scales(scales)
                    
                    btn.clicked.connect(create_preset_handler(preset_scales))
            else:
                # Still connect with empty list as fallback
                btn.clicked.connect(lambda: self._apply_preset_scales([]))
                
    def _apply_preset_scales(self, scales: List[str]):
        """Apply a preset's scales to the clinical scales section."""
        if not isinstance(scales, list):
            return
            
        if hasattr(self, 'on_add_callback') and hasattr(self, 'on_remove_callback'):
            # Clear existing scales first
            for _, _, row_layout in self.clinical_scales_rows:
                while row_layout.count():
                    item = row_layout.takeAt(0)
                    widget = item.widget()
                    if widget is not None:
                        widget.deleteLater()
                self.clinical_scales_container.removeItem(row_layout)
            self.clinical_scales_rows = []
            
            # Also remove any stretches from container
            while self.clinical_scales_container.count():
                item = self.clinical_scales_container.takeAt(0)
                if item.spacerItem():
                    # Just remove the stretch, no widget to delete
                    continue
                elif item.widget():
                    item.widget().deleteLater()
                else:
                    # Remove layout items
                    continue
            
            # Add the preset scales
            for scale_name in scales:
                self._add_clinical_scale_row(scale_name, with_minus=True, on_remove=self.on_remove_callback)
            
            # Add empty row with add button
            self._add_clinical_scale_row("", with_plus=True, on_add=self.on_add_callback)
            
            # Add stretch at the very bottom 
            self.clinical_scales_container.addStretch()

    def _add_clinical_scale_row(
        self,
        name: str = "",
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

        if with_plus:
            btn = QPushButton("+")
            btn.setToolTip("Add clinical scale")
            btn.setMaximumWidth(24)
            if on_add:
                btn.clicked.connect(on_add)
        elif with_minus:
            btn = QPushButton("-")
            btn.setToolTip("Remove clinical scale")
            btn.setMaximumWidth(24)
            if on_remove:
                btn.clicked.connect(lambda: on_remove(row))
                
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

    def _load_clinical_presets(self) -> Dict[str, List[str]]:
        """Load clinical presets from config file."""
        presets_file = resource_path("config/clinical_presets.json")
        
        if os.path.exists(presets_file):
            try:
                with open(presets_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                print(f"Error loading clinical presets: {e}")
                return {}
        else:
            # Create default presets if file doesn't exist
            return {
                "OCD": ["Y-BOCS", "HADS", "GAF"],
                "MDD": ["HAM-D", "MADRS", "GAF"],
                "PD": ["UPDRS", "MoCA", "GAF"],
                "ET": ["TREMOR", "ADL", "QOL"]
            }
        
    def _open_clinical_scales_settings(self):
        """Open the clinical scales settings dialog."""
        dialog = ClinicalScalesSettingsDialog(self.clinical_presets, self, PRESET_BUTTONS)
        dialog.presets_changed.connect(self._on_presets_changed)
        dialog.exec_()

    def _on_presets_changed(self, new_presets: Dict[str, List[str]]):
        """Handle presets change from settings dialog."""
        old_presets = self.clinical_presets
        self.clinical_presets = new_presets
        
        # Save all presets to file immediately
        try:
            presets_file = resource_path("config/clinical_presets.json")
            os.makedirs(os.path.dirname(presets_file), exist_ok=True)
            
            with open(presets_file, 'w', encoding='utf-8') as f:
                json.dump(new_presets, f, indent=2, ensure_ascii=False)
                
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
        if hasattr(self, 'on_add_callback') and hasattr(self, 'on_remove_callback'):
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
            if stretch_index < 0 or not (preset_row.itemAt(stretch_index) and preset_row.itemAt(stretch_index).spacerItem()):
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
            ordered_names: List[str] = []
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
            if hasattr(self, 'on_add_callback') and hasattr(self, 'on_remove_callback'):
                self._connect_preset_buttons()
