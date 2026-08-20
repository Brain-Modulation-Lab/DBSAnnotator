/// Optional Unicode font theme for the PDF reports.
///
/// dart_pdf's built-in Type1 fonts (Helvetica) only cover Latin-1, which is
/// enough for the ASCII-only longitudinal report but not for the session
/// report's `µs` pulse-width unit and verbatim clinical notes (arbitrary
/// Unicode). IBMPlexSans-Regular.ttf / IBMPlexSans-Bold.ttf are OFL-licensed
/// (https://github.com/IBM/plex) and are dropped into tablet/assets/fonts/
/// (see tablet/README). This loader degrades gracefully: when the TTFs are
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
    return pw.ThemeData.withFont(
      base: base,
      bold: bold,
      fontFallback: [base],
    );
  } catch (_) {
    // Missing asset (or no asset bundle at all in pure Dart tests): fall
    // back to the built-in Helvetica by returning no theme.
    return null;
  }
}
