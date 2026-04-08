"""
Session data management model.

This module contains the main SessionData class that manages all data
for a clinical DBS programming session, including TSV file writing.
"""

import csv
from datetime import datetime
from pathlib import Path
from typing import TextIO

import pytz

from ..config import TIMEZONE, TSV_COLUMNS
from .clinical_scale import ClinicalScale, SessionScale
from .stimulation import StimulationParameters


class SessionData:
    """
    Manages all data for a clinical DBS programming session.

    This class handles:
    - TSV file creation and writing
    - Block ID tracking
    - Clinical and session scales management
    - Stimulation parameters tracking
    """

    def __init__(self, file_path: str | None = None):
        """
        Initialize a new session.

        Args:
            file_path: Path to the TSV file where data will be saved
        """
        self.file_path = file_path
        self.tsv_file: TextIO | None = None
        self.tsv_writer: csv.DictWriter | None = None
        self.tsv_fieldnames: list[str] | None = None
        self.block_id: int = 0
        self.session_id: int = 1
        self.session_start_time: datetime | None = None

        if file_path:
            self.open_file(file_path)

    def open_file(self, file_path: str) -> None:
        """
        Open a TSV file for writing and initialize the CSV writer.

        Args:
            file_path: Path to the TSV file
        """
        self.file_path = file_path
        self.close_file()
        self.block_id = 0
        self.session_id = 1
        self.tsv_file = open(file_path, "w", newline="", encoding="utf-8")
        self.tsv_fieldnames = list(TSV_COLUMNS)
        self.tsv_writer = csv.DictWriter(
            self.tsv_file,
            fieldnames=self.tsv_fieldnames,
            delimiter="\t",
            extrasaction="ignore",
        )
        self.tsv_writer.writeheader()
        self.session_start_time = datetime.now()

    def open_file_append(self, file_path: str, start_block_id: int | None = None) -> None:
        """Open an existing TSV file in append mode and continue block numbering."""
        self.file_path = file_path
        self.close_file()

        file_exists = Path(file_path).exists()
        if not file_exists:
            self.open_file(file_path)
            return

        # Calculate next session_id and block_id
        max_block = -1
        max_session = 0
        try:
            with open(file_path, newline="", encoding="utf-8") as f:
                reader = csv.DictReader(f, delimiter="\t")
                for row in reader:
                    try:
                        # Get max block_id
                        val = row.get("block_id", None)
                        if val is not None and val != "":
                            max_block = max(max_block, int(float(val)))

                        # Get max session_ID
                        session_val = row.get("session_ID", None)
                        if session_val is not None and session_val != "":
                            max_session = max(max_session, int(float(session_val)))
                    except Exception:
                        continue
        except Exception:
            max_block = -1
            max_session = 0

        if start_block_id is None:
            start_block_id = max_block + 1

        self.block_id = int(start_block_id)
        self.session_id = max_session + 1
        self.tsv_file = open(file_path, "a", newline="", encoding="utf-8")
        existing_fieldnames: list[str] | None = None
        try:
            with open(file_path, newline="", encoding="utf-8") as f:
                reader = csv.DictReader(f, delimiter="\t")
                existing_fieldnames = reader.fieldnames
        except Exception:
            existing_fieldnames = None

        self.tsv_fieldnames = existing_fieldnames or list(TSV_COLUMNS)

        self.tsv_writer = csv.DictWriter(
            self.tsv_file,
            fieldnames=self.tsv_fieldnames,
            delimiter="\t",
            extrasaction="ignore",
        )
        try:
            if Path(file_path).stat().st_size == 0:
                self.tsv_writer.writeheader()
        except Exception:
            pass
        self.session_start_time = datetime.now()


    def close_file(self) -> None:
        """Close the TSV file if it's open."""
        if self.tsv_file:
            self.tsv_file.close()
            self.tsv_file = None
            self.tsv_writer = None

    def write_clinical_scales(
        self,
        scales: list[ClinicalScale],
        stimulation: StimulationParameters,
        group: str = "",
        electrode_model: str = "",
        notes: str = "",
    ) -> None:
        """
        Write clinical scales data to the TSV file.

        Args:
            scales: List of clinical scales to write
            stimulation: Stimulation parameters
            notes: Additional notes for this entry
        """
        if not self.tsv_writer:
            raise ValueError("TSV file not opened. Call open_file() first.")

        tz = pytz.timezone(TIMEZONE)
        now_et = datetime.now(tz)
        time_str = now_et.strftime("%H:%M:%S")
        today = datetime.now().astimezone().strftime("%Y-%m-%d")
        stim_dict = stimulation.to_dict()

        # If no scales have values, write a single row with null scale data
        valid_scales = [s for s in scales if s.is_valid()]
        if not valid_scales:
            row = {
                "date": today,
                "time": time_str,
                "block_id": self.block_id,
                "group_ID": group,
                "session_ID": self.session_id,
                "is_initial": 1,  # Clinical scales are from view1, so is_initial = 1
                "scale_name": None,
                "scale_value": None,
                "electrode_model": electrode_model,
                "notes": notes,
                **stim_dict,
            }
            self.tsv_writer.writerow(row)
        else:
            # Write one row per scale
            for scale in valid_scales:
                row = {
                    "date": today,
                    "time": time_str,
                    "block_id": self.block_id,
                    "group_ID": group,
                    "session_ID": self.session_id,
                    "is_initial": 1,  # Clinical scales are from view1, so is_initial = 1
                    "scale_name": scale.name,
                    "scale_value": scale.value,
                    "electrode_model": electrode_model,
                    "notes": notes,
                    **stim_dict,
                }
                self.tsv_writer.writerow(row)

        self.tsv_file.flush()
        self.block_id += 1

    def write_session_scales(
        self,
        scales: list[SessionScale],
        stimulation: StimulationParameters,
        group: str = "",
        electrode_model: str = "",
        notes: str = "",
    ) -> None:
        """
        Write session scales data to the TSV file with current timestamp.

        Args:
            scales: List of session scales to write
            stimulation: Stimulation parameters
            notes: Additional notes for this entry
        """
        if not self.tsv_writer:
            raise ValueError("TSV file not opened. Call open_file() first.")

        # Get current time in Eastern timezone
        tz = pytz.timezone(TIMEZONE)
        now_et = datetime.now(tz)
        time_str = now_et.strftime("%H:%M:%S")
        today = datetime.now().astimezone().strftime("%Y-%m-%d")
        stim_dict = stimulation.to_dict()

        # If no scales have values, write a single row with null scale data
        valid_scales = [s for s in scales if s.has_value()]
        if not valid_scales:
            row = {
                "date": today,
                "time": time_str,
                "block_id": self.block_id,
                "group_ID": group,
                "session_ID": self.session_id,
                "is_initial": 0,  # Session scales are from view3, so is_initial = 0
                "scale_name": None,
                "scale_value": None,
                "electrode_model": electrode_model,
                "notes": notes,
                **stim_dict,
            }
            self.tsv_writer.writerow(row)
        else:
            # Write one row per scale
            for scale in valid_scales:
                row = {
                    "date": today,
                    "time": time_str,
                    "block_id": self.block_id,
                    "group_ID": group,
                    "session_ID": self.session_id,
                    "is_initial": 0,  # Session scales are from view3, so is_initial = 0
                    "scale_name": scale.name,
                    "scale_value": scale.current_value,
                    "electrode_model": electrode_model,
                    "notes": notes,
                    **stim_dict,
                }
                self.tsv_writer.writerow(row)

        self.tsv_file.flush()
        self.block_id += 1

    def is_file_open(self) -> bool:
        """Check if a TSV file is currently open."""
        return self.tsv_file is not None

    def __enter__(self):
        """Context manager entry."""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit - ensures file is closed."""
        self.close_file()

    def __del__(self):
        """Destructor - ensures file is closed."""
        self.close_file()

    # ============================================
    # Annotations-Only Workflow Methods
    # ============================================

    def initialize_simple_file(self, filepath: str) -> None:
        """
        Initialize a simple TSV file for annotations-only mode.

        Args:
            filepath: Full path to the TSV file to create

        Raises:
            ValueError: If a file is already open
            IOError: If file cannot be created
        """
        if self.is_file_open():
            raise ValueError("A file is already open. Close it before initializing a new one.")

        self.file_path = filepath

        # Create the file with headers
        self.tsv_file = open(filepath, "w", newline="", encoding="utf-8")

        # Simple header: date, time, and annotation
        fieldnames = ["date", "time", "annotation"]

        self.tsv_writer = csv.DictWriter(
            self.tsv_file,
            fieldnames=fieldnames,
            delimiter="\t",
            extrasaction="ignore",
        )
        self.tsv_writer.writeheader()
        self.tsv_file.flush()

    def open_simple_file_append(self, filepath: str) -> None:
        """Open an existing annotations-only TSV file in append mode (or create if missing)."""
        if self.is_file_open():
            raise ValueError("A file is already open. Close it before opening another file.")

        self.file_path = filepath

        file_exists = Path(filepath).exists()
        self.tsv_file = open(filepath, "a", newline="", encoding="utf-8")

        fieldnames: list[str] | None = None
        if file_exists:
            try:
                with open(filepath, newline="", encoding="utf-8") as f:
                    reader = csv.DictReader(f, delimiter="\t")
                    fieldnames = reader.fieldnames
            except Exception:
                fieldnames = None

        fieldnames = fieldnames or ["date", "time", "annotation"]

        self.tsv_writer = csv.DictWriter(
            self.tsv_file,
            fieldnames=fieldnames,
            delimiter="\t",
            extrasaction="ignore",
        )

        try:
            if (not file_exists) or Path(filepath).stat().st_size == 0:
                self.tsv_writer.writeheader()
                self.tsv_file.flush()
        except Exception:
            pass

    def write_simple_annotation(self, annotation: str) -> None:
        """
        Write a simple annotation with timestamp.

        Args:
            annotation: The annotation text to write

        Raises:
            ValueError: If no file is open
        """
        if not self.is_file_open():
            raise ValueError("No file is open. Call initialize_simple_file first.")

        # Get current time
        from datetime import datetime


        time_str = datetime.now().astimezone().strftime("%H:%M:%S")
        date_str = datetime.now().astimezone().strftime("%Y-%m-%d")

        # Write row
        row = {
            "date": date_str,
            "time": time_str,
            "annotation": annotation,
        }
        self.tsv_writer.writerow(row)
        self.tsv_file.flush()
