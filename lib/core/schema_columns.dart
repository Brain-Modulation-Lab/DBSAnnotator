/// Canonical TSV column orders.
///
/// These lists and `schema/tsv_schema.json` describe the same contract, and
/// test/schema_parity_test.dart fails if they disagree — so a column added here
/// without updating the JSON (or the reverse) is caught rather than shipped.
/// The JSON is committed, not generated: edit `schema/*.json` and the bundled
/// copy under `assets/schema/` together.
///
/// ## Naming
///
/// All lower snake_case, which BIDS recommends for tabular column names. Files
/// written before v0.5.0 used `block_ID`, `session_ID` and `program_ID`;
/// [legacyColumnAliases] maps those so an older file still reads.
library;

/// Annotations-only TSV (`task-notes`).
const List<String> annotationColumns = <String>[
  'date',
  'time',
  'timezone',
  'acq_time',
  'notes',
];

/// Programming-session TSV (`task-programming`). Used by longitudinal review.
const List<String> sessionColumns = <String>[
  'date',
  'time',
  'timezone',
  'acq_time',
  'block_id',
  'session_id',
  'is_initial',
  'scale_name',
  'scale_value',
  'electrode_model',
  'program_id',
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

/// Pre-0.5.0 spellings, keyed by their current name.
///
/// Readers consult these so a file written by 0.4.x — or by the Qt desktop app,
/// which wrote the same headers — opens without a conversion step. Nothing
/// writes them.
const Map<String, String> legacyColumnAliases = <String, String>{
  'block_id': 'block_ID',
  'session_id': 'session_ID',
  'program_id': 'program_ID',
};

/// Read [column] from a TSV record, falling back to its pre-0.5.0 spelling.
String readColumn(Map<String, String> record, String column) =>
    record[column] ?? record[legacyColumnAliases[column] ?? column] ?? '';
