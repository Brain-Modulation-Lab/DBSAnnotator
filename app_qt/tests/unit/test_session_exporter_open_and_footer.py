"""SessionExporter small static paths: open file, filename, footer."""

from __future__ import annotations

import sys
from unittest.mock import MagicMock, patch

import pytest
from docx import Document

from dbs_annotator.models.session_data import SessionData
from dbs_annotator.utils import session_exporter as session_exporter_mod
from dbs_annotator.utils.session_exporter import SessionExporter


def test_generate_bids_report_filename_with_bids_path():
    sd = MagicMock(spec=SessionData)
    sd.file_path = r"C:\data\sub-ABC_ses-20250101_task-custom_run-2_events.tsv"
    ex = SessionExporter(sd)
    name = ex._generate_bids_report_filename(".docx")
    assert name.startswith("sub-ABC_")
    assert "_task-custom_" in name
    assert name.endswith("_report.docx")
    assert "run-2" in name


def test_generate_bids_report_filename_empty_path():
    sd = MagicMock(spec=SessionData)
    sd.file_path = ""
    ex = SessionExporter(sd)
    name = ex._generate_bids_report_filename(".pdf")
    assert name.startswith("dbs_session_report_")
    assert name.endswith(".pdf")


def test_extract_bids_info_formats_numeric_session():
    sd = MagicMock(spec=SessionData)
    sd.file_path = r"C:\sub-01_ses-20250315_task-x_events.tsv"
    ex = SessionExporter(sd)
    pid, ses = ex._extract_bids_info_from_path()
    assert pid == "01"
    assert ses == "2025-03-15"


def test_extract_bids_info_non_numeric_session_passthrough():
    sd = MagicMock(spec=SessionData)
    sd.file_path = r"C:\sub-01_ses-pre_task-x_events.tsv"
    ex = SessionExporter(sd)
    pid, ses = ex._extract_bids_info_from_path()
    assert pid == "01"
    assert ses == "pre"


def test_add_report_footer_with_patient(tmp_path):
    sd = MagicMock(spec=SessionData)
    sd.file_path = str(tmp_path / "sub-99_ses-20250101_task-p_events.tsv")
    ex = SessionExporter(sd)
    doc = Document()
    ex._add_report_footer(doc)
    assert len(doc.paragraphs) >= 1


@pytest.mark.parametrize("platform", ["win32", "darwin", "linux"])
def test_open_file_platform_branches(platform, monkeypatch, tmp_path):
    p = tmp_path / "x.txt"
    p.write_text("hi", encoding="utf-8")
    monkeypatch.setattr(sys, "platform", platform)
    if platform == "win32":
        # os.startfile exists only on Windows; create=True allows patching
        # on macOS/Linux CI.
        with patch.object(session_exporter_mod.os, "startfile", create=True) as op:
            SessionExporter._open_file(str(p))
            op.assert_called_once_with(str(p))
    else:
        with patch("subprocess.Popen") as po:
            SessionExporter._open_file(str(p))
            po.assert_called_once()
