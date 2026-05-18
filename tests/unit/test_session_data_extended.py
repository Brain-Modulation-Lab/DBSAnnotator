"""Extended SessionData coverage: append mode, simple annotations, errors."""

from __future__ import annotations

import csv

import pytest

from dbs_annotator.config import TSV_COLUMNS
from dbs_annotator.models import SessionData, StimulationParameters
from dbs_annotator.utils.tsv_columns import BLOCK_ID_COLUMN


def _stim() -> StimulationParameters:
    return StimulationParameters(
        left_frequency="130",
        left_cathode="e1",
        left_anode="e3",
        left_amplitude="3",
        left_pulse_width="60",
        right_frequency="130",
        right_cathode="e2",
        right_anode="e4",
        right_amplitude="3",
        right_pulse_width="60",
    )


def test_open_file_append_creates_when_missing(tmp_path):
    p = tmp_path / "new.tsv"
    sd = SessionData()
    sd.open_file_append(str(p))
    try:
        assert sd.is_file_open()
        assert sd.block_id == 0
    finally:
        sd.close_file()


def test_open_file_append_reads_max_block_and_session(tmp_path):
    p = tmp_path / "sess.tsv"
    data = dict.fromkeys(TSV_COLUMNS, "")
    data[BLOCK_ID_COLUMN] = "5"
    data["session_ID"] = "2"
    data["date"] = "2024-01-01"
    data["time"] = "12:00:00"
    data["timezone"] = "UTC +0000"
    data["is_initial"] = "0"
    with open(p, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(TSV_COLUMNS), delimiter="\t")
        w.writeheader()
        w.writerow(data)

    sd = SessionData()
    sd.open_file_append(str(p))
    try:
        assert sd.block_id == 6
        assert sd.session_id == 3
    finally:
        sd.close_file()


def test_open_file_append_legacy_block_id_header(tmp_path):
    p = tmp_path / "legacy.tsv"
    fieldnames = [c if c != "block_ID" else "block_id" for c in TSV_COLUMNS]
    data = dict.fromkeys(fieldnames, "")
    data["block_id"] = "3"
    data["session_ID"] = "1"
    data["date"] = "2024-01-01"
    data["time"] = "12:00:00"
    data["timezone"] = "UTC +0000"
    data["is_initial"] = "0"
    with open(p, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, delimiter="\t")
        w.writeheader()
        w.writerow(data)

    sd = SessionData()
    sd.open_file_append(str(p))
    try:
        assert sd.block_id == 4
        assert sd.tsv_fieldnames is not None
        assert BLOCK_ID_COLUMN in sd.tsv_fieldnames
    finally:
        sd.close_file()


def test_open_file_append_malformed_rows_skipped(tmp_path, caplog):
    p = tmp_path / "bad.tsv"
    with open(p, "w", newline="", encoding="utf-8") as f:
        f.write("block_ID\tsession_ID\nnotnum\tx\n")
    sd = SessionData()
    sd.open_file_append(str(p))
    try:
        assert sd.is_file_open()
    finally:
        sd.close_file()


def test_open_file_append_start_block_id_override(tmp_path):
    p = tmp_path / "x.tsv"
    sd = SessionData()
    sd.open_file(str(p))
    sd.close_file()
    sd.open_file_append(str(p), start_block_id=99)
    try:
        assert sd.block_id == 99
    finally:
        sd.close_file()


def test_write_clinical_without_open_raises():
    sd = SessionData()
    with pytest.raises(ValueError, match="not opened"):
        sd.write_clinical_scales([], _stim())


def test_write_session_empty_scale_values_writes_null_row(tmp_path):
    p = tmp_path / "w.tsv"
    sd = SessionData()
    sd.open_file(str(p))
    try:
        sd.write_session_scales([], _stim())
        assert sd.block_id == 1
    finally:
        sd.close_file()


def test_initialize_simple_file_and_write(tmp_path):
    p = tmp_path / "ann.tsv"
    sd = SessionData()
    sd.initialize_simple_file(str(p))
    try:
        sd.write_simple_annotation("hello")
    finally:
        sd.close_file()
    text = p.read_text(encoding="utf-8")
    assert "annotation" in text
    assert "hello" in text


def test_initialize_simple_when_open_raises(tmp_path):
    p = tmp_path / "a.tsv"
    sd = SessionData()
    sd.open_file(str(p))
    with pytest.raises(ValueError, match="already open"):
        sd.initialize_simple_file(str(tmp_path / "b.tsv"))
    sd.close_file()


def test_open_simple_file_append_new_file(tmp_path):
    p = tmp_path / "s.tsv"
    sd = SessionData()
    sd.open_simple_file_append(str(p))
    try:
        assert sd.is_file_open()
    finally:
        sd.close_file()
    assert "annotation" in p.read_text(encoding="utf-8")


def test_write_simple_annotation_requires_open():
    sd = SessionData()
    with pytest.raises(ValueError, match="No file is open"):
        sd.write_simple_annotation("x")


def test_open_simple_when_already_open_raises(tmp_path):
    p1 = tmp_path / "1.tsv"
    p2 = tmp_path / "2.tsv"
    sd = SessionData()
    sd.initialize_simple_file(str(p1))
    with pytest.raises(ValueError, match="already open"):
        sd.open_simple_file_append(str(p2))
    sd.close_file()
