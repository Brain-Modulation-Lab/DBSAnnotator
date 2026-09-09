/// The guard that stops the Annotations workflow destroying a programming
/// session TSV.
///
/// This is a pure-logic test of the guard's PREMISE, not a widget test: it
/// pins the two facts that made the bug possible, so that if either changes,
/// the reason `annotations_screen._open` must sniff the kind is still recorded.
///
/// The bug: `annotations_screen._open` was the only one of four file readers
/// with no `sniffTsvKind` check, and the only one that autosaves back to the
/// file it opened. A programming TSV parses as notes *successfully*, so the
/// screen reported a plausible note count, set `_savePath` to the clinician's
/// real file, and the first typed note atomically rewrote it with only the five
/// annotation columns - every block, stimulation parameter, amplitude, scale
/// rating and program gone, with no error and no `.tmp` to recover from.
library;

import 'dart:io';

import 'package:dbs_annotator/core/annotation.dart';
import 'package:dbs_annotator/core/schema_columns.dart';
import 'package:dbs_annotator/core/session/tsv_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final programming = File(
    'test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv',
  ).readAsStringSync();

  test('the sniffer is what distinguishes the two kinds', () {
    // The guard added to annotations_screen._open compares against this.
    expect(sniffTsvKind(programming), TsvKind.programming);
    expect(
      sniffTsvKind(writeAnnotations(parseAnnotations(programming))),
      TsvKind.notes,
    );
  });

  test('a programming TSV parses as notes WITHOUT error - the trap', () {
    // Precondition for the bug, and the reason a guard is required rather than
    // relying on a parse failure: `parseAnnotations` is total, and every
    // annotation column exists in a programming file.
    expect(
      annotationColumns.every(sessionColumns.contains),
      isTrue,
      reason:
          'annotationColumns must be a subset of sessionColumns for the '
          'silent-success trap to exist; if this ever stops being true, the '
          'guard is still correct but this test needs rewriting',
    );
    final asNotes = parseAnnotations(programming);
    expect(
      asNotes,
      isNotEmpty,
      reason:
          'it does not throw and does not come back empty - it comes back '
          'looking plausible, which is exactly why nothing caught it',
    );
  });

  test('round-tripping a programming file through the notes writer would '
      'destroy it', () {
    // What autosave used to do on the very first note. Asserted so the cost is
    // recorded next to the guard, not just described in a comment.
    final rewritten = writeAnnotations(parseAnnotations(programming));
    final lostColumns = sessionColumns.where(
      (c) => !annotationColumns.contains(c),
    );

    expect(lostColumns, isNotEmpty);
    for (final column in ['block_id', 'scale_name', 'scale_value']) {
      expect(
        sessionColumns.contains(column),
        isTrue,
        reason: 'guarding against a schema rename silently weakening this test',
      );
      expect(
        rewritten.split('\n').first.split('\t'),
        isNot(contains(column)),
        reason:
            '$column survives in the notes-only rewrite, so this test is '
            'no longer demonstrating the data loss it claims to',
      );
    }
  });
}
