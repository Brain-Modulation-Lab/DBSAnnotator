/// Canonical TSV column orders, kept byte-for-byte in sync with the desktop
/// app (dbs_annotator/config.py) via schema/tsv_schema.json.
///
/// test/schema_parity_test.dart loads the generated JSON contract and fails if
/// these lists ever drift from the Python source of truth. Regenerate the JSON
/// with `uv run python scripts/generate_schema_json.py` when the schema changes.
library;

/// Annotations-only TSV (`task-notes`).
const List<String> annotationColumns = <String>[
  'date',
  'time',
  'timezone',
  'notes',
];

/// Programming-session TSV (`task-programming`). Used by longitudinal review.
const List<String> sessionColumns = <String>[
  'date',
  'time',
  'timezone',
  'block_ID',
  'session_ID',
  'is_initial',
  'scale_name',
  'scale_value',
  'electrode_model',
  'program_ID',
  'left_stim_freq',
  'left_anode',
  'left_cathode',
  'left_amplitude',
  'left_pulse_width',
  'right_stim_freq',
  'right_anode',
  'right_cathode',
  'right_amplitude',
  'right_pulse_width',
  'notes',
];
