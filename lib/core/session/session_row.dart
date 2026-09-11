/// One row of a programming-session (`task-programming`) TSV.
library;

import '../schema_columns.dart';
import '../timestamps.dart';

/// One row of a programming-session (`task-programming`) TSV.
///
/// Mirrors the desktop writer in
/// dbs_annotator/models/session_data.py (write_clinical_scales /
/// write_session_scales). Every field is kept as the raw TSV string so a
/// parse -> serialize round trip is lossless (the desktop may write block
/// IDs as "3" or "3.0", amplitudes as split strings like "1.5_1", and
/// scale_name/scale_value cells with embedded newlines).
class SessionRow {
  const SessionRow({
    this.acqTime = '',
    this.blockId = '',
    this.appendId = '',
    this.isInitial = '',
    this.scaleName = '',
    this.scaleValue = '',
    this.electrodeModel = '',
    this.programId = '',
    this.leftStimFreq = '',
    this.leftAnode = '',
    this.leftCathode = '',
    this.leftAmplitude = '',
    this.leftPulseWidth = '',
    this.rightStimFreq = '',
    this.rightAnode = '',
    this.rightCathode = '',
    this.rightAmplitude = '',
    this.rightPulseWidth = '',
    this.notes = '',
  });

  /// The whole instant as one ISO-8601 string (`2026-02-03T09:00:00+00:00`).
  ///
  /// The only timestamp a row carries. For a file written before this became so,
  /// [SessionRow.fromMap] composes it from the retired `date` / `time` /
  /// `timezone` cells, so it is populated whatever wrote the source — see
  /// `backfillAcqTime`. Empty only when the source had nothing parseable.
  final String acqTime;
  final String blockId;

  /// Data-entry episode within one file: increments each time that file was
  /// reopened to add rows. **File-scoped** — `append_id` 1 in two different
  /// files are unrelated. Was called `session_id`, which BIDS uses for the
  /// `ses-` label; see `schema_columns.dart`.
  final String appendId;
  final String isInitial;
  final String scaleName;
  final String scaleValue;
  final String electrodeModel;
  final String programId;
  final String leftStimFreq;
  final String leftAnode;
  final String leftCathode;
  final String leftAmplitude;
  final String leftPulseWidth;
  final String rightStimFreq;
  final String rightAnode;
  final String rightCathode;
  final String rightAmplitude;
  final String rightPulseWidth;
  final String notes;

  /// Build from a TSV record keyed by the column names in
  /// schema_columns.dart `sessionColumns`. Missing columns become ''.
  ///
  /// Goes through [readColumn], so every superseded spelling is read as well as
  /// the current one — `block_ID`, `program_ID`, and both ancestors of
  /// `append_id`. An older file opens with no conversion step.
  ///
  /// **This is where a legacy row gains its instant.** A file written before
  /// `acq_time` became the only timestamp has `date` / `time` / `timezone`
  /// instead, and [backfillAcqTime] composes them — offset included when the
  /// `timezone` cell carried one. Doing it here, at the single parse boundary,
  /// means reports, the aggregate and every export see one populated column and
  /// none of them needs to know the source was older.
  factory SessionRow.fromMap(Map<String, String> m) => SessionRow(
    acqTime: _acqTimeOf(m),
    blockId: readColumn(m, 'block_id'),
    appendId: readColumn(m, 'append_id'),
    isInitial: readColumn(m, 'is_initial'),
    scaleName: readColumn(m, 'scale_name'),
    scaleValue: readColumn(m, 'scale_value'),
    electrodeModel: readColumn(m, 'electrode_model'),
    programId: readColumn(m, 'program_id'),
    leftStimFreq: readColumn(m, 'left_stim_freq'),
    leftAnode: readColumn(m, 'left_anode'),
    leftCathode: readColumn(m, 'left_cathode'),
    leftAmplitude: readColumn(m, 'left_amplitude'),
    leftPulseWidth: readColumn(m, 'left_pulse_width'),
    rightStimFreq: readColumn(m, 'right_stim_freq'),
    rightAnode: readColumn(m, 'right_anode'),
    rightCathode: readColumn(m, 'right_cathode'),
    rightAmplitude: readColumn(m, 'right_amplitude'),
    rightPulseWidth: readColumn(m, 'right_pulse_width'),
    notes: readColumn(m, 'notes'),
  );

  /// The row's instant as a local [DateTime], or null when [acqTime] is empty
  /// or unparsable.
  ///
  /// An externally-authored TSV can carry anything, hence the nullable result —
  /// callers skip rows they cannot place in time rather than guessing.
  /// `.toLocal()` so results from files recorded in different offsets are
  /// directly comparable.
  ///
  /// This is now a one-line read because [SessionRow.fromMap] already resolved
  /// the legacy two-cell form; the fallback that used to live here moved to the
  /// parse boundary, where it runs once instead of on every access.
  DateTime? get timestamp {
    final parsed = DateTime.tryParse(acqTime.trim());
    return parsed?.toLocal();
  }

  /// [acqTime] as written, or composed from the retired `date` / `time` /
  /// `timezone` cells when the source predates it.
  static String _acqTimeOf(Map<String, String> m) {
    final iso = readColumn(m, 'acq_time').trim();
    if (iso.isNotEmpty) return iso;
    return backfillAcqTime(
      date: readColumn(m, 'date'),
      time: readColumn(m, 'time'),
      timezone: readColumn(m, 'timezone'),
    );
  }

  /// Convert to a TSV record keyed by the exact column names.
  Map<String, String> toMap() => {
    'acq_time': acqTime,
    'block_id': blockId,
    'append_id': appendId,
    'is_initial': isInitial,
    'scale_name': scaleName,
    'scale_value': scaleValue,
    'electrode_model': electrodeModel,
    'program_id': programId,
    'left_stim_freq': leftStimFreq,
    'left_anode': leftAnode,
    'left_cathode': leftCathode,
    'left_amplitude': leftAmplitude,
    'left_pulse_width': leftPulseWidth,
    'right_stim_freq': rightStimFreq,
    'right_anode': rightAnode,
    'right_cathode': rightCathode,
    'right_amplitude': rightAmplitude,
    'right_pulse_width': rightPulseWidth,
    'notes': notes,
  };
}

/// The electrode model named by [rows], or '' when none of them say.
///
/// `electrode_model` is a TSV column and `ElectrodeCatalog.models` is keyed by
/// exactly that name, but nothing used to read it back: opening a file rendered
/// the lead diagrams for whatever the model dropdown happened to hold. A
/// mismatch there is not cosmetic — it labels one lead's contacts with
/// another lead's geometry.
String electrodeModelIn(Iterable<SessionRow> rows) {
  for (final row in rows) {
    final name = row.electrodeModel.trim();
    if (name.isNotEmpty) return name;
  }
  return '';
}
