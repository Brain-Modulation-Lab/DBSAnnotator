/// The Unicode font theme for the PDF reports. dart_pdf's built-in Helvetica
/// is Latin-1 only, too narrow for the `µs` pulse-width unit and for verbatim
/// clinical notes, so the reports draw with bundled IBM Plex Sans (OFL).
/// Absent TTFs fall back to Helvetica with the Latin-1 sanitiser on.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart' show TtfParser;
import 'package:pdf/widgets.dart' as pw;

/// The theme to draw with, plus the runes it can actually draw. Coverage, not
/// a "did a theme load?" flag: Plex lacks CJK, which a flag draws as nothing.
typedef ReportFonts = ({pw.ThemeData? theme, Set<int> coverage});

/// No font: Helvetica, Latin-1 only, sanitiser on.
const ReportFonts noReportFonts = (theme: null, coverage: <int>{});

/// Load the bundled IBM Plex Sans TTFs, with the character map they provide.
Future<ReportFonts> loadReportFonts() async {
  try {
    final regular = await rootBundle.load(
      'assets/fonts/IBMPlexSans-Regular.ttf',
    );
    final base = pw.Font.ttf(regular);
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/IBMPlexSans-Bold.ttf'),
    );
    // Force the lazy parse inside the guard: `pw.Font.ttf` only stores bytes,
    // so a file that is not really a font (an HTML error page saved as .ttf)
    // would yield a theme, switch the sanitiser off, then throw mid-document.
    // Reading `fontName` parses the table directory, failing here instead.
    if (base.fontName.isEmpty || bold.fontName.isEmpty) return noReportFonts;
    return (
      theme: pw.ThemeData.withFont(
        base: base,
        bold: bold,
        fontFallback: [base],
      ),
      // Bold is the same family, so one face's cmap describes both.
      coverage: TtfParser(regular).charToGlyphIndexMap.keys.toSet(),
    );
  } catch (_) {
    return noReportFonts;
  }
}
