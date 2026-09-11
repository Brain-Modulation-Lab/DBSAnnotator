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
/// All lower snake_case, which BIDS recommends for tabular column names.
/// [legacyColumnAliases] maps every superseded spelling so an older file still
/// reads.
///
/// ## What v0.5.0 removed, and why
///
/// Earlier drafts carried `date`, `time` and `timezone` beside `acq_time` — four
/// cells for one instant. They are no longer written: four cells can disagree
/// and nothing asserted they agreed, `timezone`'s zone-name half was not
/// reproducible across platforms, and `acq_time` alone is what BIDS names and
/// what `pd.to_datetime` reads in one line. See `lib/core/timestamps.dart` for
/// the full argument, and `backfillAcqTime` for how older files still resolve to
/// an instant on read.
///
/// `session_id` was also renamed to `append_id`. It counts data-entry episodes
/// within one file — it increments each time that file is reopened to add rows —
/// and is file-scoped, so equal values in different files are unrelated. It was
/// never the BIDS session: BIDS uses `session_id` for the `ses-` label in
/// `sessions.tsv`, and keeping one name for both meanings would have misled
/// every reader of an aggregated table.
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

/// Superseded spellings, newest first, keyed by their current name.
///
/// Readers consult these so a file written by an earlier version — or by the Qt
/// desktop app, which wrote the `*_ID` forms — opens without a conversion step.
/// Nothing writes them.
///
/// A **list** per column, not a single string: `append_id` has two ancestors,
/// `session_id` from the 0.5.0 drafts and `session_ID` from 0.4.x and Qt, and
/// both are in the wild — the committed legacy fixture uses one and files
/// exported during 0.5.0 development use the other. Ordered newest-first so the
/// most likely spelling is tried first.
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
/// Guaranteed to be one of exactly those two strings, because the alternative
/// bites a reader immediately: `df.is_initial.astype(bool)` is **True** for the
/// string `"0.0"`, which silently moves the baseline row into the tested set and
/// changes every count derived from it. The Qt app and pre-0.5.0 files wrote
/// floats, so this normalises on read as well as on write.
String initialCell(bool isInitial) => isInitial ? '1' : '0';

/// Whether an `is_initial` cell means "baseline", tolerating `1`, `1.0`, ` 1 `.
bool isInitialValue(String cell) {
  final v = double.tryParse(cell.trim());
  return v != null && v.round() == 1;
}
