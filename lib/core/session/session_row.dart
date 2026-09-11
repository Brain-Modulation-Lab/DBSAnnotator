/// One row of a programming-session (`task-programming`) TSV.
library;

import '../schema_columns.dart';
import '../timestamps.dart';

/// One row of a programming-session (`task-programming`) TSV.
///
/// Every field stays the raw TSV string so a parse/serialize round trip is
/// lossless: the desktop writes block IDs as "3" or "3.0", amplitudes as
/// split strings like "1.5_1", and scale cells with embedded newlines.
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

  /// The whole instant as one ISO-8601 string and the only timestamp a row
  /// carries; empty only when the source had nothing parseable.
  final String acqTime;
  final String blockId;

  /// Data-entry episode within one file, incremented each time that file is
  /// reopened: file-scoped, so equal values in two files are unrelated.
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

  /// Build from a TSV record keyed by `sessionColumns`; missing columns become
  /// ''. Reads through [readColumn], so superseded spellings open without a
  /// conversion step, and this is where a legacy row gains its instant: doing
  /// the [backfillAcqTime] composition at the single parse boundary means no
  /// report, aggregate or export has to know the source was older.
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
  /// or unparsable: an external TSV can carry anything, and callers skip rows
  /// they cannot place in time. `.toLocal()` makes rows recorded in different
  /// offsets comparable.
  DateTime? get timestamp {
    final parsed = DateTime.tryParse(acqTime.trim());
    return parsed?.toLocal();
  }

  /// [acqTime] as written, or composed from a legacy row's `date`/`time`.
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

/// The electrode model named by [rows], or '' when none of them say. The name
/// keys `ElectrodeCatalog.models`, and a file opened against the wrong model
/// labels one lead's contacts with another lead's geometry.
String electrodeModelIn(Iterable<SessionRow> rows) {
  for (final row in rows) {
    final name = row.electrodeModel.trim();
    if (name.isNotEmpty) return name;
  }
  return '';
}
