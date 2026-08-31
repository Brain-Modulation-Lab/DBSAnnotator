/// The sniffer that stops a wrong-workflow file importing "successfully".
library;

import 'dart:io';

import 'package:dbs_annotator/core/annotation.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/tsv_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final programming =
      File('test/fixtures/sub-01_ses-20260626_task-programming_run-01_events.tsv')
          .readAsStringSync();

  test('the committed programming example is recognised', () {
    expect(sniffTsvKind(programming), TsvKind.programming);
  });

  test('a notes TSV is recognised, and is NOT a session', () {
    final notes = writeAnnotations(const [
      Annotation(
          date: '2026-06-26',
          time: '09:00:00',
          timezone: '+0200',
          notes: 'a note'),
    ]);
    expect(sniffTsvKind(notes), TsvKind.notes);

    // The bug this guards: SessionRow.fromMap is total, so the same content
    // parses as a session without complaint and yields empty rows.
    final asSession = parseSessionTsv(notes);
    expect(asSession, isNotEmpty, reason: 'it really does parse');
    expect(asSession.every((r) => r.blockId.isEmpty), isTrue,
        reason: 'into nothing usable, which is why the sniffer must run first');
  });

  test('a header with no data rows still classifies', () {
    // What `New` leaves on disk before the first insert.
    expect(sniffTsvKind(serializeSessionTsv(const [])), TsvKind.programming);
  });

  test('unrecognised and unreadable are distinguished', () {
    expect(sniffTsvKind('alpha\tbeta\n1\t2\n'), TsvKind.unknown);
    expect(sniffTsvKind(''), TsvKind.unreadable);
  });

  test('the message names both the file and the workflow', () {
    final msg = tsvKindMismatch('notes.tsv', TsvKind.notes, TsvKind.programming);
    expect(msg, contains('notes.tsv'));
    expect(msg, contains('annotations'));
    expect(msg, contains('programming session'));
  });
}
