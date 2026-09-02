/// Canonical TSV column orders.
///
/// These lists and `schema/tsv_schema.json` describe the same contract, and
/// test/schema_parity_test.dart fails if they disagree — so a column added here
/// without updating the JSON (or the reverse) is caught rather than shipped.
/// The JSON is committed, not generated: edit `schema/*.json` and the bundled
/// copy under `assets/schema/` together.
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
