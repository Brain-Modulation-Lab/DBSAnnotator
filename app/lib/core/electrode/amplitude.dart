/// Split-amplitude serialization shared with the desktop app's TSV files.
///
/// Ports `get_amplitude_text` and `set_amplitude_from_split` from
/// `src/dbs_annotator/ui/amplitude_split_widget.py`.
///
/// Format: a single total (e.g. `"2.5"`) when there is at most one cathode,
/// or per-contact mA values joined with `_` (e.g. `"1.5_1"`) when the total
/// is split across multiple cathodes.
library;

/// Encodes a total amplitude and its per-cathode percentage split.
///
/// With zero or one percentage entries, returns the [total] formatted on its
/// own. Otherwise each per-contact value is `total * pct / 100`, formatted to
/// two decimals with trailing zeros (and a trailing dot) stripped, joined by
/// `_`. Example: `encodeAmplitude(2.5, [60, 40]) == '1.5_1'`.
String encodeAmplitude(double total, List<double> percentages) {
  if (percentages.length <= 1) {
    return _stripTrailingZeros(total.toStringAsFixed(2));
  }
  return percentages
      .map((pct) => _stripTrailingZeros((total * pct / 100.0).toStringAsFixed(2)))
      .join('_');
}

/// Parses an amplitude string (single value or `_`-separated split) back into
/// the total and the percentage distribution.
///
/// Empty parts are ignored (matching Python). If the total is not positive,
/// all percentages are 0.0 (divide-by-zero guard, matching Python).
/// Throws [FormatException] on non-numeric parts.
({double total, List<double> percentages}) parseAmplitude(String text) {
  final values = <double>[];
  for (final part in text.split('_')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    values.add(double.parse(trimmed));
  }

  final total = values.fold(0.0, (sum, v) => sum + v);
  final percentages = values
      .map((v) => total > 0 ? v / total * 100.0 : 0.0)
      .toList(growable: false);
  return (total: total, percentages: percentages);
}

/// Strips trailing zeros, then a trailing dot, from a fixed-decimal string —
/// equivalent to Python's `f"{x:.2f}".rstrip("0").rstrip(".")`. Only call
/// this on strings that contain a decimal point (e.g. `toStringAsFixed`
/// output); otherwise trailing zeros of an integer would be eaten.
String _stripTrailingZeros(String fixed) {
  var out = fixed;
  while (out.endsWith('0')) {
    out = out.substring(0, out.length - 1);
  }
  if (out.endsWith('.')) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}
