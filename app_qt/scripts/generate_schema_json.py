"""Export this (frozen) app's domain contract to ``app_qt/schema/*.json``.

**Ownership changed when the Qt app was frozen.** The Flutter app at the repo
root now owns the live contract in the repo-root ``schema/``: it is the
implementation that will keep evolving, so it must not need this app -- or a
Python environment -- to add a column.

What this script does now is emit *this* app's own snapshot into
``app_qt/schema/``, and ``--check`` is the drift guard in both directions:

1. the snapshot still matches what this app's Python constants produce, and
2. the snapshot still matches the live root ``schema/``.

So the day the Flutter side changes the format, (2) fails and says so, rather
than the two implementations diverging in silence. That is the whole point of
keeping the frozen app around: it is the second implementation that makes the
interchange format falsifiable.

Run ``uv run --directory app_qt python scripts/generate_schema_json.py``;
add ``--check`` to verify without writing (used by pre-commit and CI).

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

# This app's own snapshot, resolved from the script rather than the CWD so the
# output never depends on where it was invoked from.
_PROJECT_ROOT = Path(__file__).resolve().parents[1]
SCHEMA_DIR = _PROJECT_ROOT / "schema"

# The live contract, owned by the Flutter app at the repo root. Read-only here:
# a frozen app must never write to the app that succeeded it.
LIVE_SCHEMA_DIR = _PROJECT_ROOT.parent / "schema"


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
        failed = False

        # (1) This app's snapshot still matches its own Python constants.
        for name, obj in contract.items():
            path = SCHEMA_DIR / name
            if not path.exists():
                print(f"[schema-json] Missing snapshot: {path}")
                failed = True
                continue
            if path.read_text(encoding="utf-8") != _render(obj):
                print(
                    f"[schema-json] {path} is out of date. Run "
                    "`uv run --directory app_qt python "
                    "scripts/generate_schema_json.py`."
                )
                failed = True

        # (2) The snapshot still matches the LIVE contract the Flutter app owns.
        #
        # This is the interop check, and the reason the frozen app is worth
        # keeping: it is a second, independent implementation of the same TSV
        # format, so a divergence is detectable instead of theoretical. A
        # mismatch is NOT automatically an error -- the live app is allowed to
        # move ahead of the frozen one -- but it must never happen unnoticed.
        for name, obj in contract.items():
            live = LIVE_SCHEMA_DIR / name
            if not live.exists():
                print(f"[schema-json] Live contract missing: {live}")
                failed = True
                continue
            if live.read_text(encoding="utf-8") != _render(obj):
                print(
                    f"[schema-json] DIVERGED: {live} no longer matches the "
                    "frozen Qt app's contract. If the Flutter app changed the "
                    "format deliberately, refresh this snapshot; if not, this "
                    "is a real incompatibility between the two apps."
                )
                failed = True

        if failed:
            return 1
        print(
            "[schema-json] snapshot matches this app's constants AND the live contract."
        )
        return 0

    SCHEMA_DIR.mkdir(parents=True, exist_ok=True)
    for name, obj in contract.items():
        (SCHEMA_DIR / name).write_text(_render(obj), encoding="utf-8")
        print(f"[schema-json] Wrote {SCHEMA_DIR / name}")
    print(
        "[schema-json] Wrote this app's snapshot only. The live contract at "
        f"{LIVE_SCHEMA_DIR} is owned by the Flutter app and was not touched."
    )
    return 0


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Export schema/*.json contract.")
    parser.add_argument(
        "--check", action="store_true", help="Fail if committed JSON is stale."
    )
    args = parser.parse_args()
    raise SystemExit(main(check=args.check))
