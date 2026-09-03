/// Programming-session TSV parsing, appending, and serialization.
///
/// Mirrors dbs_annotator/models/session_data.py:
/// - `buildInsertRows` = the row-shaping half of `write_session_scales`
///   (Step 3: one row per valid scale, or one scale-less row).
/// - `nextBlockId` / `nextSessionId` = the max-scan half of
///   `open_file_append`.
///
/// MOBILE PERSISTENCE NOTE: the desktop app keeps an open append handle
/// (csv.DictWriter on a file opened with mode "a") and writes each insert
/// incrementally. On the tablet there is no long-lived file handle: callers
/// read the whole TSV with [parseSessionTsv], append the rows from
/// [buildInsertRows] in memory, and rewrite the entire file with
/// [serializeSessionTsv] (writeTsvRecords over sessionColumns). The result
/// on disk is byte-compatible with what the desktop appender produces.
library;

import '../schema_columns.dart';
import '../timestamps.dart';
import '../tsv.dart';
import 'session_row.dart';

/// A (name, value) session-scale reading entered in Step 3.
typedef ScaleEntry = ({String name, String value});

/// Parse a programming-session TSV document into [SessionRow]s.
List<SessionRow> parseSessionTsv(String content) =>
    parseTsvRecords(content).map(SessionRow.fromMap).toList();

/// Serialize rows to a full TSV document with the canonical column header.
String serializeSessionTsv(List<SessionRow> rows) =>
    writeTsvRecords(sessionColumns, rows.map((r) => r.toMap()).toList());

/// Parse a TSV integer cell the way `int(float(val))` does in Python
/// (accepts "3" and "3.0", truncates toward zero); null when unparsable,
/// matching open_file_append's skip-malformed-row behavior.
int? _asInt(String raw) {
  final v = double.tryParse(raw.trim());
  if (v == null || !v.isFinite) return null;
  return v.truncate();
}

/// Next block ID for an append: max(block_id) + 1, or 0 for an empty/new
/// file. Mirrors open_file_append (max_block starts at -1; malformed cells
/// are skipped).
int nextBlockId(List<SessionRow> existing) {
  var maxBlock = -1;
  for (final row in existing) {
    final v = _asInt(row.blockId);
    if (v != null && v > maxBlock) maxBlock = v;
  }
  return maxBlock + 1;
}

/// Next session ID for an append: max(session_id) + 1, or 1 for an
/// empty/new file. Mirrors open_file_append (max_session starts at 0).
int nextSessionId(List<SessionRow> existing) {
  var maxSession = 0;
  for (final row in existing) {
    final v = _asInt(row.sessionId);
    if (v != null && v > maxSession) maxSession = v;
  }
  return maxSession + 1;
}

/// Build the NEW rows for one insert, mirroring write_session_scales
/// ([isInitial] false, the default: Step-3 recording, is_initial=0) or
/// write_clinical_scales ([isInitial] true: Step-1 baseline, is_initial=1).
/// The two Python writers produce identical row shapes apart from is_initial
/// and the scale filter: session scales keep any scale with a non-blank
/// value (SessionScale.has_value), clinical scales additionally require a
/// non-blank name (ClinicalScale.is_valid).
///
/// If no scale survives the filter, ONE row is written with empty
/// scale_name/scale_value; otherwise one row PER valid scale. Every row of
/// the insert shares the same block/session IDs, is_initial, timestamp,
/// stimulation columns, [programId] (the desktop's `group`),
/// [electrodeModel], and [notes].
///
/// The caller advances the block ID itself for the next insert (the desktop
/// increments `self.block_id` after each write); recompute with
/// [nextBlockId] after appending.
List<SessionRow> buildInsertRows({
  required int blockId,
  required int sessionId,
  bool isInitial = false,
  List<ScaleEntry> scales = const [],
  String programId = '',
  String electrodeModel = '',
  String notes = '',
  String leftStimFreq = '',
  String leftAnode = '',
  String leftCathode = '',
  String leftAmplitude = '',
  String leftPulseWidth = '',
  String rightStimFreq = '',
  String rightAnode = '',
  String rightCathode = '',
  String rightAmplitude = '',
  String rightPulseWidth = '',
  DateTime? at,
}) {
  final dt = at ?? DateTime.now();
  final date = dateCell(dt);
  final time = timeCell(dt);
  final timezone = timezoneCell(dt);
  final acqTime = acqTimeCell(dt);

  SessionRow row({String scaleName = '', String scaleValue = ''}) => SessionRow(
        date: date,
        time: time,
        timezone: timezone,
        acqTime: acqTime,
        blockId: '$blockId',
        sessionId: '$sessionId',
        // 1 for Step-1 baseline (write_clinical_scales), 0 for Step-3
        // recording (write_session_scales).
        isInitial: isInitial ? '1' : '0',
        scaleName: scaleName,
        scaleValue: scaleValue,
        electrodeModel: electrodeModel,
        programId: programId,
        leftStimFreq: leftStimFreq,
        leftAnode: leftAnode,
        leftCathode: leftCathode,
        leftAmplitude: leftAmplitude,
        leftPulseWidth: leftPulseWidth,
        rightStimFreq: rightStimFreq,
        rightAnode: rightAnode,
        rightCathode: rightCathode,
        rightAmplitude: rightAmplitude,
        rightPulseWidth: rightPulseWidth,
        notes: notes,
      );

  final valid = scales
      .where((s) =>
          s.value.trim().isNotEmpty && (!isInitial || s.name.trim().isNotEmpty))
      .toList();
  if (valid.isEmpty) return [row()];
  return [
    for (final s in valid) row(scaleName: s.name, scaleValue: s.value),
  ];
}
