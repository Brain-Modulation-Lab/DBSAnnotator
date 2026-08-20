/// Pure (Flutter-free) controller for the Complete-Workflow authoring
/// screen. Mirrors the desktop `SessionData` counters: `open_file_append`
/// sets block/session numbering from the existing file, and every write
/// increments the block counter (`self.block_id += 1`).
library;

import 'session_file.dart';
import 'session_row.dart';

/// Holds the working rows of one programming-session TSV plus the desktop's
/// block/session counters. Callers append inserts with [addInsert] and get
/// the full byte-compatible document back from [serialize].
class SessionAuthoring {
  /// All rows of the working file (existing + newly inserted), oldest first.
  final List<SessionRow> rows = [];

  int _blockId = 0;
  int _sessionId = 1;

  /// Block ID the NEXT insert will use.
  int get blockId => _blockId;

  /// Session ID every insert of this app session uses.
  int get sessionId => _sessionId;

  /// Load an existing TSV and continue numbering, mirroring
  /// open_file_append: next block = max(block_ID)+1, this session =
  /// max(session_ID)+1 (malformed cells are skipped).
  void loadExisting(String tsv) {
    rows
      ..clear()
      ..addAll(parseSessionTsv(tsv));
    _blockId = nextBlockId(rows);
    _sessionId = nextSessionId(rows);
  }

  /// Append one insert (one block). [stim] carries the 10 stimulation
  /// columns keyed by their exact TSV column names (missing keys become
  /// empty cells). [isInitial] true mirrors write_clinical_scales (Step-1
  /// baseline, is_initial=1); false mirrors write_session_scales (Step-3
  /// recording, is_initial=0). Returns the rows that were appended.
  List<SessionRow> addInsert({
    required bool isInitial,
    required Map<String, String> stim,
    List<ScaleEntry> scales = const [],
    String programId = '',
    String electrodeModel = '',
    String notes = '',
    DateTime? at,
  }) {
    final inserted = buildInsertRows(
      blockId: _blockId,
      sessionId: _sessionId,
      isInitial: isInitial,
      scales: scales,
      programId: programId,
      electrodeModel: electrodeModel,
      notes: notes,
      leftStimFreq: stim['left_stim_freq'] ?? '',
      leftAnode: stim['left_anode'] ?? '',
      leftCathode: stim['left_cathode'] ?? '',
      leftAmplitude: stim['left_amplitude'] ?? '',
      leftPulseWidth: stim['left_pulse_width'] ?? '',
      rightStimFreq: stim['right_stim_freq'] ?? '',
      rightAnode: stim['right_anode'] ?? '',
      rightCathode: stim['right_cathode'] ?? '',
      rightAmplitude: stim['right_amplitude'] ?? '',
      rightPulseWidth: stim['right_pulse_width'] ?? '',
      at: at,
    );
    rows.addAll(inserted);
    _blockId += 1; // Desktop: self.block_id += 1 after each write.
    return inserted;
  }

  /// Full TSV document (canonical 21-column header, \r\n line endings).
  String serialize() => serializeSessionTsv(rows);
}
