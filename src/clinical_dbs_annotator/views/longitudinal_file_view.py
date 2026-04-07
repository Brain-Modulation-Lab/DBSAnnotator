"""
Longitudinal file view: load multiple annotation TSV files for longitudinal reporting.

This module contains the view where users can drag-and-drop or browse to load
multiple annotation files from the same patient, then generate a unified
longitudinal report.
"""

import os
import re
import csv
from typing import List, Dict, Tuple, Optional

from PyQt5.QtCore import Qt, QSize, QMimeData
from PyQt5.QtWidgets import (
    QWidget,
    QVBoxLayout,
    QHBoxLayout,
    QPushButton,
    QLabel,
    QGroupBox,
    QStyle,
    QSizePolicy,
    QFileDialog,
    QMessageBox,
    QListWidget,
    QListWidgetItem,
    QAbstractItemView,
    QMenu,
)


class FileDropZone(QWidget):
    """A drop zone widget that accepts multiple TSV file drops."""

    def __init__(self, on_files_dropped, parent=None):
        super().__init__(parent)
        self._on_files_dropped = on_files_dropped
        self.setAcceptDrops(True)
        self.setMinimumHeight(80)
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
        self._label = QLabel("Drop .tsv annotation files here\nor use the Add Files button")
        self._label.setAlignment(Qt.AlignCenter)
        self._label.setStyleSheet("color: #64748b; padding: 10px;")
        self._label.setAttribute(Qt.WA_TransparentForMouseEvents, True)
        layout = QVBoxLayout(self)
        layout.addWidget(self._label)
        self._update_style(False)

    def _update_style(self, hovering: bool):
        border_color = "#f59e0b" if hovering else "#475569"
        self.setStyleSheet(
            f"FileDropZone {{ border: 2px dashed {border_color}; "
            f"border-radius: 8px; background: transparent; }}"
        )

    def dragEnterEvent(self, event):
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
            self._update_style(True)
            return
        super().dragEnterEvent(event)

    def dragLeaveEvent(self, event):
        self._update_style(False)
        super().dragLeaveEvent(event)

    def dropEvent(self, event):
        self._update_style(False)
        if event.mimeData().hasUrls():
            paths = []
            for url in event.mimeData().urls():
                local = url.toLocalFile()
                if local and local.lower().endswith(".tsv"):
                    paths.append(local)
            if paths:
                self._on_files_dropped(paths)
            event.acceptProposedAction()
            return
        super().dropEvent(event)


