/// Text sanitising for the PDF report's Latin-1 fallback font.
///
/// ## Why this exists
///
/// When the optional IBM Plex TTFs are absent from `assets/fonts/` — which is
/// the shipping state — `loadReportTheme()` returns null and dart_pdf falls back
/// to built-in Helvetica, a Type1 font that can only encode Latin-1.
///
/// dart_pdf does **not** throw on an unsupported rune. `RichText._preProcessSpans`
/// pre-checks every rune and silently substitutes an empty **placeholder box**
/// (`pdf/lib/src/widgets/text.dart`). So a clinician typing a smart apostrophe
/// on an iPad — where smart punctuation is on by default — gets a blank
/// rectangle in the middle of an exported clinical document, with no error
/// anywhere. Silent corruption of a clinical record is worse than a loud
/// failure, so this maps the characters that actually turn up in clinical notes
/// onto Latin-1 equivalents, and flags anything it had to replace outright.
///
/// The Word report needs none of this: its XML is UTF-8 and Word uses system
/// fonts, so it renders any character correctly. This is a PDF-only concern.
library;

/// Typographic characters that commonly reach us from iOS/Word autocorrect and
/// from pasted text, mapped to Latin-1 equivalents that mean the same thing.
const _replacements = <String, String>{
  '‘': "'", // ' left single quote
  '’': "'", // ' right single quote / apostrophe
  '‚': "'",
  '‛': "'",
  '“': '"', // " left double quote
  '”': '"', // " right double quote
  '„': '"',
  '′': "'", // prime
  '″': '"', // double prime
  '–': '-', // – en dash
  '—': '-', // — em dash
  '―': '-',
  '−': '-', // − minus sign
  '…': '...', // … ellipsis
  '•': '-', // • bullet
  ' ': ' ', // non-breaking space
  ' ': ' ', // thin space
  ' ': ' ', // narrow no-break space
  '≥': '>=', // ≥
  '≤': '<=', // ≤
  '≠': '!=', // ≠
  '≈': '~', // ≈
  '×': 'x', // × (Latin-1, but 'x' reads better in a note)
  '→': '->', // →
  '←': '<-', // ←
  '↑': 'up', // ↑
  '↓': 'down', // ↓
  'Δ': 'delta', // Δ
  'μ': 'µ', // μ GREEK MU -> µ MICRO SIGN, which IS Latin-1
  '℃': '°C', // ℃
  '℉': '°F', // ℉
};

/// Result of sanitising: the safe text, plus whether anything was lost.
typedef SanitisedText = ({String text, bool replaced});

/// Map [input] onto what the report font can draw, substituting known
/// typography and replacing anything else with '?'.
///
/// [coverage] is the set of runes the loaded font provides a glyph for; empty
/// means no font was loaded, so the Latin-1 built-in is what will draw the text.
///
/// [replaced] is true only when a character had to be replaced by '?' — the
/// known typographic substitutions above are faithful, so they do not count as
/// loss and must not trigger a warning.
SanitisedText sanitiseForFont(String input, {Set<int> coverage = const {}}) {
  if (input.isEmpty) return (text: input, replaced: false);

  // Latin-1 is what dart_pdf's built-in Helvetica covers, and is the floor: a
  // loaded font is only ever consulted for what falls outside it.
  bool drawable(int rune) =>
      coverage.isEmpty ? rune <= 0xFF : coverage.contains(rune);

  // Fast path: nothing to do for plain ASCII/Latin-1 text, which is the norm.
  var needsWork = false;
  for (final rune in input.runes) {
    if (!drawable(rune) ||
        _replacements.containsKey(String.fromCharCode(rune))) {
      needsWork = true;
      break;
    }
  }
  if (!needsWork) return (text: input, replaced: false);

  final out = StringBuffer();
  var lost = false;
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    final mapped = _replacements[ch];
    // The table is applied whatever the font covers. Its entries are faithful
    // by construction, and several of them — the space variants especially —
    // are worth normalising even when the font could draw the original: a
    // non-breaking space inside a report table cell is a layout hazard, not a
    // fidelity gain.
    if (mapped != null) {
      out.write(mapped);
    } else if (drawable(rune)) {
      out.write(ch);
    } else {
      out.write('?');
      lost = true;
    }
  }
  return (text: out.toString(), replaced: lost);
}

/// Map [input] onto Latin-1 — [sanitiseForFont] with no font loaded.
SanitisedText sanitiseForLatin1(String input) => sanitiseForFont(input);

/// Sanitises every string a report will draw, tracking whether anything was
/// lost so the UI can tell the user once.
///
/// Always runs. It used to be switched off whenever a Unicode theme loaded,
/// which was a reasonable shortcut while the fonts were an optional download —
/// but IBM Plex Sans covers Latin, Greek and Cyrillic and no more, so with the
/// fonts bundled that shortcut turned a CJK clinical note from "replaced with ?
/// and reported" into "drawn as nothing, silently". [coverage] is what the
/// loaded font can actually draw; empty means Helvetica's Latin-1.
class ReportTextSanitiser {
  ReportTextSanitiser({this.coverage = const {}});

  /// The runes the report font provides a glyph for.
  final Set<int> coverage;

  /// True once any character had to be replaced by '?'.
  bool get lostCharacters => _lost;
  bool _lost = false;

  String call(String input) {
    final result = sanitiseForFont(input, coverage: coverage);
    if (result.replaced) _lost = true;
    return result.text;
  }

  /// Convenience for table data.
  List<List<String>> rows(List<List<String>> data) => [
        for (final r in data) [for (final c in r) call(c)]
      ];
}
