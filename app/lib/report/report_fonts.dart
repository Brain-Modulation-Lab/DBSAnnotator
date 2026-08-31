/// Optional Unicode font theme for the PDF reports.
///
/// dart_pdf's built-in Type1 fonts (Helvetica) only cover Latin-1, which is
/// enough for the ASCII-only longitudinal report but not for the session
/// report's `µs` pulse-width unit and verbatim clinical notes (arbitrary
/// Unicode). IBMPlexSans-Regular.ttf / IBMPlexSans-Bold.ttf are OFL-licensed
/// (https://github.com/IBM/plex) and are dropped into app/assets/fonts/
/// (see app/README). This loader degrades gracefully: when the TTFs are
/// absent (e.g. headless tests, a checkout without the fonts) it returns null
/// and callers omit the theme, letting dart_pdf fall back to Helvetica — ASCII
/// still renders.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Load the bundled IBM Plex Sans TTFs into a pdf theme, or null when they are
/// missing (caller then builds `pw.Document()` without a theme).
Future<pw.ThemeData?> loadReportTheme() async {
  try {
    final base = pw.Font.ttf(
      await rootBundle.load('assets/fonts/IBMPlexSans-Regular.ttf'),
    );
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
    // `fontName` builds a TtfParser over the bytes, which is what actually
    // reads the table directory.
    if (base.fontName.isEmpty || bold.fontName.isEmpty) return null;
    return pw.ThemeData.withFont(
      base: base,
      bold: bold,
      fontFallback: [base],
    );
  } catch (_) {
    // Missing asset, no asset bundle at all (pure Dart tests), or a file that
    // is not a usable font: fall back to the built-in Helvetica by returning no
    // theme. Callers then enable the sanitiser and warn if a glyph was lost.
    return null;
  }
}
