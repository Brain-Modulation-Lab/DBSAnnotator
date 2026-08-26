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

/// True when [rune] can be encoded by the Latin-1 fallback font.
bool _isLatin1(int rune) => rune <= 0xFF;

/// Map [input] onto Latin-1, substituting known typography and replacing
/// anything else with '?'.
///
/// [replaced] is true only when a character had to be replaced by '?' — the
/// known typographic substitutions above are faithful, so they do not count as
/// loss and must not trigger a warning.
SanitisedText sanitiseForLatin1(String input) {
  if (input.isEmpty) return (text: input, replaced: false);

  // Fast path: nothing to do for plain ASCII/Latin-1 text, which is the norm.
  var needsWork = false;
  for (final rune in input.runes) {
    if (!_isLatin1(rune) || _replacements.containsKey(String.fromCharCode(rune))) {
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
    if (mapped != null) {
      out.write(mapped);
    } else if (_isLatin1(rune)) {
      out.write(ch);
    } else {
      out.write('?');
      lost = true;
    }
  }
  return (text: out.toString(), replaced: lost);
}

/// Sanitises every string a report will draw, tracking whether anything was
/// lost so the UI can tell the user once.
///
/// Used by the PDF builder only when no Unicode theme could be loaded; with the
/// TTFs present the text is passed through untouched.
class ReportTextSanitiser {
  ReportTextSanitiser({required this.active});

  /// False when a Unicode font is available, in which case this is a no-op.
  final bool active;

  /// True once any character had to be replaced by '?'.
  bool get lostCharacters => _lost;
  bool _lost = false;

  String call(String input) {
    if (!active) return input;
    final result = sanitiseForLatin1(input);
    if (result.replaced) _lost = true;
    return result.text;
  }

  /// Convenience for table data.
  List<List<String>> rows(List<List<String>> data) =>
      active ? [for (final r in data) [for (final c in r) call(c)]] : data;
}
