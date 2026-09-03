/// The report font path must degrade, never explode — and must never draw
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
        date: '2026-01-01',
        time: '09:00:00',
        scaleName: 'Tremor',
        scaleValue: '3',
        notes: '中文 note'),
  ];

  test('a PDF is always produced, with or without the Unicode fonts', () async {
    // This must hold in BOTH states, because whether assets/fonts holds the IBM
    // Plex TTFs is a deployment choice: a fresh checkout of a fork may have
    // none.
    //
    // The bug this pins: `pw.Font.ttf` parses LAZILY, so a file named .ttf that
    // is not a font — most easily the 300 KB HTML error page GitHub serves for
    // a dead raw URL — used to sail through the loader, which returned a
    // non-null theme. That switched the sanitiser OFF and then threw
    // "Unable to find the hmtx table" halfway through building the document, so
    // every export failed instead of falling back to Helvetica.
    final report = await buildSessionPdf(
        data: buildSessionReportData(rows: rows), subjectId: '01');
    expect(report.bytes, isNotEmpty);
    expect(report.bytes.sublist(0, 4), '%PDF'.codeUnits);

    // CJK is outside Helvetica AND outside IBM Plex Sans, so it is reported as
    // lost either way. This is the case that regressed when the fonts were
    // bundled: the sanitiser used to switch off whenever any theme loaded, and
    // the note was then drawn as nothing at all, with no warning.
    expect(report.lostCharacters, isTrue,
        reason: 'neither font can draw CJK, so the loss must be reported');
  });

  test('the bundled font covers Latin, and reports what it does not', () async {
    final fonts = await loadReportFonts();
    if (fonts.theme == null) return; // a checkout without the TTFs

    // Coverage is a real cmap, not a guess.
    expect(fonts.coverage, contains('A'.codeUnitAt(0)));
    expect(fonts.coverage, contains(0x00b5)); // µ, the pulse-width unit
    expect(fonts.coverage, contains(0x2019)); // a curly apostrophe
    expect(fonts.coverage, isNot(contains(0x4e2d))); // 中

    // The substitution table still applies — it is faithful, and normalising a
    // curly apostrophe is not a loss — but what falls outside the font is now
    // reported rather than silently drawn as nothing.
    final t = ReportTextSanitiser(coverage: fonts.coverage);
    expect(t('curly ’ quote'), "curly ' quote");
    expect(t.lostCharacters, isFalse);

    expect(t('cjk 中文'), 'cjk ??');
    expect(t.lostCharacters, isTrue);
  });

  test('with no font loaded, it maps what it can and flags a true loss', () {
    // A faithful substitution is not a loss; a `?` is. Getting this wrong in
    // either direction is bad: warn always and the warning is ignored, warn
    // never and a clinical note is silently corrupted.
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
    // A character in the coverage set and not in the table is drawn as itself,
    // whatever it is — this is the case the old boolean could not express, and
    // the reason a CJK note used to vanish silently.
    final t = ReportTextSanitiser(coverage: {
      for (var r = 0x20; r < 0x7f; r++) r,
      ...'中文'.runes,
    });
    expect(t('中文'), '中文');
    expect(t.lostCharacters, isFalse);

    // Outside it, and outside the table: reported.
    expect(t('❤'), '?');
    expect(t.lostCharacters, isTrue);
  });
}
