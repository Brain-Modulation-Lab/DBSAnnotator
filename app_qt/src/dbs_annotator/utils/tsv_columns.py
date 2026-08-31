"""Canonical TSV column names and legacy alias handling."""

from __future__ import annotations

from typing import Any

import pandas as pd

BLOCK_ID_COLUMN = "block_ID"
BLOCK_ID_LEGACY_KEYS = ("block_id", "blockId", "blockID")


def block_id_from_row(row: dict[str, Any]) -> Any:
    """Return the block index from a ``csv.DictReader`` row.

    Accepts legacy headers (``block_id``, ``blockId``, ``blockID``) and the
    canonical ``block_ID`` column name.
    """
    for key in (BLOCK_ID_COLUMN, *BLOCK_ID_LEGACY_KEYS):
        val = row.get(key)
        if val is not None and val != "":
            return val
    return None


def normalize_block_id_dataframe(df: pd.DataFrame | None) -> pd.DataFrame | None:
    """Rename legacy block-index columns to ``block_ID``."""
    if df is None or df.empty:
        return df

    if BLOCK_ID_COLUMN in df.columns:
        return df

    for candidate in BLOCK_ID_LEGACY_KEYS:
        if candidate in df.columns:
            return df.rename(columns={candidate: BLOCK_ID_COLUMN})

    return df


def read_session_tsv(path: str) -> pd.DataFrame:
    """Read a programming-session TSV and normalize column names."""
    df = pd.read_csv(path, sep="\t", na_filter=False)
    normalized = normalize_block_id_dataframe(df)
    return df if normalized is None else normalized


def canonicalize_row_block_id(row: dict[str, Any]) -> dict[str, Any]:
    """Ensure the row dict uses ``block_ID`` (drop legacy keys)."""
    out = dict(row)
    bid = block_id_from_row(row)
    if bid is not None:
        out[BLOCK_ID_COLUMN] = bid
    for key in BLOCK_ID_LEGACY_KEYS:
        out.pop(key, None)
    return out


def normalize_tsv_fieldnames(fieldnames: list[str] | None) -> list[str]:
    """Map legacy ``block_id`` header to ``block_ID`` (once per file)."""
    if not fieldnames:
        return []

    normalized: list[str] = []
    block_column_added = False
    for name in fieldnames:
        if name in (BLOCK_ID_COLUMN, *BLOCK_ID_LEGACY_KEYS):
            if not block_column_added:
                normalized.append(BLOCK_ID_COLUMN)
                block_column_added = True
            continue
        normalized.append(name)
    return normalized
