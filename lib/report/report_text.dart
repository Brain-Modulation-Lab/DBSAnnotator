/// Text sanitising for the PDF report's Latin-1 fallback font.
///
/// With the optional IBM Plex TTFs absent from `assets/fonts/`, which is the
/// shipping state, dart_pdf falls back to built-in Helvetica, a Type1 font that
/// can only encode Latin-1. It does not throw on an unsupported rune: it
/// silently substitutes an empty placeholder box. So a clinician typing a smart
/// apostrophe on an iPad, where smart punctuation is on by default, gets a
/// blank rectangle in an exported clinical document with no error anywhere.
/// This maps the characters that turn up in clinical notes onto Latin-1
/// equivalents and flags anything it had to replace outright.
///
/// PDF-only: the Word report's XML is UTF-8 and Word uses system fonts.
library;

/// Typographic characters that commonly reach us from iOS/Word autocorrect and
/// from pasted text, mapped to Latin-1 equivalents that mean the same thing.
const _replacements = <String, String>{
  '‘': "'", // left single quote
  '’': "'", // right single quote / apostrophe
  '‚': "'",
  '‛': "'",
  '“': '"', // left double quote
  '”': '"', // right double quote
  '„': '"',
  '′': "'", // prime
  '″': '"', // double prime
  '–': '-', // en dash
  '—': '-', // em dash
  '―': '-',
  '−': '-', // minus sign
  '…': '...', // ellipsis
  '•': '-', // bullet
  ' ': ' ', // non-breaking space
  ' ': ' ', // thin space
  ' ': ' ', // narrow no-break space
  '\t': ' ', // a tab inside a table cell is a layout hazard, not fidelity
  '\r': '', // the line break is carried by the newline beside it
  '≥': '>=',
  '≤': '<=',
  '≠': '!=',
  '≈': '~',
  '×': 'x', // Latin-1, but 'x' reads better in a note
  '→': '->',
  '←': '<-',
  '↑': 'up',
  '↓': 'down',
  'Δ': 'delta',
  'μ': 'µ', // GREEK MU -> MICRO SIGN, which IS Latin-1
  '℃': '°C',
  '℉': '°F',
};

/// Result of sanitising: the safe text, plus whether anything was lost.
typedef SanitisedText = ({String text, bool replaced});

/// Map [input] onto what the report font can draw, substituting known
/// typography and replacing anything else with '?'.
///
/// [coverage] is the set of runes the loaded font provides a glyph for; empty
/// means no font was loaded, so the Latin-1 built-in will draw the text.
/// [replaced] is true only for a character replaced by '?', since the
/// substitutions above are faithful and must not trigger a warning.
SanitisedText sanitiseForFont(String input, {Set<int> coverage = const {}}) {
  if (input.isEmpty) return (text: input, replaced: false);

  // Latin-1 is what dart_pdf's built-in Helvetica covers, and is the floor: a
  // loaded font is only ever consulted for what falls outside it. A line break
  // is exempt because it is structure rather than a glyph: dart_pdf splits a
  // span on it and the Word builder emits a break element, so neither renderer
  // consults the font, while a TTF cmap carries no entry for it. Testing it
  // against coverage puts a literal '?' into every multi-line table cell.
  bool drawable(int rune) =>
      rune == 0x0A ||
      (coverage.isEmpty ? rune <= 0xFF : coverage.contains(rune));

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
    // The table applies whatever the font covers. The space variants are worth
    // normalising even when the font could draw the original: a non-breaking
    // space inside a report table cell is a layout hazard, not fidelity.
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

/// [sanitiseForFont] with no font loaded, i.e. straight to Latin-1.
SanitisedText sanitiseForLatin1(String input) => sanitiseForFont(input);

/// Sanitises every string a report will draw, tracking whether anything was
/// lost so the UI can tell the user once.
///
/// Runs even when a Unicode theme loaded: IBM Plex Sans covers Latin, Greek and
/// Cyrillic and no more, so skipping it turned a CJK clinical note from
/// "replaced with ? and reported" into "drawn as nothing, silently".
/// [coverage] is what the font can draw; empty means Helvetica's Latin-1.
class ReportTextSanitiser {
  ReportTextSanitiser({this.coverage = const {}});

  final Set<int> coverage;

  /// True once any character had to be replaced by '?'.
  bool get lostCharacters => _lost;
  bool _lost = false;

  String call(String input) {
    final result = sanitiseForFont(input, coverage: coverage);
    if (result.replaced) _lost = true;
    return result.text;
  }

  List<List<String>> rows(List<List<String>> data) => [
    for (final r in data) [for (final c in r) call(c)],
  ];
}
