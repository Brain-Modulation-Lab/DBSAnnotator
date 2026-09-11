/// Canonical TSV column orders.
///
/// These lists and `schema/tsv_schema.json` describe the same contract, and
/// test/schema_parity_test.dart fails if they disagree — so a column added here
/// without updating the JSON (or the reverse) is caught rather than shipped.
/// The JSON is committed, not generated: edit `schema/*.json` and the bundled
/// copy under `assets/schema/` together.
///
/// All lower snake_case, which BIDS recommends for tabular column names;
/// [legacyColumnAliases] maps every superseded spelling so an older file reads.
///
/// v0.5.0 removed `date`, `time` and `timezone` in favour of `acq_time` alone
/// (see `lib/core/timestamps.dart`) and renamed `session_id` to `append_id`,
/// because BIDS uses `session_id` for the `ses-` label while this column counts
/// data-entry episodes within one file.
library;

/// Annotations-only TSV (`task-notes`).
const List<String> annotationColumns = <String>['acq_time', 'notes'];

/// Programming-session TSV (`task-programming`). Used by longitudinal review.
const List<String> sessionColumns = <String>[
  'acq_time',
  'block_id',
  'append_id',
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

/// Superseded spellings, newest first, keyed by their current name. Readers
/// consult these so an older file opens without a conversion step; nothing
/// writes them.
///
/// A list per column because `append_id` has two ancestors - `session_id` from
/// the 0.5.0 drafts and `session_ID` from 0.4.x and Qt - and both exist in the
/// wild.
const Map<String, List<String>> legacyColumnAliases = <String, List<String>>{
  'block_id': <String>['block_ID'],
  'append_id': <String>['session_id', 'session_ID'],
  'program_id': <String>['program_ID'],
};

/// Read [column] from a TSV record, falling back to its superseded spellings.
String readColumn(Map<String, String> record, String column) {
  final current = record[column];
  if (current != null) return current;
  for (final alias in legacyColumnAliases[column] ?? const <String>[]) {
    final value = record[alias];
    if (value != null) return value;
  }
  return '';
}

/// `0` or `1` for the `is_initial` cell, whatever shape the source used.
///
/// Exactly those two strings, never `0.0`: `df.is_initial.astype(bool)` is True
/// for the string `"0.0"`, which silently moves the baseline row into the
/// tested set. Older files wrote floats, so this normalises both ways.
String initialCell(bool isInitial) => isInitial ? '1' : '0';

/// Whether an `is_initial` cell means "baseline", tolerating `1`, `1.0`, ` 1 `.
bool isInitialValue(String cell) {
  final v = double.tryParse(cell.trim());
  return v != null && v.round() == 1;
}
