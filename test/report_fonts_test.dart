/// The report font path must degrade, never explode, and must never draw
/// nothing where a character was.
library;

import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:dbs_annotator/report/report_fonts.dart';
import 'package:dbs_annotator/report/report_text.dart';
import 'package:dbs_annotator/report/session_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A note whose characters neither Helvetica nor IBM Plex Sans can draw.
  const rows = [
    SessionRow(
      blockId: '1',
      isInitial: '0',
      acqTime: '2026-01-01T09:00:00',
      scaleName: 'Tremor',
      scaleValue: '3',
      notes: '中文 note',
    ),
  ];

  test('a PDF is always produced, with or without the Unicode fonts', () async {
    // Holds in both states: whether assets/fonts ships the IBM Plex TTFs is a
    // deployment choice. `pw.Font.ttf` parses lazily, so a .ttf that is not a
    // font (an HTML error page from a dead raw URL) returned a non-null theme,
    // switched the sanitiser off, then threw mid-document instead of falling
    // back to Helvetica.
    final report = await buildSessionPdf(
      data: buildSessionReportData(rows: rows),
      subjectId: '01',
    );
    expect(report.bytes, isNotEmpty);
    expect(report.bytes.sublist(0, 4), '%PDF'.codeUnits);

    // A font that loads but cannot draw a rune must still report the loss,
    // or a CJK note is drawn as nothing at all with no warning.
    expect(
      report.lostCharacters,
      isTrue,
      reason: 'neither font can draw CJK, so the loss must be reported',
    );
  });

  test('the bundled font covers Latin, and reports what it does not', () async {
    final fonts = await loadReportFonts();
    if (fonts.theme == null) return; // a checkout without the TTFs

    expect(fonts.coverage, contains('A'.codeUnitAt(0)));
    expect(fonts.coverage, contains(0x00b5)); // µ, the pulse-width unit
    expect(fonts.coverage, contains(0x2019)); // a curly apostrophe
    expect(fonts.coverage, isNot(contains(0x4e2d))); // 中

    // The substitution table still applies (normalising a curly apostrophe is
    // faithful, not a loss), but what falls outside the font is now reported.
    final t = ReportTextSanitiser(coverage: fonts.coverage);
    expect(t('curly ’ quote'), "curly ' quote");
    expect(t.lostCharacters, isFalse);

    expect(t('cjk 中文'), 'cjk ??');
    expect(t.lostCharacters, isTrue);
  });

  test('with no font loaded, it maps what it can and flags a true loss', () {
    // A faithful substitution is not a loss; a `?` is. Warn always and the
    // warning is ignored; warn never and a clinical note is corrupted.
    for (final (input, output) in const [
      ('curly ’ quote', "curly ' quote"),
      ('em — dash', 'em - dash'),
      ('at ≥ least', 'at >= least'),
      ('micro µs', 'micro µs'),
      ('greek μ', 'greek µ'),
    ]) {
      final t = ReportTextSanitiser();
      expect(t(input), output);
      expect(t.lostCharacters, isFalse, reason: input);
    }

    final t = ReportTextSanitiser();
    expect(t('cjk 中文'), 'cjk ??');
    expect(t.lostCharacters, isTrue);
  });

  test('coverage decides what is lost, not what is substituted', () {
    // In coverage and not in the substitution table: drawn as itself, and not
    // counted as lost. One boolean cannot express that distinction.
    final t = ReportTextSanitiser(
      coverage: {for (var r = 0x20; r < 0x7f; r++) r, ...'中文'.runes},
    );
    expect(t('中文'), '中文');
    expect(t.lostCharacters, isFalse);

    expect(t('❤'), '?');
    expect(t.lostCharacters, isTrue);
  });
}
