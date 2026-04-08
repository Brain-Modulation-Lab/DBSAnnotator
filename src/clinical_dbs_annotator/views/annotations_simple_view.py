"""
Simplified annotations view for annotations-only mode.

This module contains views for the simplified workflow that only
handles file naming and text annotations.
"""

import os

from PySide6.QtCore import QSize
from PySide6.QtWidgets import (
    QFileDialog,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QMenu,
    QMessageBox,
    QPushButton,
    QSizePolicy,
    QStyle,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from ..ui import FileDropLineEdit


class AnnotationsFileView(QWidget):
    """View for file selection in annotations-only mode."""

    def __init__(self, parent=None):
        """Initialize the file selection view."""
        super().__init__(parent)
        self.parent_style = self.style()

        self.current_file_mode = None

        self.main_layout = QVBoxLayout(self)
        self.main_layout.setContentsMargins(20, 20, 20, 20)
        self.main_layout.setSpacing(15)

        # File information group
        file_group = self._create_upload_tsv_group()
        self.main_layout.addWidget(file_group)

        self.main_layout.addStretch(1)

        self.next_button = QPushButton("Next")
        self.next_button.setIcon(self.parent_style.standardIcon(QStyle.SP_ArrowForward))
        self.next_button.setIconSize(QSize(16, 16))
        self.next_button.setMaximumWidth(120)

        # Add the next button to the layout
        self.main_layout.addWidget(self.next_button)

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
        """Load an existing TSV file and populate the path field."""
        import csv
        try:
            self.file_path_edit.setText(file_path)
            self.current_file_mode = "existing"

            with open(file_path, newline="", encoding="utf-8") as f:
                reader = csv.DictReader(f, delimiter="\t")
                for row in reader:
                    try:
                        bid_raw = row.get("block_id", "")
                        if bid_raw is None or bid_raw == "":
                            continue
                        int(float(bid_raw))
                    except Exception:
                        continue


        except Exception as e:
            QMessageBox.warning(self, "Error", f"Failed to load file: {str(e)}")


    def create_new_file(self) -> None:
        """Create new file with BIDS-style naming via a dialog."""
        from datetime import datetime

        from PySide6.QtWidgets import QDialog, QDialogButtonBox, QFormLayout, QLineEdit

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

        current_path = self.file_path_edit.text().strip()
        start_dir = os.path.dirname(current_path) if current_path else ""

        subject_id = f"sub-{patient_id}"
        session_id = f"ses-{session_num}"
        task = "task-notes"
        run_id = f"run-{run_num}"
        default_name = f"{subject_id}_{session_id}_{task}_{run_id}_events.tsv"

        default_path = os.path.join(start_dir, default_name) if start_dir else default_name

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
        self.file_path_edit.setPlaceholderText("Drop a .tsv annotation file or use the buttons")

        open_button = QPushButton()
        open_button.setText("Open")
        open_button.setMaximumWidth(90)
        open_button.setFixedHeight(45)
        open_button.setToolTip("Open existing file")
        open_button.clicked.connect(self.open_existing_file)

        self.create_button = QPushButton()
        self.create_button.setText("New")
        self.create_button.setMaximumWidth(90)
        self.create_button.setFixedHeight(45)
        self.create_button.setToolTip("Create new file")
        self.create_button.clicked.connect(self.create_new_file)

        layout.addWidget(self.file_path_edit, 1)
        layout.addWidget(open_button)
        layout.addWidget(self.create_button)

        return gb_upload


class AnnotationsSessionView(QWidget):
    """View for recording annotations in annotations-only mode."""

    def __init__(self, parent=None):
        """Initialize the annotations session view."""
        super().__init__(parent)

        self.parent_style = self.style()

        self.main_layout = QVBoxLayout(self)
        self.main_layout.setContentsMargins(20, 20, 20, 20)
        self.main_layout.setSpacing(15)

        # Annotation input group
        annotation_group = self._create_annotation_group()
        self.main_layout.addWidget(annotation_group)

        self.insert_button = QPushButton("Insert")
        self.insert_button.setIcon(
            self.parent_style.standardIcon(QStyle.SP_DialogApplyButton)
        )
        self.insert_button.setMinimumWidth(170)

        self.close_button = QPushButton("Close Session")
        self.close_button.setIcon(
            self.parent_style.standardIcon(QStyle.SP_DialogCloseButton)
        )
        self.close_button.setMinimumWidth(170)

        self.export_button = QPushButton("Export Report")
        self.export_button.setIcon(
            self.parent_style.standardIcon(QStyle.SP_DialogSaveButton)
        )
        self.export_button.setMinimumWidth(170)

        self.export_menu = QMenu(self)
        self.export_word_action = self.export_menu.addAction("📄 Word Report")
        self.export_pdf_action = self.export_menu.addAction("📋 PDF Report")
        self.export_button.setMenu(self.export_menu)

    def _create_annotation_group(self) -> QGroupBox:
        """Create the annotation input group box."""
        gb_annotation = QGroupBox("Session Annotations")
     #   gb_annotation.setFont(QFont("Segoe UI", 10, QFont.Bold))

        layout = QVBoxLayout(gb_annotation)
        layout.setSpacing(10)

        # Instructions
        instructions = QLabel(
            "Enter your observations and notes below. "
            "Each annotation will be saved with the current timestamp."
        )
        instructions.setWordWrap(True)
        instructions.setStyleSheet("color: #64748b; padding: 5px;")
        layout.addWidget(instructions)

        # Annotation text area
        self.annotation_edit = QTextEdit()
        self.annotation_edit.setPlaceholderText("Type your notes here...")
        self.annotation_edit.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.annotation_edit.setMinimumHeight(50)
        layout.addWidget(self.annotation_edit)

        return gb_annotation

    def get_annotation(self) -> str:
        """Get the current annotation text."""
        return self.annotation_edit.toPlainText()

    def clear_annotation(self) -> None:
        """Clear the annotation text area."""
        self.annotation_edit.clear()