class LongitudinalFileView(QWidget):
    """
    View for loading multiple annotation TSV files for longitudinal reporting.

    Users can:
    - Drag-and-drop multiple .tsv files
    - Browse to add files
    - Remove individual files from the list
    - Generate a unified longitudinal report (Word/PDF)
    """

    def __init__(self, parent=None):
        """Initialize the longitudinal file view."""
        super().__init__(parent)
        self.parent_style = self.style()
        self.loaded_files: List[str] = []

        self.main_layout = QVBoxLayout(self)
        self.main_layout.setContentsMargins(20, 20, 20, 20)
        self.main_layout.setSpacing(15)

        # File upload group
        file_group = self._create_file_group()
        self.main_layout.addWidget(file_group)

        # Stretch to push buttons down
        self.main_layout.addStretch(1)

        # Export button with dropdown menu
        self.export_button = QPushButton("Create Report")
        self.export_button.setIcon(
            self.parent_style.standardIcon(QStyle.SP_DialogSaveButton)
        )
        self.export_button.setMinimumWidth(170)

        self.export_menu = QMenu(self)
        self.export_word_action = self.export_menu.addAction("📄 Word Report")
        self.export_word_action.setToolTip("Export to Word (.docx) document")
        self.export_pdf_action = self.export_menu.addAction("📋 PDF Report")
        self.export_pdf_action.setToolTip("Export to PDF document")
        self.export_button.setMenu(self.export_menu)

    def get_header_title(self) -> str:
        """Return the header title for this view."""
        return "Longitudinal Report"

    def _create_file_group(self) -> QGroupBox:
        """Create the file upload group with drop zone and file list."""
        gb = QGroupBox("Annotation Files")
        gb.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)

        layout = QVBoxLayout(gb)
        layout.setSpacing(10)

        # Instructions
        instructions = QLabel(
            "Load multiple annotation session files (.tsv) from the same patient "
            "to create a unified longitudinal report."
        )
        instructions.setWordWrap(True)
        instructions.setStyleSheet("color: #64748b; padding: 5px;")
        layout.addWidget(instructions)

        # Buttons row
        btn_row = QHBoxLayout()

        self.add_files_button = QPushButton("Add Files")
        self.add_files_button.setIcon(
            self.parent_style.standardIcon(QStyle.SP_FileDialogNewFolder)
        )
        self.add_files_button.setMaximumWidth(140)
        self.add_files_button.clicked.connect(self._browse_files)
        btn_row.addWidget(self.add_files_button)

        self.remove_selected_button = QPushButton("Remove Selected")
        self.remove_selected_button.setIcon(
            self.parent_style.standardIcon(QStyle.SP_TrashIcon)
        )
        self.remove_selected_button.setMaximumWidth(160)
        self.remove_selected_button.clicked.connect(self._remove_selected)
        btn_row.addWidget(self.remove_selected_button)

        self.clear_all_button = QPushButton("Clear All")
        self.clear_all_button.setMaximumWidth(100)
        self.clear_all_button.clicked.connect(self._clear_all)
        btn_row.addWidget(self.clear_all_button)

        btn_row.addStretch(1)
        layout.addLayout(btn_row)

        # File list with embedded drop zone
        file_container = QWidget()
        file_container_layout = QVBoxLayout(file_container)
        file_container_layout.setContentsMargins(0, 0, 0, 0)
        file_container_layout.setSpacing(0)

        # Drop zone inside file list area
        self.drop_zone = FileDropZone(self._on_files_dropped)
        self.drop_zone.setMaximumHeight(60)
        file_container_layout.addWidget(self.drop_zone)

        # File list
        self.file_list = QListWidget()
        self.file_list.setSelectionMode(QAbstractItemView.ExtendedSelection)
        self.file_list.setMinimumHeight(120)
        self.file_list.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.file_list.setAlternatingRowColors(True)
        file_container_layout.addWidget(self.file_list)

        layout.addWidget(file_container)

        # Patient mismatch warning label (hidden by default)
        self.warning_label = QLabel("")
        self.warning_label.setWordWrap(True)
        self.warning_label.setStyleSheet(
            "color: #dc2626; font-weight: bold; padding: 4px;"
        )
        self.warning_label.setVisible(False)
        layout.addWidget(self.warning_label)

        # Status label
        self.status_label = QLabel("No files loaded")
        self.status_label.setStyleSheet("color: #64748b; font-style: italic;")
        layout.addWidget(self.status_label)

        return gb

    def _on_files_dropped(self, paths: List[str]) -> None:
        """Handle files dropped onto the drop zone."""
        added = 0
        for path in paths:
            if path not in self.loaded_files:
                self.loaded_files.append(path)
                added += 1
        if added > 0:
            self._refresh_file_list()

    def _browse_files(self) -> None:
        """Open file dialog to select TSV files."""
        paths, _ = QFileDialog.getOpenFileNames(
            self,
            "Select Annotation Files",
            "",
            "TSV Files (*.tsv);;All Files (*)",
        )
        if paths:
            self._on_files_dropped(paths)

    def _remove_selected(self) -> None:
        """Remove selected files from the list."""
        selected = self.file_list.selectedItems()
        if not selected:
            return
        for item in selected:
            path = item.data(Qt.UserRole)
            if path in self.loaded_files:
                self.loaded_files.remove(path)
        self._refresh_file_list()

    def _clear_all(self) -> None:
        """Clear all loaded files."""
        self.loaded_files.clear()
        self._refresh_file_list()

    def _refresh_file_list(self) -> None:
        """Refresh the file list widget from loaded_files."""
        self.file_list.clear()
        for path in self.loaded_files:
            basename = os.path.basename(path)
            item = QListWidgetItem(basename)
            item.setData(Qt.UserRole, path)
            item.setToolTip(path)
            self.file_list.addItem(item)
        count = len(self.loaded_files)
        self.status_label.setText(
            f"{count} file{'s' if count != 1 else ''} loaded"
            if count > 0
            else "No files loaded"
        )
        self._validate_patient_ids()

    def _validate_patient_ids(self) -> None:
        """Check that all loaded files belong to the same patient."""
        if len(self.loaded_files) < 2:
            self.warning_label.setVisible(False)
            return

        ids = set()
        for path in self.loaded_files:
            pid = self._extract_patient_id(path)
            if pid:
                ids.add(pid)

        if len(ids) > 1:
            self.warning_label.setText(
                f"⚠ Warning: Files belong to different patients ({', '.join(sorted(ids))}). "
                "Please ensure all files are from the same patient."
            )
            self.warning_label.setVisible(True)
        else:
            self.warning_label.setVisible(False)

    @staticmethod
    def _extract_patient_id(file_path: str) -> Optional[str]:
        """Extract patient ID (sub-XXX) from a BIDS-like filename."""
        m = re.search(r"sub-([^_]+)", os.path.basename(file_path))
        return m.group(1) if m else None

    def get_loaded_files(self) -> List[str]:
        """Return the list of loaded file paths."""
        return list(self.loaded_files)

    @staticmethod
    def extract_session_scales_from_files(
        file_paths: List[str],
    ) -> List[Tuple[str, str, str]]:
        """
        Read all TSV files and extract unique session scale names (is_initial == 0).

        Returns:
            List of (scale_name, min_value, max_value) tuples with observed ranges.
        """
        scale_values: Dict[str, List[float]] = {}

        for path in file_paths:
            try:
                with open(path, "r", newline="", encoding="utf-8") as f:
                    reader = csv.DictReader(f, delimiter="\t")
                    for row in reader:
                        is_initial = row.get("is_initial", "").strip()
                        if is_initial not in ("0", "0.0"):
                            continue
                        scale_name = (row.get("scale_name") or "").strip()
                        scale_value = (row.get("scale_value") or "").strip()
                        if not scale_name or not scale_value:
                            continue
                        try:
                            val = float(scale_value)
                        except ValueError:
                            continue
                        if scale_name not in scale_values:
                            scale_values[scale_name] = []
                        scale_values[scale_name].append(val)
            except Exception as e:
                print(f"[WARNING] Could not read {path}: {e}")

        result = []
        for name, values in scale_values.items():
            min_v = str(min(values))
            max_v = str(max(values))
            result.append((name, min_v, max_v))
        return result
