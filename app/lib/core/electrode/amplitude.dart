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
/// own. Otherwise each per-contact value is `total * pct / 100` rounded to two
/// decimals, joined by `_`. Example: `encodeAmplitude(2.5, [60, 40]) == '1.5_1'`.
///
/// ## The parts sum EXACTLY to the total (deliberate divergence from Qt)
///
/// The desktop rounds each part independently, so the total does not survive the
/// round trip: 5.0 mA over three contacts becomes `1.67_1.67_1.67`, which sums
/// to **5.01**, and 7.0 mA becomes **6.99**. Every consumer then prints the
/// artifact as the delivered dose — the report table showed `= 5.01`, the
/// on-screen amplitude panel plotted 5.01 and 6.99, and grouping blocks by dose
/// put nominally identical settings in different bins.
///
/// So the residual is distributed by largest remainder: parts are rounded down
/// to hundredths, then a hundredth is added back to those with the largest
/// discarded fraction until the parts sum to the total. 5.0 over three contacts
/// becomes `1.67_1.67_1.66`. The output is still a plain `_`-joined list the
/// desktop parses unchanged, and the dose it states is now the dose that was set.
///
/// The cost is that re-deriving percentages from the parts gives 33.4/33.4/33.2
/// rather than three equal thirds. Preserving the DOSE matters more than
/// preserving the symmetry of a display: the total is what is titrated, printed
/// and analysed.
String encodeAmplitude(double total, List<double> percentages) {
  if (percentages.length <= 1) {
    return _stripTrailingZeros(total.toStringAsFixed(2));
  }
  // Work in integer hundredths so the arithmetic is exact.
  final targetHundredths = (total * 100).round();
  final exact = percentages.map((pct) => total * pct / 100.0 * 100).toList();
  final parts = exact.map((v) => v.floor()).toList();
  var residual = targetHundredths - parts.fold<int>(0, (a, b) => a + b);

  // Indices ordered by the fraction each one gave up, largest first.
  final order = List<int>.generate(exact.length, (i) => i)
    ..sort((a, b) {
      final cmp = (exact[b] - parts[b]).compareTo(exact[a] - parts[a]);
      return cmp != 0 ? cmp : a.compareTo(b);
    });
  // A negative residual can only arise from a total that is not a whole number
  // of hundredths; take back from the smallest remainders in that case.
  final step = residual >= 0 ? 1 : -1;
  for (var k = 0; residual != 0 && k < order.length * 2; k++) {
    final i = order[step > 0 ? k % order.length
        : order.length - 1 - (k % order.length)];
    if (parts[i] + step < 0) continue;
    parts[i] += step;
    residual -= step;
  }

  return parts
      .map((h) => _stripTrailingZeros((h / 100).toStringAsFixed(2)))
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
