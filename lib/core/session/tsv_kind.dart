/// What kind of TSV a file actually is, from its header row.
///
/// ## Why this has to exist
///
/// `SessionRow.fromMap` is **total**: every column it cannot find becomes `''`.
/// So handing it an annotations (`task-notes`) TSV does not fail — it silently
/// yields one all-empty row per line. The longitudinal screen imported such a
/// file and reported success, then showed a review with no data in it and no
/// explanation. A reader that cannot fail is a reader that needs a sniffer in
/// front of it.
///
/// The check is on the HEADER, not the filename: a BIDS `task-` entity is a
/// convention a user can rename, and the columns are the actual contract.
library;

import '../tsv.dart';

/// The kinds of TSV this app reads.
enum TsvKind {
  /// A programming session: blocks, stimulation, scales.
  programming,

  /// Timestamped free-text notes only.
  notes,

  /// A TSV whose header matches neither contract.
  unknown,

  /// Not parseable as a TSV at all (binary, empty, no header).
  unreadable,
}

/// Columns that only a programming TSV has. The block index and `is_initial`
/// are the structural ones — everything a session report does starts by
/// grouping on them — so their presence is what makes a file a session.
///
/// The block index is spelled `block_id` from v0.5.0 and `block_ID` before it,
/// so either satisfies the marker; a file that predates the rename must still
/// classify as a session.
const _blockMarkers = {'block_id', 'block_ID'};
const _programmingMarkers = {'is_initial'};

/// A notes file is `notes` plus a timestamp, in either era's spelling.
///
/// The timestamp is what distinguishes a notes TSV from any other one-column
/// text file, but which column carries it changed: v0.5.0 and later write only
/// `acq_time`, while 0.4.x and the Qt desktop wrote `date` + `time` (+ a
/// free-text `timezone`). Requiring one fixed set would misclassify one era or
/// the other — and misclassifying is not cosmetic here, because the notes
/// screen refuses to open anything it does not recognise.
const _notesRequired = {'notes'};
const _notesTimestampAlternatives = [
  {'acq_time'},
  {'date', 'time'},
];

/// Classify [content] by its header row.
///
/// A programming TSV also contains every annotation column, so the checks are
/// ordered: programming first, then the narrower notes shape.
TsvKind sniffTsvKind(String content) {
  final List<List<String>> rows;
  try {
    rows = parseTsv(content);
  } catch (_) {
    return TsvKind.unreadable;
  }
  // The header alone is the evidence, so a file with a header and no data rows
  // still classifies — that is a freshly created session, which is exactly the
  // state `New` leaves behind.
  if (rows.isEmpty || rows.first.isEmpty) return TsvKind.unreadable;
  final header = rows.first.map((c) => c.trim()).toSet();

  if (_programmingMarkers.every(header.contains) &&
      _blockMarkers.any(header.contains)) {
    return TsvKind.programming;
  }
  // `notes` plus a timestamp in either era's spelling — see the marker
  // declarations for why this cannot be one fixed set.
  if (_notesRequired.every(header.contains) &&
      _notesTimestampAlternatives.any((set) => set.every(header.contains))) {
    return TsvKind.notes;
  }
  return TsvKind.unknown;
}

/// A message naming what was found and what was expected, for the UI.
///
/// Phrased for a clinician, not a developer: the useful information is which
/// workflow the file belongs to.
String tsvKindMismatch(String filename, TsvKind found, TsvKind wanted) {
  String describe(TsvKind k) => switch (k) {
    TsvKind.programming => 'a programming session',
    TsvKind.notes => 'an annotations (notes) file',
    TsvKind.unknown => 'an unrecognised TSV',
    TsvKind.unreadable => 'not a readable TSV',
  };
  return '$filename is ${describe(found)}; this view needs '
      '${describe(wanted)}.';
}
