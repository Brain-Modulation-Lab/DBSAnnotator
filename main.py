import os
import sys
import csv
from datetime import datetime
import pytz
from PyQt5.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QHBoxLayout, QFormLayout, QGroupBox, QFrame,
    QPushButton, QLabel, QStackedWidget, QFileDialog, QLineEdit, QTextEdit,
    QMessageBox, QSizePolicy, QStyle)
from PyQt5.QtCore import Qt, QSize
from PyQt5.QtGui import QFont, QIcon, QPixmap, QDoubleValidator, QIntValidator
import annotator_utils as au

# to install:
# WINDOWS: pyinstaller --onefile --noconsole --name "ClinicalDBSAnnot_v01" --add-data "icons\logobml.ico;." --add-data "icons\logobml.png;." --add-data "annotator_utils.py;." --add-data "style.qss;." main.py
# WINDOWS if PyQt plugin is not working: pyinstaller --onefile --noconsole --name "ClinicalDBSAnnot_v01" --add-data "icons\logobml.ico;." --add-data "icons\logobml.png;." --add-data "annotator_utils.py;." --add-data "style.qss;." main.py --collect-all PyQt5
# MACos: pyinstaller --onefile --windowed --name "ClinicalDBSAnnot_v01" --add-data "icons/logobml.ico:." --add-data "icons/logobml.png:." --add-data "annotator_utils.py:." --add-data "style.qss:." main.py

deploy = False
version = "v0.1"


def resource_path(relative_path):
    if hasattr(sys, '_MEIPASS'):
        return os.path.join(sys._MEIPASS, relative_path)
    return os.path.join(os.path.abspath("."), relative_path)

def h_line():
    line = QFrame()
    line.setFrameShape(QFrame.HLine)
    line.setFrameShadow(QFrame.Sunken)
    line.setStyleSheet("background: #3a3a3a; max-height: 2t; min-height: 2pt; border: none; margin: 10pt 0 10pt 0;")
    return line


