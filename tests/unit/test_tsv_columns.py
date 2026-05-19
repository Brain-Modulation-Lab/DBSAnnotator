"""Tests for TSV block_ID column compatibility helpers."""

from __future__ import annotations

import pandas as pd

from dbs_annotator.utils.tsv_columns import (
    BLOCK_ID_COLUMN,
    block_id_from_row,
    canonicalize_row_block_id,
    normalize_block_id_dataframe,
    normalize_tsv_fieldnames,
    read_session_tsv,
)


def test_block_id_from_row_canonical_and_legacy():
    assert block_id_from_row({"block_ID": "3"}) == "3"
    assert block_id_from_row({"block_id": 2}) == 2
    assert block_id_from_row({"blockId": "1"}) == "1"
    assert block_id_from_row({"scale_name": "Tremor"}) is None


def test_normalize_block_id_dataframe():
    df = pd.DataFrame({"block_id": [1, 2], "x": [0, 1]})
    out = normalize_block_id_dataframe(df)
    assert out is not None
    assert list(out.columns) == ["block_ID", "x"]


def test_normalize_tsv_fieldnames():
    assert normalize_tsv_fieldnames(["date", "block_id", "session_ID"]) == [
        "date",
        "block_ID",
        "session_ID",
    ]
    assert normalize_tsv_fieldnames(["block_ID", "block_id"]) == ["block_ID"]


def test_canonicalize_row_block_id():
    row = canonicalize_row_block_id(
        {"date": "2025-01-01", "block_id": "5", "scale_name": "Tremor"}
    )
    assert row[BLOCK_ID_COLUMN] == "5"
    assert "block_id" not in row


def test_read_session_tsv(tmp_path):
    p = tmp_path / "sess.tsv"
    p.write_text(
        "date\ttime\tblock_id\tscale_name\tscale_value\n"
        "2025-01-01\t10:00:00\t0\tTremor\t6\n",
        encoding="utf-8",
    )
    df = read_session_tsv(str(p))
    assert "block_ID" in df.columns
    assert int(float(str(df.loc[0, "block_ID"]))) == 0
