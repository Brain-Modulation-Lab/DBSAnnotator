/// The Unicode font theme for the PDF reports, and what it can actually draw.
///
/// dart_pdf's built-in Type1 fonts (Helvetica) only cover Latin-1, which is
/// enough for the ASCII-only longitudinal report but not for the session
/// report's `µs` pulse-width unit or for verbatim clinical notes. The bundled
/// IBMPlexSans-Regular.ttf / IBMPlexSans-Bold.ttf (OFL,
/// https://github.com/IBM/plex) cover Latin, Greek and Cyrillic.
///
/// This loader degrades gracefully: when the TTFs are absent — a checkout
/// without them, or a pure-Dart test with no asset bundle — it reports no
/// coverage at all and callers fall back to Helvetica with the Latin-1
/// sanitiser switched on.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart' show TtfParser;
import 'package:pdf/widgets.dart' as pw;

/// A loaded report font: the theme to draw with, and the runes it can draw.
///
/// The coverage set is the point. Before it existed the sanitiser was switched
/// on and off by a single boolean — "did a theme load?" — which was right only
/// while the answer was almost always no. With the fonts bundled the answer is
/// always yes, and a CJK note (which IBM Plex Sans has no glyphs for) went from
/// "replaced with ? and reported" to "silently drawn as nothing". Coverage is
/// what distinguishes *this font can render it* from *some font could*.
typedef ReportFonts = ({pw.ThemeData? theme, Set<int> coverage});

/// No font: Helvetica, Latin-1 only, sanitiser on.
const ReportFonts noReportFonts = (theme: null, coverage: <int>{});

/// Load the bundled IBM Plex Sans TTFs, with the character map they provide.
Future<ReportFonts> loadReportFonts() async {
  try {
    final regular =
        await rootBundle.load('assets/fonts/IBMPlexSans-Regular.ttf');
    final base = pw.Font.ttf(regular);
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/IBMPlexSans-Bold.ttf'),
    );
    // Force the parse HERE, inside the guard.
    //
    // `pw.Font.ttf` is lazy: it stores the bytes and parses on first use. So a
    // file that is named .ttf but is not a font — most easily, the 300 KB HTML
    // error page GitHub serves for a dead raw URL — sailed through this
    // function, which then returned a non-null theme. That is strictly worse
    // than having no font at all: the sanitiser switched OFF because a theme
    // existed, and the parse then threw `Unable to find the hmtx table` in the
    // middle of building the document, so EVERY export failed instead of
    // degrading to Helvetica. Reading `fontName` parses the table directory, so
    // a bad file fails now, here, where the catch can do its job.
    if (base.fontName.isEmpty || bold.fontName.isEmpty) return noReportFonts;
    return (
      theme:
          pw.ThemeData.withFont(base: base, bold: bold, fontFallback: [base]),
      // The regular face's cmap. Bold is the same family and the same coverage,
      // and a character present in one but not the other would be a broken
      // font, not a case worth splitting the set for.
      coverage: TtfParser(regular).charToGlyphIndexMap.keys.toSet(),
    );
  } catch (_) {
    // Missing asset, no asset bundle at all (pure Dart tests), or a file that
    // is not a usable font.
    return noReportFonts;
  }
}