class WizardWindow(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("BML Annotator for DBS clinical programming sessions "+version)

        screen = app.primaryScreen()
        rect = screen.availableGeometry()
        screen_width = rect.width()
        screen_height = rect.height()
        x = int(screen_width * 0.1)
        y = int(screen_height * 0.1)
        width = int(screen_width * 0.4)  
        height = int(screen_height * 0.4)
        self.setGeometry(x, y, width, height)

        self.session_start_time = datetime.now()

        self.setWindowIcon(QIcon(resource_path(os.path.join('icons','logobml.png'))))
        self.logo_path = QPixmap(resource_path(os.path.join('icons','logobml.png')))

        self.tsv_file = None
        self.tsv_writer = None
        self.tsv_columns = [
            "date", "time", "block_id", "scale_name", "scale_value",
            "stim_freq", "left_contact", "left_amplitude", "left_pulse_width",
            "right_contact", "right_amplitude", "right_pulse_width", "notes"
        ]
        self.current_step = 0
        self.session_start_time = None
        self.session_scales_names = []  
        self.block_id_session = 0     
        main_layout = QVBoxLayout(self)
        self.stack = QStackedWidget(self)
        self.step_widgets = [self.create_step1(),None,None]
        self.stack.addWidget(self.step_widgets[0])
        main_layout.addWidget(self.stack)
        main_layout.addLayout(self.create_nav_bar())
        self.update_ui()

    def create_section_label(self, text):
        label = QLabel(text)
        label.setStyleSheet("color: #ff8800; font-size: 18pt; font-weight: 600; margin-bottom: 4pt;")
        return label
    
    # ------------------------------------------------------------------------------------
    # ------------------------------------------------------------------------------------
    # ------------------------------------------------------------------------------------

    def create_step1(self):
        widget = QWidget()
        layout = QVBoxLayout(widget)

        welcome_row = QHBoxLayout()

        # logo
        image_label = QLabel()
        logo_pixmap = self.logo_path
        logo_pixmap = logo_pixmap.scaledToWidth(90, Qt.SmoothTransformation)
        logo_pixmap = au.rounded_pixmap(logo_pixmap, 10)
        image_label.setPixmap(logo_pixmap)
        image_label.setAlignment(Qt.AlignVCenter | Qt.AlignRight)
        welcome_row.addWidget(image_label, 1)  
        
        # label
        welcome = QLabel("Welcome to the BML Annotator for Percept clinical programming sessions!")
        welcome.setStyleSheet("font-size: 20pt; font-weight: 500;")
        welcome.setAlignment(Qt.AlignVCenter | Qt.AlignCenter)
        welcome.setWordWrap(True)
        welcome_row.addWidget(welcome, 4) 

        layout.addLayout(welcome_row)

        main_content_layer = QHBoxLayout()
        
        # File/Initial section
        gb_init = QGroupBox("Initial settings")
        gb_init.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Preferred)
        gb_init.setFont(QFont("Segoe UI", 12, QFont.Bold))
        init_lyt = QFormLayout(gb_init)
        init_lyt.setLabelAlignment(Qt.AlignRight)
        gb_init.setStyleSheet("QGroupBox { margin-top: 16pt; } QGroupBox::title { color: #ff8800; margin-left: 4pt; font-size: 16pt; font-weight: 600; }")
        

        # File
        file_row = QHBoxLayout()
        self.file_path_edit = QLineEdit()
        browse_button = QPushButton()
        browse_button.setFixedWidth(40)
        browse_button.setIcon(self.style().standardIcon(QStyle.SP_DirOpenIcon))
        browse_button.setToolTip("Browse for file")
        browse_button.clicked.connect(self.browse_file_step1)
        file_row.addWidget(self.file_path_edit)
        file_row.addWidget(browse_button)
        file_container = QWidget()
        file_container.setLayout(file_row)
        init_lyt.addRow(QLabel("File:"), file_container)

        # Stimulation frequency
        self.stim_freq_edit = QLineEdit()
        self.stim_freq_edit.setFixedWidth(100)
        self.stim_freq_edit.setPlaceholderText("Hz")
        self.stim_freq_edit.setValidator(QIntValidator(0, 200))
        init_lyt.addRow(QLabel("Stimulation frequency:"), self.stim_freq_edit)

        init_lyt.addWidget(h_line())

        # Left contact
        self.left_contact_edit = QLineEdit()
        self.left_contact_edit.setFixedWidth(100)
        self.left_contact_edit.setPlaceholderText("e#")
        init_lyt.addRow(QLabel("Left contact:"), self.left_contact_edit)

        # Left amplitude
        self.left_amp_edit = QLineEdit()
        self.left_amp_edit.setFixedWidth(100)
        self.left_amp_edit.setPlaceholderText("mA")
        self.left_amp_edit.setValidator(QDoubleValidator(0.0, 15.0, 2))
        init_lyt.addRow(QLabel("Left amplitude:"), self.left_amp_edit)

        # Left pulse width
        self.left_pw_edit = QLineEdit()
        self.left_pw_edit.setFixedWidth(100)
        self.left_pw_edit.setPlaceholderText("µs")
        self.left_pw_edit.setValidator(QIntValidator(10, 200))
        init_lyt.addRow(QLabel("Left pulse width:"), self.left_pw_edit)

        init_lyt.addWidget(h_line())

        # Right contact
        self.right_contact_edit = QLineEdit()
        self.right_contact_edit.setFixedWidth(100)
        self.right_contact_edit.setPlaceholderText("e#")
        init_lyt.addRow(QLabel("Right contact:"), self.right_contact_edit)

        # Right amplitude
        self.right_amp_edit = QLineEdit()
        self.right_amp_edit.setFixedWidth(100)
        self.right_amp_edit.setPlaceholderText("mA")
        self.right_amp_edit.setValidator(QDoubleValidator(0.0, 15.0, 2))
        init_lyt.addRow(QLabel("Right amplitude:"), self.right_amp_edit)

        # Right pulse width
        self.right_pw_edit = QLineEdit()
        self.right_pw_edit.setFixedWidth(100)
        self.right_pw_edit.setPlaceholderText("µs")
        self.right_pw_edit.setValidator(QIntValidator(10, 200))
        init_lyt.addRow(QLabel("Right pulse width:"), self.right_pw_edit)
        main_content_layer.addWidget(gb_init)
        

        clinical_content_layer = QVBoxLayout()
        # clinical scales
        gb_clinical = QGroupBox("Clinical scales")
        gb_clinical.setStyleSheet("QGroupBox::title { color: #ff8800; font-size: 15pt; font-weight: 600; }")
        gb_clinical.setFont(QFont("Segoe UI", 12, QFont.Bold))
        clinical_lyt = QVBoxLayout(gb_clinical)
        preset_row = QHBoxLayout()
        preset_list = ["OCD", "MDD", "PD", "ET"]
        for label in preset_list:
            btn = QPushButton(label)
            btn.setObjectName(f"preset_{label}")
            btn.clicked.connect(lambda checked, l=label: self.apply_clinical_preset(l))
            preset_row.addWidget(btn)
            if label==preset_list[-1]:
                preset_row.addStretch(1)
        preset_row.addStretch(1)
        clinical_lyt.addLayout(preset_row)
        self.clinical_scales_rows = []
        self.clinical_scales_container = QVBoxLayout()
        clinical_lyt.addLayout(self.clinical_scales_container)
        # Empty raw
        self.update_clinical_scales([])
        clinical_content_layer.addWidget(gb_clinical)

        # Notes section
        gb_notes = QGroupBox("Initial notes")
        gb_notes.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Preferred)
        gb_notes.setFont(QFont("Segoe UI", 12, QFont.Bold))
        gb_notes.setStyleSheet("QGroupBox::title { color: #ff8800; font-size: 15pt; font-weight: 600; }")
        notes_lyt = QHBoxLayout(gb_notes)
        self.notes_edit = QTextEdit()
        self.notes_edit.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        notes_lyt.addWidget(self.notes_edit)
        clinical_content_layer.addWidget(gb_notes)
        main_content_layer.addLayout(clinical_content_layer)

        layout.addLayout(main_content_layer)

        # Next
        self.next_button_step1 = QPushButton("Next")
        self.next_button_step1.setIcon(self.style().standardIcon(QStyle.SP_ArrowForward))
        self.next_button_step1.setIconSize(QSize(22, 22))
        self.next_button_step1.setFixedWidth(150)
        self.next_button_step1.clicked.connect(self.go_to_step2_and_write_clinical)
        layout.addWidget(self.next_button_step1, alignment=Qt.AlignRight)

        return widget
    
    def browse_file_step1(self):
        file_path, _ = QFileDialog.getSaveFileName(self, "Save TSV File", "", "TSV Files (*.tsv)")
        if file_path:
            if not file_path.endswith(".tsv"):
                file_path += ".tsv"
            self.file_path_edit.setText(file_path)

    # --- CLINICAL SCALES ---
    def update_clinical_scales(self, preset_scales):
        for _, _, row_layout in self.clinical_scales_rows:
            while row_layout.count():
                item = row_layout.takeAt(0)
                widget = item.widget()
                if widget is not None:
                    widget.deleteLater()
            self.clinical_scales_container.removeItem(row_layout)
        self.clinical_scales_rows = []

        # Preset
        for name in preset_scales:
            self._add_clinical_scale_row(name=name, with_minus=True)
        self._add_clinical_scale_row(name="", with_plus=True)

    def _add_clinical_scale_row(self, name="", with_plus=False, with_minus=False):
        row = QHBoxLayout()
        name_edit = QLineEdit()
        name_edit.setPlaceholderText("Name")
        name_edit.setFixedWidth(100)
        name_edit.setText(name)
        score_edit = QLineEdit()
        score_edit.setPlaceholderText("Score")
        score_edit.setFixedWidth(60)

        if with_plus:
            btn = QPushButton("+")
            btn.setToolTip("Add clinical scale")
            btn.setFixedWidth(28)
            btn.clicked.connect(self.on_add_clinical_scale_clicked)
        elif with_minus:
            btn = QPushButton("-")
            btn.setToolTip("Remove clinical scale")
            btn.setFixedWidth(28)
            btn.clicked.connect(lambda: self.on_remove_clinical_scale_clicked(row))
        else:
            btn = QLabel("")  

        row.addWidget(QLabel("Name:"))
        row.addWidget(name_edit)
        row.addSpacing(10)
        row.addWidget(QLabel("Score:"))
        row.addWidget(score_edit)
        row.addWidget(btn)
        row.addStretch(1)
        self.clinical_scales_container.addLayout(row)
        self.clinical_scales_rows.append((name_edit, score_edit, row))

    def on_add_clinical_scale_clicked(self):
        preset_scales = [r[0].text() for r in self.clinical_scales_rows[:-1] if r[0].text()]
        last_row = self.clinical_scales_rows[-1]
        if last_row[0].text():
            preset_scales.append(last_row[0].text())
        self.update_clinical_scales(preset_scales)

    def on_remove_clinical_scale_clicked(self, layout):
        preset_scales = []
        for name_edit, _, row_layout in self.clinical_scales_rows[:-1]:
            if row_layout != layout:
                preset_scales.append(name_edit.text())
        self.update_clinical_scales(preset_scales)

    def apply_clinical_preset(self, label):
        if label == "OCD":
            preset = ["YBOCS", "YBOCS-o", "YBOCS-c", "MADRS"]
        elif label == "MDD":
            preset = ["MADRS"]
        elif label == "PD":
            preset = ["UPDRS", "PDQ"]
        elif label == "ET":
            preset = ["FTM"]
        else:
            preset = []
        self.update_clinical_scales(preset)
    

    def go_to_step2_and_write_clinical(self):
        file_path = self.file_path_edit.text().strip()
        if not file_path:
            QMessageBox.warning(self, "Missing file", "Please select a file path to save.")
            return
        # Save TSV file and write header if not already done
        if self.tsv_file is None:
            self.tsv_file = open(file_path, "w", newline="")
            self.tsv_writer = csv.DictWriter(self.tsv_file, fieldnames=self.tsv_columns, delimiter="\t")
            self.tsv_writer.writeheader()
        
        # write 
        today = datetime.now().strftime("%Y-%m-%d")
        stim_freq = self.stim_freq_edit.text()
        left_contact = self.left_contact_edit.text()
        left_amp = self.left_amp_edit.text()
        left_pw = self.left_pw_edit.text()
        right_contact = self.right_contact_edit.text()
        right_amp = self.right_amp_edit.text()
        right_pw = self.right_pw_edit.text()
        notes = self.notes_edit.toPlainText()
        if not self.clinical_scales_rows or all(score.text().strip()=='' for name, score, _ in self.clinical_scales_rows):
            row = {
                "date": today,
                "time": "0",
                "block_id": self.block_id_session,
                "scale_name": None,
                "scale_value": None,
                "stim_freq": stim_freq,
                "left_contact": left_contact,
                "left_amplitude": left_amp,
                "left_pulse_width": left_pw,
                "right_contact": right_contact,
                "right_amplitude": right_amp,
                "right_pulse_width": right_pw,
                "notes": notes
            }
            self.tsv_writer.writerow(row)
        else:
            for name_edit, score_edit, _ in self.clinical_scales_rows:
                name = name_edit.text().strip()
                score = score_edit.text().strip()
                if not name:
                    continue
                row = {
                    "date": today,
                    "time": "0",
                    "block_id": self.block_id_session,
                    "scale_name": name,
                    "scale_value": score,
                    "stim_freq": stim_freq,
                    "left_contact": left_contact,
                    "left_amplitude": left_amp,
                    "left_pulse_width": left_pw,
                    "right_contact": right_contact,
                    "right_amplitude": right_amp,
                    "right_pulse_width": right_pw,
                    "notes": notes
                }
                self.tsv_writer.writerow(row)
        
        self.tsv_file.flush()
        self.block_id_session += 1

        if self.step_widgets[1] is None:
            self.step_widgets[1] = self.create_step2()
            self.stack.addWidget(self.step_widgets[1])
        self.current_step += 1
        self.stack.setCurrentIndex(self.current_step)

        self.update_ui()

    # ------------------------------------------------------------------------------------
    # ------------------------------------------------------------------------------------
    # ------------------------------------------------------------------------------------

    def create_step2(self):
        widget = QWidget()
        layout = QVBoxLayout(widget)

        welcome_row = QHBoxLayout()

        # Logo
        image_label = QLabel()
        logo_pixmap = self.logo_path
        logo_pixmap = logo_pixmap.scaledToWidth(70, Qt.SmoothTransformation)
        logo_pixmap = au.rounded_pixmap(logo_pixmap, 5)
        image_label.setPixmap(logo_pixmap)
        image_label.setAlignment(Qt.AlignVCenter | Qt.AlignRight)
        welcome_row.addWidget(image_label, 1)  

        # Label
        welcome = QLabel("Which session scales would you like to track?")
        welcome.setStyleSheet("font-size: 16pt; font-weight: 500;")
        welcome.setAlignment(Qt.AlignVCenter | Qt.AlignLeft)
        welcome.setWordWrap(True)
        welcome_row.addWidget(welcome, 4) 

        layout.addLayout(welcome_row)
        
        # --- Session scales group ---
        gb_session = QGroupBox("Session scales")
        gb_session.setStyleSheet("QGroupBox::title { color: #ff8800; font-size: 15pt; font-weight: 600; }")
        gb_session.setFont(QFont("Segoe UI", 12, QFont.Bold))
        session_lyt = QVBoxLayout(gb_session)

        # presets
        preset_row2 = QHBoxLayout()
        preset_list = ["OCD", "MDD", "PD", "ET"]
        for label in preset_list:
            btn = QPushButton(label)
            btn.setObjectName(f"preset2_{label}")
            btn.clicked.connect(lambda checked, l=label: self.apply_session_preset(l))
            preset_row2.addWidget(btn)
            if label==preset_list[-1]:
                preset_row2.addStretch(1)
        preset_row2.addStretch(1)
        session_lyt.addLayout(preset_row2)

        self.session_scales_rows = []
        self.session_scales_container = QVBoxLayout()
        session_lyt.addLayout(self.session_scales_container)
        # Empty raw
        self.update_session_scales([])
        layout.addWidget(gb_session)
        layout.addStretch(1)

        # Next
        self.next_button_step2 = QPushButton("Next")
        self.next_button_step2.setIcon(self.style().standardIcon(QStyle.SP_ArrowForward))
        self.next_button_step2.setIconSize(QSize(22, 22))
        self.next_button_step2.setFixedWidth(150)
        self.next_button_step2.clicked.connect(self.go_to_step3_and_write_clinical)
        layout.addWidget(self.next_button_step2, alignment=Qt.AlignRight)

        return widget

    # --- SESSION SCALES LOGIC  ---
    def update_session_scales(self, preset_scales):
        for _, _, _, row_layout in self.session_scales_rows:
            while row_layout.count():
                item = row_layout.takeAt(0)
                widget = item.widget()
                if widget is not None:
                    widget.deleteLater()
            self.session_scales_container.removeItem(row_layout)
        self.session_scales_rows = []

        # Preset
        for name, minval, maxval in preset_scales:
            self._add_session_scale_row(name=name, minval=minval, maxval=maxval, with_minus=True)

        # empty raw
        self._add_session_scale_row(name="", minval="", maxval="", with_plus=True)

    def _add_session_scale_row(self, name="", minval="", maxval="", with_plus=False, with_minus=False):
        row = QHBoxLayout()
        name_edit = QLineEdit()
        name_edit.setPlaceholderText("Name")
        name_edit.setFixedWidth(120)
        name_edit.setText(name)
        scale1_edit = QLineEdit()
        scale1_edit.setPlaceholderText("Min")
        scale1_edit.setFixedWidth(50)
        scale1_edit.setText(minval)
        scale2_edit = QLineEdit()
        scale2_edit.setPlaceholderText("Max")
        scale2_edit.setFixedWidth(50)
        scale2_edit.setText(maxval)

        if with_plus:
            btn = QPushButton("+")
            btn.setToolTip("Add session scale")
            btn.setFixedWidth(28)
            btn.clicked.connect(self.on_add_session_scale_clicked)
        elif with_minus:
            btn = QPushButton("-")
            btn.setToolTip("Remove session scale")
            btn.setFixedWidth(28)
            btn.clicked.connect(lambda: self.on_remove_session_scale_clicked(row))
        else:
            btn = QLabel("")

        row.addWidget(QLabel("Name:"))
        row.addWidget(name_edit)
        row.addSpacing(10)
        row.addWidget(QLabel("Min:"))
        row.addWidget(scale1_edit)
        row.addWidget(QLabel("Max:"))
        row.addWidget(scale2_edit)
        row.addWidget(btn)
        row.addStretch(1)
        self.session_scales_container.addLayout(row)
        self.session_scales_rows.append((name_edit, scale1_edit, scale2_edit, row))

    def on_add_session_scale_clicked(self):
        preset_scales = []
        for name_edit, scale1_edit, scale2_edit, _ in self.session_scales_rows[:-1]:
            name = name_edit.text()
            minval = scale1_edit.text()
            maxval = scale2_edit.text()
            if name:
                preset_scales.append((name, minval, maxval))
        last_row = self.session_scales_rows[-1]
        if last_row[0].text():
            name = last_row[0].text()
            minval = last_row[1].text()
            maxval = last_row[2].text()
            preset_scales.append((name, minval, maxval))
        self.update_session_scales(preset_scales)

    def on_remove_session_scale_clicked(self, layout):
        preset_scales = []
        for name_edit, scale1_edit, scale2_edit, row_layout in self.session_scales_rows[:-1]:
            if row_layout != layout:
                name = name_edit.text()
                minval = scale1_edit.text()
                maxval = scale2_edit.text()
                if name:
                    preset_scales.append((name, minval, maxval))
        self.update_session_scales(preset_scales)

    def apply_session_preset(self, label):
        if label == "OCD":
            preset = [("Mood", "0", "10"), ("Anxiety", "0", "10"), ("Energy", "0", "10"), ("OCD", "0", "10")]
        elif label == "MDD":
            preset = [("Mood", "0", "10"), ("Anxiety", "0", "10"), ("Energy", "0", "10"), ("Rumination", "0", "10")]
        elif label == "PD":
            preset = [("Tremor", "0", "10"), ("Rigidity", "0", "10")]
        elif label == "ET":
            preset = [("Tremor", "0", "10"), ("Rigidity", "0", "10")]
        else:
            preset = []
        self.update_session_scales(preset)


    def go_to_step3_and_write_clinical(self):
        # Session scales for page 3
        self.session_scales_names = []
        for name_edit, scale1_edit, scale2_edit, _ in self.session_scales_rows:
            name = name_edit.text().strip()
            if name:
                self.session_scales_names.append(name)

        if self.step_widgets[2] is None:
            self.step_widgets[2] = self.create_step3()
            self.stack.addWidget(self.step_widgets[2])
        else:
            self.update_session_scales_step3()
        self.current_step = 2
        self.stack.setCurrentIndex(self.current_step)
        self.session_start_time = datetime.now()
        self.update_ui()

    # ------------------------------------------------------------------------------------
    # ------------------------------------------------------------------------------------
    # ------------------------------------------------------------------------------------


    def create_step3(self):
        widget = QWidget()
        layout = QVBoxLayout(widget)
        layout.setSpacing(18)
        layout.setContentsMargins(30, 18, 30, 18)

        welcome_row = QHBoxLayout()

        # Logo
        image_label = QLabel()
        logo_pixmap = self.logo_path
        logo_pixmap = logo_pixmap.scaledToWidth(70, Qt.SmoothTransformation)
        logo_pixmap = au.rounded_pixmap(logo_pixmap, 5)
        image_label.setPixmap(logo_pixmap)
        image_label.setAlignment(Qt.AlignVCenter | Qt.AlignRight)
        welcome_row.addWidget(image_label, 1)  

        # Label
        welcome = QLabel("Let's start with the clinical programming session")
        welcome.setStyleSheet("font-size: 16pt; font-weight: 500;")
        welcome.setAlignment(Qt.AlignVCenter | Qt.AlignLeft)
        welcome.setWordWrap(True)
        welcome_row.addWidget(welcome, 4) 

        layout.addLayout(welcome_row)

        main_content_layout = QHBoxLayout()

        gb_params = QGroupBox("Stimulation parameters")
        gb_params.setStyleSheet("QGroupBox::title { color: #ff8800; font-size: 15pt; font-weight: 600; }")
        gb_params.setFont(QFont("Segoe UI", 12, QFont.Bold))
        form = QFormLayout(gb_params)
        form.setLabelAlignment(Qt.AlignRight)
        form.setFormAlignment(Qt.AlignTop)
        form.setHorizontalSpacing(18)
        form.setVerticalSpacing(10)

        # Stimulation frequency
        self.session_stim_freq_edit = QLineEdit()
        self.session_stim_freq_edit.setPlaceholderText("Hz")
        self.session_stim_freq_edit.setText(self.stim_freq_edit.text())
        self.session_stim_freq_edit.setFixedWidth(100)
        self.session_stim_freq_edit.setValidator(QIntValidator(10, 200))
        form.addRow(QLabel("Stimulation frequency:"), self.add_increment_buttons(self.session_stim_freq_edit, step1=10, decimals=0, minval=10, maxval=200))

        form.addWidget(h_line())

        # Left contact
        self.session_left_contact_edit = QLineEdit()
        self.session_left_contact_edit.setPlaceholderText("e#")
        self.session_left_contact_edit.setText(self.left_contact_edit.text())
        self.session_left_contact_edit.setFixedWidth(100)
        form.addRow(QLabel("Left contact:"), self.session_left_contact_edit)

        # Left amplitude
        self.session_left_amp_edit = QLineEdit()
        self.session_left_amp_edit.setPlaceholderText("mA")
        self.session_left_amp_edit.setText(self.left_amp_edit.text())
        self.session_left_amp_edit.setFixedWidth(100)
        self.session_left_amp_edit.setValidator(QDoubleValidator(0.0, 15.0, 2))
        form.addRow(QLabel("Left amplitude:"), self.add_increment_buttons(self.session_left_amp_edit, step1=1.0, step2=0.5, decimals=1, minval=0.0, maxval=15.0))
        
        # Left pulse width
        self.session_left_pw_edit = QLineEdit()
        self.session_left_pw_edit.setPlaceholderText("µs")
        self.session_left_pw_edit.setText(self.left_pw_edit.text())
        self.session_left_pw_edit.setFixedWidth(100)
        self.session_left_pw_edit.setValidator(QIntValidator(10, 200))
        form.addRow(QLabel("Left pulse width:"), self.add_increment_buttons(self.session_left_pw_edit, step1=10, decimals=0, minval=10, maxval=200))

        form.addWidget(h_line())

        # Right contact
        self.session_right_contact_edit = QLineEdit()
        self.session_right_contact_edit.setPlaceholderText("e#")
        self.session_right_contact_edit.setText(self.right_contact_edit.text())
        self.session_right_contact_edit.setFixedWidth(100)
        form.addRow(QLabel("Right contact:"), self.session_right_contact_edit)

        # Right amplitude
        self.session_right_amp_edit = QLineEdit()
        self.session_right_amp_edit.setPlaceholderText("mA")
        self.session_right_amp_edit.setText(self.right_amp_edit.text())
        self.session_right_amp_edit.setFixedWidth(100)
        self.session_right_amp_edit.setValidator(QDoubleValidator(0.0, 15.0, 2))
        form.addRow(QLabel("Right amplitude:"), self.add_increment_buttons(self.session_right_amp_edit, step1=1.0, step2=0.5, decimals=1, minval=0.0, maxval=15.0))

        # Right pulse width
        self.session_right_pw_edit = QLineEdit()
        self.session_right_pw_edit.setPlaceholderText("µs")
        self.session_right_pw_edit.setText(self.right_pw_edit.text())
        self.session_right_pw_edit.setFixedWidth(100)
        self.session_right_pw_edit.setValidator(QIntValidator(10, 200))
        form.addRow(QLabel("Right pulse width:"), self.add_increment_buttons(self.session_right_pw_edit, step1=10, decimals=0, minval=10, maxval=200))

        main_content_layout.addWidget(gb_params)

        clinical_content_layout = QVBoxLayout()

        gb_session = QGroupBox("Session scales")
        gb_session.setStyleSheet("QGroupBox::title { color: #ff8800; font-size: 15pt; font-weight: 600; }")
        gb_session.setFont(QFont("Segoe UI", 12, QFont.Bold))
        self.session_scale_value_edits = []

        self.step3_session_scales_form = QFormLayout(gb_session)
        self.step3_session_scales_form.setLabelAlignment(Qt.AlignRight)
        self.step3_session_scales_form.setFormAlignment(Qt.AlignTop)
        self.step3_session_scales_form.setHorizontalSpacing(18)
        self.step3_session_scales_form.setVerticalSpacing(10)

        for name in getattr(self, "session_scales_names", []):
            value_edit = QLineEdit()
            value_edit.setPlaceholderText("value")
            value_edit.setFixedWidth(75)
            self.step3_session_scales_form.addRow(QLabel(name + ":"), self.add_increment_buttons(value_edit, step1=1, step2=0.5, decimals=2, minval=0, maxval=10))
            self.session_scale_value_edits.append((name, value_edit))

        # form = QFormLayout(gb_session)
        # form.setLabelAlignment(Qt.AlignRight)
        # form.setFormAlignment(Qt.AlignTop)
        # form.setHorizontalSpacing(18)
        # form.setVerticalSpacing(10)

        # for name in getattr(self, "session_scales_names", []):
        #     value_edit = QLineEdit()
        #     value_edit.setPlaceholderText("value")
        #     value_edit.setFixedWidth(75)
        #     form.addRow(QLabel(name + ":"), self.add_increment_buttons(value_edit, step1=1, step2=0.5, decimals=2, minval=0, maxval=10))
        #     self.session_scale_value_edits.append((name, value_edit))
        clinical_content_layout.addWidget(gb_session)
        clinical_content_layout.addWidget(h_line())

        gb_notes = QGroupBox("Session notes")
        gb_notes.setStyleSheet("QGroupBox::title { color: #ff8800; font-size: 15pt; font-weight: 600; }")
        gb_notes.setFont(QFont("Segoe UI", 12, QFont.Bold))
        notes_lyt = QHBoxLayout(gb_notes)
        self.session_notes_edit = QTextEdit()
        self.session_notes_edit.setMinimumHeight(30)#
        notes_lyt.addWidget(self.session_notes_edit)
        clinical_content_layout.addWidget(gb_notes)

        main_content_layout.addLayout(clinical_content_layout)
        layout.addLayout(main_content_layout)
        layout.addStretch(1)

        button_row = QHBoxLayout()
        button_row.addStretch(1)
        self.insert_button = QPushButton("Insert")
        self.insert_button.setIcon(self.style().standardIcon(QStyle.SP_DialogApplyButton))
        self.insert_button.setFixedWidth(150)
        self.insert_button.clicked.connect(self.insert_session_row)
        button_row.addWidget(self.insert_button)
        self.close_button = QPushButton("Close session")
        self.close_button.setIcon(self.style().standardIcon(QStyle.SP_DialogCloseButton))
        self.close_button.setFixedWidth(150)
        self.close_button.clicked.connect(self.close_session)
        button_row.addWidget(self.close_button)
        layout.addLayout(button_row)
        return widget
    


    def add_increment_buttons(self, lineedit, step1=1.0, step2=None, decimals=2, minval=None, maxval=None):
        container = QWidget()
        hbox = QHBoxLayout(container)
        hbox.setContentsMargins(0,0,0,0)
        hbox.setSpacing(0) 
        hbox.addWidget(lineedit)

        def adjust_value(le, delta):
            try:
                val = float(le.text())
            except Exception:
                val = 0.0
            val += delta
            if minval is not None:
                val = max(val, minval)
            if maxval is not None:
                val = min(val, maxval)
            le.setText(f"{val:.{decimals}f}")

        btn_width = 20
        btn_height = 14
        icon_size = 16

        def make_btn(icon):
            btn = QPushButton()
            btn.setIcon(icon)
            btn.setIconSize(QSize(icon_size, icon_size))
            btn.setFixedSize(btn_width, btn_height)
            btn.setCursor(Qt.PointingHandCursor)
            btn.setStyleSheet("""
                QPushButton {
                    background: transparent;
                    border: none;
                    padding: 0;
                }
                QPushButton:hover, QPushButton:pressed {
                    background: transparent;
                }
            """)
            return btn

        # ↑↓
        vbox1 = QVBoxLayout()
        vbox1.setContentsMargins(0,0,0,0)
        vbox1.setSpacing(0)
        btn_up1 = make_btn(au.create_arrow_icon("up", double=True))
        btn_down1 = make_btn(au.create_arrow_icon("down", double=True))
        btn_up1.clicked.connect(lambda: adjust_value(lineedit, +step1))
        btn_down1.clicked.connect(lambda: adjust_value(lineedit, -step1))
        vbox1.addWidget(btn_up1)
        vbox1.addWidget(btn_down1)
        hbox.addLayout(vbox1)
        
        btns = [btn_up1, btn_down1]
        # ↑↑↓↓
        if step2 is not None:
            vbox2 = QVBoxLayout()
            vbox2.setContentsMargins(0,0,0,0)
            vbox2.setSpacing(0)
            btn_up2 = make_btn(au.create_arrow_icon("up", double=False))
            btn_down2 = make_btn(au.create_arrow_icon("down", double=False))
            btn_up2.clicked.connect(lambda: adjust_value(lineedit, +step2))
            btn_down2.clicked.connect(lambda: adjust_value(lineedit, -step2))
            vbox2.addWidget(btn_up2)
            vbox2.addWidget(btn_down2)
            hbox.addLayout(vbox2)
            btns += [btn_up2, btn_down2]
        def sync_buttons_height():
            total_height = lineedit.height()
            #single_height = max(12, total_height // 2) if step2 is not None else total_height // 2
            single_height = total_height // 2
            if step2 is not None:
                for b in btns:
                    b.setFixedHeight(single_height)
            else:
                for b in btns:
                    b.setFixedHeight(total_height // 2)
        sync_buttons_height()

        container.setMaximumWidth(container.sizeHint().width())
        return container

    def update_session_scales_step3(self):
        form = self.step3_session_scales_form
        while form.rowCount():
            form.removeRow(0)
        self.session_scale_value_edits = []
        for name in self.session_scales_names:
            value_edit = QLineEdit()
            value_edit.setPlaceholderText("value")
            value_edit.setFixedWidth(75)
            form.addRow(QLabel(name + ":"), self.add_increment_buttons(
                value_edit, step1=1, step2=0.5, decimals=2, minval=0, maxval=10))
            self.session_scale_value_edits.append((name, value_edit))


    def insert_session_row(self):
        # ET time
        tz = pytz.timezone("US/Eastern")
        now_et = datetime.now(tz)
        time_str = now_et.strftime("%H:%M:%S")
        today = datetime.now().strftime("%Y-%m-%d")
        stim_freq = self.session_stim_freq_edit.text()
        left_contact = self.session_left_contact_edit.text()
        left_amp = self.session_left_amp_edit.text()
        left_pw = self.session_left_pw_edit.text()
        right_contact = self.session_right_contact_edit.text()
        right_amp = self.session_right_amp_edit.text()
        right_pw = self.session_right_pw_edit.text()
        notes = self.session_notes_edit.toPlainText()
        #wrote = False
        if not self.session_scale_value_edits or all(value.text().strip()=='' for name, value in self.session_scale_value_edits):
            row = {
                    "date": today,
                    "time": time_str,
                    "block_id": self.block_id_session,
                    "scale_name": None,
                    "scale_value": None,
                    "stim_freq": stim_freq,
                    "left_contact": left_contact,
                    "left_amplitude": left_amp,
                    "left_pulse_width": left_pw,
                    "right_contact": right_contact,
                    "right_amplitude": right_amp,
                    "right_pulse_width": right_pw,
                    "notes": notes
                }
            self.tsv_writer.writerow(row)
            #wrote = True
        else:
            for name, value_edit in self.session_scale_value_edits:
                scale_value = value_edit.text().strip()
                if not name or not scale_value:
                    continue
                row = {
                    "date": today,
                    "time": time_str,
                    "block_id": self.block_id_session,
                    "scale_name": name,
                    "scale_value": scale_value,
                    "stim_freq": stim_freq,
                    "left_contact": left_contact,
                    "left_amplitude": left_amp,
                    "left_pulse_width": left_pw,
                    "right_contact": right_contact,
                    "right_amplitude": right_amp,
                    "right_pulse_width": right_pw,
                    "notes": notes
                }
                self.tsv_writer.writerow(row)
                #wrote = True

        self.tsv_file.flush()
        #if wrote:
        self.block_id_session += 1
        au.animate_insert_button(self.insert_button)
        self.session_notes_edit.clear()

    def close_session(self):
        if self.tsv_file:
            self.tsv_file.close()
            self.tsv_file = None
        QMessageBox.information(self, "Session closed", "Session closed and file saved.")
        self.close()

    def create_nav_bar(self):
        nav_layout = QHBoxLayout()
        self.back_button = QPushButton("Back")
        self.back_button.setIcon(self.style().standardIcon(QStyle.SP_ArrowBack))
        self.back_button.setIconSize(QSize(22, 22))
        self.back_button.setFixedWidth(140)
        self.back_button.clicked.connect(self.go_back)
        nav_layout.addWidget(self.back_button)
        nav_layout.addStretch()
        return nav_layout

    def go_back(self):
        if self.current_step > 0:
            self.current_step -= 1
            self.stack.setCurrentIndex(self.current_step)
            self.update_ui()

    def update_ui(self):
        if hasattr(self, "back_button"):
            self.back_button.setEnabled(self.current_step > 0)
        if hasattr(self, "back_button3"):
            self.back_button3.setEnabled(self.current_step > 0)

if __name__ == "__main__":
    try:
        import pytz
    except ImportError:
        print("Install pytz for timezone support: pip install pytz")
        sys.exit(1)
    QApplication.setAttribute(Qt.AA_EnableHighDpiScaling, True)
    QApplication.setAttribute(Qt.AA_UseHighDpiPixmaps, True)
    app = QApplication(sys.argv)
    qss_path = os.path.join(resource_path('style.qss'))
    if os.path.exists(qss_path):
        with open(qss_path, 'r') as f:
            app.setStyleSheet(f.read())
    window = WizardWindow()
    window.show()
    sys.exit(app.exec_())