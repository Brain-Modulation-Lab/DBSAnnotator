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

import dbs_annotator  # noqa: E402
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
from dbs_annotator.config_electrode_models import (  # noqa: E402
    ELECTRODE_MODELS,
    MANUFACTURERS,
)

# Mirrors dbs_annotator.models.clinical_scale.SESSION_SCALE_OMITTED_TSV. Inlined
# (not imported) because importing dbs_annotator.models pulls in Qt via its
# __init__; this sentinel is a stable literal.
SESSION_SCALE_OMITTED_TSV = "NaN"

SCHEMA_DIR = Path("schema")


def _stimulation_presets() -> dict:
    """Default freq/amplitude/pulse-width quick-pick lists.

    These are the bundled defaults the desktop's SettingPresetsManager ships
    (src/dbs_annotator/config/setting_presets.json); the tablet uses them as
    the stimulation quick-picks.
    """
    path = Path(dbs_annotator.__file__).parent / "config" / "setting_presets.json"
    return json.loads(path.read_text(encoding="utf-8"))


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


def _electrode_models() -> dict:
    """Serialize the electrode catalog for the Dart port + parity test.

    ``level_directional`` is precomputed per level so the Dart side can be
    verified directly without re-deriving the default middle-levels rule.
    """
    models = {}
    for name, m in ELECTRODE_MODELS.items():
        models[name] = {
            "name": m.name,
            "num_contacts": m.num_contacts,
            "contact_height": m.contact_height,
            "contact_spacing": m.contact_spacing,
            "lead_diameter": m.lead_diameter,
            "is_directional": m.is_directional,
            "tip_contact": m.tip_contact,
            "segments_per_level": m.segments_per_level,
            "directional_levels": m._directional_levels,
            "level_directional": [
                m.is_level_directional(i) for i in range(m.num_contacts)
            ],
        }
    return models


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
            "session_scale": {
                **SESSION_SCALE_LIMITS,
                "omitted_tsv": SESSION_SCALE_OMITTED_TSV,
            },
            "stimulation_presets": _stimulation_presets(),
        },
        "electrode_models.json": {
            "schema_version": APP_VERSION,
            "manufacturers": MANUFACTURERS,
            "models": _electrode_models(),
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
