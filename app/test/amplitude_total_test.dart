/// The split amplitude must sum to the dose that was set.
library;

import 'package:dbs_annotator/core/electrode/amplitude.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the parts always sum exactly to the total', () {
    // The desktop rounds each part independently, so 5.0 mA over three contacts
    // became `1.67_1.67_1.67` = 5.01 and 7.0 became 6.99 — and every consumer
    // then printed the artifact as the delivered dose.
    const cases = <(double, List<double>)>[
      (5.0, [33.33, 33.33, 33.33]),
      (7.0, [33.33, 33.33, 33.33]),
      (1.0, [33.33, 33.33, 33.33]),
      (2.5, [60, 40]),
      (5.5, [60, 40]),
      (10.0, [25, 25, 25, 25]),
      (0.05, [50, 50]),
      (8.1, [70, 30]),
      (3.7, [33.33, 33.33, 33.33]),
    ];
    for (final (total, pct) in cases) {
      final encoded = encodeAmplitude(total, pct);
      expect(parseAmplitude(encoded).total, closeTo(total, 1e-9),
          reason: '$total split $pct encoded as "$encoded"');
    }
  });

  test('the clean splits are unchanged from the desktop', () {
    // Where independent rounding already summed correctly, the output must be
    // byte-identical to what the desktop writes, or existing files would
    // round-trip differently.
    expect(encodeAmplitude(2.5, [60, 40]), '1.5_1');
    expect(encodeAmplitude(5.5, [60, 40]), '3.3_2.2');
    expect(encodeAmplitude(3.0, [50, 50]), '1.5_1.5');
    expect(encodeAmplitude(10.0, [25, 25, 25, 25]), '2.5_2.5_2.5_2.5');
  });

  test('the residual lands on the largest discarded fraction', () {
    // 5.0 / 3 = 1.6667 each: all three give up the same fraction, so the extra
    // hundredth goes to the first by the stable tie-break.
    expect(encodeAmplitude(5.0, [33.33, 33.33, 33.33]), '1.67_1.67_1.66');
    expect(encodeAmplitude(7.0, [33.33, 33.33, 33.33]), '2.34_2.33_2.33');
  });

  test('a single contact or none is the total alone', () {
    expect(encodeAmplitude(4.5, const []), '4.5');
    expect(encodeAmplitude(4.5, const [100]), '4.5');
  });
}
