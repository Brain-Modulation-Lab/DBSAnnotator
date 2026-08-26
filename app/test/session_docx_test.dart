import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/session_docx.dart';
import 'package:flutter_test/flutter_test.dart';

/// Read a part's UTF-8 text from the docx (zip) bytes.
String _part(List<int> bytes, String name) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final file = archive.files.firstWhere((f) => f.name == name);
  return utf8.decode(file.content);
}

void main() {
  const rows = [
    SessionRow(
      date: '2026-07-29',
      time: '09:00:00',
      blockId: '0',
      sessionId: '1',
      isInitial: '1',
      scaleName: 'UPDRS-III',
      scaleValue: '32',
      electrodeModel: 'SenSight B33005',
      leftAnode: 'C',
      leftCathode: '1',
      rightAnode: 'C',
      rightCathode: '9',
      notes: 'Baseline assessment before titration',
    ),
    SessionRow(
      date: '2026-07-29',
      time: '09:30:00',
      blockId: '1',
      sessionId: '1',
      isInitial: '0',
      scaleName: 'Tremor',
      scaleValue: '2',
      electrodeModel: 'SenSight B33005',
      programId: 'A',
      leftStimFreq: '130',
      leftAnode: 'C',
      leftCathode: '1_2',
      leftAmplitude: '1.5_1',
      leftPulseWidth: '60 µs',
      rightStimFreq: '130',
      rightAnode: 'C',
      rightCathode: '9',
      rightAmplitude: '2',
      rightPulseWidth: '60',
      notes: 'Paresthesia & resolved <30 s', // exercises XML escaping
    ),
    // A second recording block, so the table has a block BOUNDARY (separator
    // rule) and two distinct scores to rank (best vs second-best shading).
    SessionRow(
      date: '2026-07-29',
      time: '10:15:00',
      blockId: '2',
      sessionId: '1',
      isInitial: '0',
      scaleName: 'Tremor',
      scaleValue: '5',
      electrodeModel: 'SenSight B33005',
      programId: 'B',
      leftStimFreq: '180',
      leftAnode: 'C',
      leftCathode: '2',
      leftAmplitude: '3',
      leftPulseWidth: '90',
      rightStimFreq: '180',
      rightAnode: 'C',
      rightCathode: '10',
      rightAmplitude: '3',
      rightPulseWidth: '90',
    ),
  ];

  test('buildSessionDocx returns a valid PK zip with the OOXML parts', () {
    final bytes = buildSessionDocx(
      rows: rows,
      subjectId: '01',
      generatedAt: DateTime(2026, 7, 29),
    );
    expect(bytes, isNotEmpty);
    // ZIP local-file-header magic: "PK\x03\x04".
    expect(bytes.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);

    final names = ZipDecoder().decodeBytes(bytes).files.map((f) => f.name);
    expect(names, containsAll(<String>[
      '[Content_Types].xml',
      '_rels/.rels',
      'word/document.xml',
    ]));
  });

  test('document.xml carries the report sections and escapes XML', () {
    final bytes = buildSessionDocx(
      rows: rows,
      subjectId: '01',
      generatedAt: DateTime(2026, 7, 29),
    );
    final doc = _part(bytes, 'word/document.xml');

    // Section headings + data made it into the document.
    expect(doc, contains('Session report'));
    expect(doc, contains('Initial clinical notes'));
    expect(doc, contains('UPDRS-III'));
    expect(doc, contains('Session data'));
    expect(doc, contains('Programming summary'));
    // Split amplitude 1.5_1 sums to 2.5 mA in the summary.
    expect(doc, contains('2.5'));
    // The note's & and < are escaped, not raw.
    expect(doc, contains('Paresthesia &amp; resolved &lt;30 s'));
    expect(doc, isNot(contains('Paresthesia & resolved')));
  });

  test('empty rows still yield a valid docx', () {
    final bytes = buildSessionDocx(
      rows: const [],
      subjectId: 'unknown',
      generatedAt: DateTime(2026, 7, 29),
    );
    expect(bytes.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
    final doc = _part(bytes, 'word/document.xml');
    expect(doc, contains('No recording blocks in this session.'));
  });

  group('embedded graphics (OOXML drawing parts)', () {
    // A 2x1 red PNG, so pngSize can read a real IHDR.
    final tinyPng = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEklEQVR4AWP8z8'
        'Dwn4GBgYEBAA1TAv0Q2FSJAAAAAElFTkSuQmCC');

    Uint8List build() => buildSessionDocx(
          rows: rows,
          subjectId: '01',
          generatedAt: DateTime(2026, 7, 29),
          chartPng: tinyPng,
          electrodeImages: (
            initLeft: tinyPng,
            initRight: tinyPng,
            finalLeft: tinyPng,
            finalRight: tinyPng,
          ),
        );

    test('adds media parts, a rels part and a png content type', () {
      final bytes = build();
      final names =
          ZipDecoder().decodeBytes(bytes).files.map((f) => f.name).toList();
      expect(names, contains('word/_rels/document.xml.rels'));
      // Chart + 4 leads = 5 images.
      final media = names.where((n) => n.startsWith('word/media/')).toList();
      expect(media, hasLength(5));
      expect(_part(bytes, '[Content_Types].xml'),
          contains('Extension="png" ContentType="image/png"'));
    });

    test('every drawing relationship resolves to a media part that exists', () {
      final bytes = build();
      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toSet();
      final rels = _part(bytes, 'word/_rels/document.xml.rels');
      final doc = _part(bytes, 'word/document.xml');

      final relIds = RegExp(r'Id="(rId\d+)"\s+Type="[^"]*/image"\s+Target="([^"]+)"')
          .allMatches(rels);
      expect(relIds, isNotEmpty);
      for (final m in relIds) {
        // Target must exist in the package...
        expect(names, contains('word/${m.group(2)}'),
            reason: 'dangling relationship target');
        // ...and be referenced by a blip in the body.
        expect(doc, contains('r:embed="${m.group(1)}"'),
            reason: 'unused image relationship');
      }
      // Conversely, every blip must have a relationship.
      for (final m in RegExp(r'r:embed="(rId\d+)"').allMatches(doc)) {
        expect(rels, contains('Id="${m.group(1)}"'),
            reason: 'blip references a missing relationship');
      }
    });

    test('declares the drawing namespaces and non-zero extents', () {
      final doc = _part(build(), 'word/document.xml');
      for (final ns in ['xmlns:r=', 'xmlns:wp=', 'xmlns:a=', 'xmlns:pic=']) {
        expect(doc, contains(ns));
      }
      expect(doc, contains('<w:drawing>'));
      // wp:extent and a:ext must agree and be non-zero, or Word offers to repair.
      final extents = RegExp(r'<wp:extent cx="(\d+)" cy="(\d+)"/>')
          .allMatches(doc)
          .toList();
      expect(extents, hasLength(5));
      for (final m in extents) {
        expect(int.parse(m.group(1)!), greaterThan(0));
        expect(int.parse(m.group(2)!), greaterThan(0));
        expect(doc, contains('<a:ext cx="${m.group(1)}" cy="${m.group(2)}"/>'));
      }
    });

    test('shades the best and second-best blocks, and rules block starts', () {
      final doc = _part(build(), 'word/document.xml');
      // Tremor is minimised by default, so block 1 (value 2) beats block 2 (5).
      expect(doc, contains('w:fill="96D2A0"'), reason: 'best-block shading');
      expect(doc, contains('w:fill="C8EBCD"'), reason: 'second-best shading');
      expect(doc, contains('w:sz="24"'), reason: '3pt block separator rule');
      expect(doc, contains('Optimal configuration'));
      expect(doc, contains('Scale targets: Tremor: min'));
      expect(doc, contains('does not constitute'), reason: 'disclaimer');
    });

    test('emits a page size and margins', () {
      final a4 = _part(build(), 'word/document.xml');
      expect(a4, contains('<w:pgSz w:w="11906" w:h="16838"/>'));
      expect(a4, contains('w:left="720"'));
      final letter = _part(
        buildSessionDocx(
            rows: rows, subjectId: '01', pageSize: DocxPageSize.letter),
        'word/document.xml',
      );
      expect(letter, contains('<w:pgSz w:w="12240" w:h="15840"/>'));
    });

    test('without images there is no rels part and no drawing', () {
      final bytes =
          buildSessionDocx(rows: rows, subjectId: '01');
      final names =
          ZipDecoder().decodeBytes(bytes).files.map((f) => f.name).toList();
      expect(names, isNot(contains('word/_rels/document.xml.rels')));
      expect(names.where((n) => n.startsWith('word/media/')), isEmpty);
      expect(_part(bytes, 'word/document.xml'), isNot(contains('<w:drawing>')));
    });
  });

  test('pngSize reads the IHDR, and rejects non-PNG bytes', () {
    final tiny = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEklEQVR4AWP8z8'
        'Dwn4GBgYEBAA1TAv0Q2FSJAAAAAElFTkSuQmCC');
    expect(pngSize(tiny), (2, 1));
    expect(pngSize(Uint8List.fromList([1, 2, 3])), isNull);
    expect(pngSize(Uint8List.fromList(List.filled(40, 0))), isNull);
  });
}
