/// The notes report — the thing the home card has always promised.
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dbs_annotator/core/annotation.dart';
import 'package:dbs_annotator/report/annotations_report.dart';
import 'package:flutter_test/flutter_test.dart';

String _part(List<int> bytes, String name) => utf8.decode(ZipDecoder()
    .decodeBytes(bytes)
    .files
    .firstWhere((f) => f.name == name)
    .content);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const entries = [
    // Deliberately out of order: the UI lists newest first, and a report has to
    // read back in the order the session happened.
    Annotation(
        date: '2026-06-26',
        time: '10:40:00',
        timezone: 'W. Europe Daylight Time +0200',
        notes: 'second note'),
    Annotation(
        date: '2026-06-26',
        time: '09:15:00',
        timezone: 'W. Europe Daylight Time +0200',
        notes: 'first note'),
  ];

  AnnotationsReportData build([List<Annotation> e = entries]) =>
      buildAnnotationsReportData(
          entries: e,
          subjectId: '01',
          generatedAt: DateTime(2026, 8, 1),
          sourceFile: 'sub-01_ses-20260626_task-notes_run-01_events.tsv');

  test('entries are ordered oldest first, whatever order they arrive in', () {
    expect(build().entries.map((e) => e.notes), ['first note', 'second note']);
  });

  test('the session date comes from the notes, not the export clock', () {
    final data = build();
    expect(data.sessionDate, '2026-06-26');
    expect(data.generatedOn, '2026-08-01');
    expect(data.utcOffset, '+02:00');
    expect(data.sessionStamp, '2026-06-26 (UTC+02:00)');
    expect(data.span, '1h 25min');
  });

  test('no entries yields a valid report rather than an exception', () async {
    final data = build(const []);
    expect(data.entries, isEmpty);
    expect(data.span, isEmpty);
    final pdf = await buildAnnotationsPdf(data);
    expect(pdf.bytes.sublist(0, 4), '%PDF'.codeUnits);
    expect(_part(buildAnnotationsDocx(data), 'word/document.xml'),
        contains('No notes recorded.'));
  });

  test('the PDF carries the notes and its document properties', () async {
    final report = await buildAnnotationsPdf(build());
    expect(report.bytes.sublist(0, 4), '%PDF'.codeUnits);
    expect(report.bytes.length, greaterThan(1000));
    // /Info, so the file is not anonymous in a document system.
    expect(String.fromCharCodes(report.bytes), contains('/Title'));
  });

  test('the docx is a complete package Word will open', () {
    final bytes = buildAnnotationsDocx(build());
    final names =
        ZipDecoder().decodeBytes(bytes).files.map((f) => f.name).toList();
    // The same packaging as the session report, because it IS the same code.
    expect(
        names,
        containsAll(<String>[
          '[Content_Types].xml',
          '_rels/.rels',
          'word/document.xml',
          'word/footer1.xml',
          'word/styles.xml',
          'docProps/core.xml',
          'word/_rels/document.xml.rels',
        ]));

    final doc = _part(bytes, 'word/document.xml');
    expect(doc, contains('Session notes'));
    expect(doc, contains('first note'));
    expect(doc, contains('second note'));
    expect(doc, contains('2026-06-26 (UTC+02:00)'));
    expect(doc, contains('Attestation'));
    // Real heading styles, so Word's navigation pane is populated.
    expect(doc, contains('w:pStyle w:val="Heading1"'));

    final core = _part(bytes, 'docProps/core.xml');
    expect(core, contains('DBS session notes - sub-01'));
  });

  test('notes with XML metacharacters are escaped, not corrupting', () {
    final bytes = buildAnnotationsDocx(build(const [
      Annotation(
          date: '2026-06-26',
          time: '09:00:00',
          timezone: '+0200',
          notes: 'paraesthesia & tingling <30 s'),
    ]));
    final doc = _part(bytes, 'word/document.xml');
    expect(doc, contains('paraesthesia &amp; tingling &lt;30 s'));
  });
}
