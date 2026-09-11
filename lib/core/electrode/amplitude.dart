/// Split-amplitude serialization shared with the desktop app's TSV files: a
/// single total (`"2.5"`) when there is at most one cathode, or per-contact mA
/// values joined with `_` (`"1.5_1"`) when the total is split across several.
library;

/// Encodes a total amplitude and a per-cathode percentage split. Parts are
/// rounded by largest remainder so they sum exactly to [total]; the desktop
/// rounds each part independently, so 5.0 mA over three contacts becomes
/// `1.67_1.67_1.67` and reads as a 5.01 mA dose downstream.
String encodeAmplitude(double total, List<double> percentages) {
  if (percentages.length <= 1) {
    return _stripTrailingZeros(total.toStringAsFixed(2));
  }
  // Work in integer hundredths so the arithmetic is exact.
  final targetHundredths = (total * 100).round();
  final exact = percentages.map((pct) => total * pct / 100.0 * 100).toList();
  final parts = exact.map((v) => v.floor()).toList();
  var residual = targetHundredths - parts.fold<int>(0, (a, b) => a + b);

  final order = List<int>.generate(exact.length, (i) => i)
    ..sort((a, b) {
      final cmp = (exact[b] - parts[b]).compareTo(exact[a] - parts[a]);
      return cmp != 0 ? cmp : a.compareTo(b);
    });
  // A negative residual (a total not in whole hundredths) takes back instead.
  final step = residual >= 0 ? 1 : -1;
  for (var k = 0; residual != 0 && k < order.length * 2; k++) {
    final i =
        order[step > 0
            ? k % order.length
            : order.length - 1 - (k % order.length)];
    if (parts[i] + step < 0) continue;
    parts[i] += step;
    residual -= step;
  }

  return parts
      .map((h) => _stripTrailingZeros((h / 100).toStringAsFixed(2)))
      .join('_');
}

/// Parses a single value or `_`-separated split into the total and its
/// percentage distribution; a non-positive total yields all-zero percentages.
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

/// Strips trailing zeros, then a trailing dot. Only safe on strings that
/// contain a decimal point (e.g. `toStringAsFixed` output).
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
