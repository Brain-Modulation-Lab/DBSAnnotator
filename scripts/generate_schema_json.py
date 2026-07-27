"""Export the machine-readable domain contract to ``schema/*.json``.

The Qt desktop app is the single source of truth for the TSV schema, BIDS
filename format, scale presets, and validation limits. The Flutter tablet app's
``dbs_core`` package consumes these JSON files and asserts against them in tests,
so the two implementations cannot silently diverge.

Run ``uv run python scripts/generate_schema_json.py`` to regenerate; the same
command with ``--check`` fails if the committed JSON is stale (used in CI).

Column names/types/descriptions are reused from ``generate_tsv_schema_docs`` so
there is exactly one place that describes each column.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

# Reuse the column type/description metadata that already backs the Sphinx docs.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_tsv_schema_docs import (  # noqa: E402
    ANNOTATION_META,
    SESSION_META,
)

from dbs_annotator.config import (  # noqa: E402
    ANNOTATION_TSV_COLUMNS,
    APP_VERSION,
    CLINICAL_SCALES_PRESETS,
    PRESET_BUTTONS,
    SESSION_SCALE_LIMITS,
    SESSION_SCALES_PRESETS,
    STIMULATION_LIMITS,
    TSV_COLUMNS,
)

SCHEMA_DIR = Path("schema")

# BIDS filename format, mirroring the construction in the Qt app (e.g.
# views/annotation_only_view.py and views/step1_view.py):
#   sub-<subject>_ses-<session>_task-<task>_run-<run>_events.tsv
# `task` is "programming" for session files and "notes" for annotations-only.
BIDS = {
    "filename_template": "sub-{subject}_ses-{session}_task-{task}_run-{run}_events.tsv",
    "session_task": "programming",
    "annotation_task": "notes",
    "session_format": "%Y%m%d",
    "default_run": "01",
    # Regexes used to parse existing filenames (mirror the exporters' re.search).
    "entities": {
        "subject": r"sub-([^_]+)",
        "session": r"ses-([^_]+)",
        "task": r"task-([^_]+)",
        "run": r"run-([0-9]+)",
    },
}


def _columns(names: list[str], meta: dict[str, tuple[str, str]]) -> list[dict]:
    return [
        {"name": name, "type": meta[name][0], "description": meta[name][1]}
        for name in names
    ]


def build_contract() -> dict[str, dict]:
    """Return {relative_filename: json_object} for every contract file."""
    # Validate the metadata still covers every column (same guard as the docs).
    for cols, meta, label in (
        (TSV_COLUMNS, SESSION_META, "TSV_COLUMNS"),
        (ANNOTATION_TSV_COLUMNS, ANNOTATION_META, "ANNOTATION_TSV_COLUMNS"),
    ):
        if set(cols) != set(meta):
            missing = sorted(set(cols) - set(meta))
            extra = sorted(set(meta) - set(cols))
            raise ValueError(
                f"Metadata does not match {label}: missing={missing}, extra={extra}"
            )

    return {
        "tsv_schema.json": {
            "schema_version": APP_VERSION,
            "session_tsv": {"columns": _columns(TSV_COLUMNS, SESSION_META)},
            "annotation_tsv": {
                "columns": _columns(ANNOTATION_TSV_COLUMNS, ANNOTATION_META)
            },
            "bids": BIDS,
        },
        "scale_presets.json": {
            "schema_version": APP_VERSION,
            "buttons": PRESET_BUTTONS,
            "clinical": CLINICAL_SCALES_PRESETS,
            # tuples -> [name, min, max] arrays
            "session": {
                name: [list(item) for item in items]
                for name, items in SESSION_SCALES_PRESETS.items()
            },
        },
        "limits.json": {
            "schema_version": APP_VERSION,
            "stimulation": STIMULATION_LIMITS,
            "session_scale": SESSION_SCALE_LIMITS,
        },
    }


def _render(obj: dict) -> str:
    # Stable, diff-friendly output; trailing newline for POSIX-friendliness.
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def main(*, check: bool = False) -> int:
    contract = build_contract()
    if check:
        for name, obj in contract.items():
            path = SCHEMA_DIR / name
            if not path.exists():
                print(f"[schema-json] Missing generated file: {path}")
                return 1
            if path.read_text(encoding="utf-8") != _render(obj):
                print(
                    f"[schema-json] {path} is out of date. "
                    "Run `uv run python scripts/generate_schema_json.py`."
                )
                return 1
        print("[schema-json] schema/*.json are up to date.")
        return 0

    SCHEMA_DIR.mkdir(parents=True, exist_ok=True)
    for name, obj in contract.items():
        (SCHEMA_DIR / name).write_text(_render(obj), encoding="utf-8")
        print(f"[schema-json] Wrote {SCHEMA_DIR / name}")
    return 0


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Export schema/*.json contract.")
    parser.add_argument(
        "--check", action="store_true", help="Fail if committed JSON is stale."
    )
    args = parser.parse_args()
    raise SystemExit(main(check=args.check))
