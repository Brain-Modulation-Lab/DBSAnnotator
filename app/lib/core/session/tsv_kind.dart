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

import '../schema_columns.dart';
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

/// Columns that only a programming TSV has. `block_ID` and `is_initial` are the
/// structural ones — everything a session report does starts by grouping on
/// them — so their presence is what makes a file a session.
const _programmingMarkers = {'block_ID', 'is_initial'};

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

  if (_programmingMarkers.every(header.contains)) return TsvKind.programming;
  if (annotationColumns.every(header.contains)) return TsvKind.notes;
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
