/// The report font path must degrade, never explode.
library;

import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:dbs_annotator/report/report_fonts.dart';
import 'package:dbs_annotator/report/report_text.dart';
import 'package:dbs_annotator/report/session_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A note whose characters Helvetica cannot draw at all.
  const rows = [
    SessionRow(
        blockId: '1',
        isInitial: '0',
        date: '2026-01-01',
        time: '09:00:00',
        scaleName: 'Tremor',
        scaleValue: '3',
        notes: '\u4e2d\u6587 note'),
  ];

  test('a PDF is always produced, with or without the Unicode fonts', () async {
    // This must hold in BOTH states, because whether app/assets/fonts holds the
    // IBM Plex TTFs is a deployment choice: a fresh checkout has none.
    //
    // The bug this pins: `pw.Font.ttf` parses LAZILY, so a file named .ttf that
    // is not a font — most easily the 300 KB HTML error page GitHub serves for
    // a dead raw URL — used to sail through `loadReportTheme`, which returned a
    // non-null theme. That switched the sanitiser OFF and then threw
    // "Unable to find the hmtx table" halfway through building the document, so
    // every export failed instead of falling back to Helvetica.
    final theme = await loadReportTheme();
    final report = await buildSessionPdf(
        data: buildSessionReportData(rows: rows), subjectId: '01');
    expect(report.bytes, isNotEmpty);
    expect(report.bytes.sublist(0, 4), '%PDF'.codeUnits);

    // And the two states are consistent with each other: no theme means the
    // sanitiser ran, which means an unrepresentable glyph was reported so the
    // UI can warn. A theme means full Unicode and nothing to report.
    if (theme == null) {
      expect(report.lostCharacters, isTrue,
          reason: 'Helvetica cannot draw CJK, so the loss must be reported');
    } else {
      expect(report.lostCharacters, isFalse,
          reason: 'a real Unicode font loses nothing');
    }
  });

  test('the sanitiser maps what it can and only flags a true loss', () {
    // A faithful substitution is not a loss; a `?` is. Getting this wrong in
    // either direction is bad: warn always and the warning is ignored, warn
    // never and a clinical note is silently corrupted.
    for (final (input, output) in const [
      ('curly \u2019 quote', "curly ' quote"),
      ('em \u2014 dash', 'em - dash'),
      ('at \u2265 least', 'at >= least'),
      ('micro \u00b5s', 'micro \u00b5s'),
      ('greek \u03bc', 'greek \u00b5'),
    ]) {
      final t = ReportTextSanitiser(active: true);
      expect(t(input), output);
      expect(t.lostCharacters, isFalse, reason: input);
    }

    final t = ReportTextSanitiser(active: true);
    expect(t('cjk \u4e2d\u6587'), 'cjk ??');
    expect(t.lostCharacters, isTrue);
  });

  test('inactive means verbatim, whatever the input', () {
    final t = ReportTextSanitiser(active: false);
    expect(t('\u4e2d\u6587 \u2019 \u2265'), '\u4e2d\u6587 \u2019 \u2265');
    expect(t.lostCharacters, isFalse);
  });
}
