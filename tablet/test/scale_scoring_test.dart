import 'package:dbs_annotator_tablet/core/session/scale_scoring.dart';
import 'package:dbs_annotator_tablet/core/session/session_row.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the Dart port against the desktop implementation. Every expected number
/// here was produced by running the Python functions themselves
/// (`report_chart_utils.parse_scale_targets` / `compute_aggregate_index` /
/// `get_declared_scale_range` / `find_best_and_second`, and the scoring loop of
/// `session_exporter._find_best_and_second_best_blocks`) over the same fixture
/// and pasting the result — not by reading the Dart output back.
void main() {
  ScalePref pref(String name, double lo, double hi, ScaleMode mode,
          [double? custom]) =>
      (name: name, min: lo, max: hi, mode: mode, custom: custom);

  /// One block's worth of rows: one row per (scale, value), as the tablet writes.
  List<SessionRow> rowsFor(Map<int, List<(String, String)>> blocks) => [
        for (final entry in blocks.entries)
          for (final pair in entry.value)
            SessionRow(
              blockId: '${entry.key}',
              isInitial: '0',
              scaleName: pair.$1,
              scaleValue: pair.$2,
            ),
      ];

  Map<int, double> indexOf(
    Map<String, Map<int, double>> data,
    List<ScalePref> prefs,
  ) {
    final points = <int>{for (final m in data.values) ...m.keys}.toList()..sort();
    return computeAggregateIndex(data, points, parseScaleTargets(prefs));
  }

  group('parseScaleTargets', () {
    test('min targets the lower bound, max the upper', () {
      final t = parseScaleTargets([
        pref('Tremor', 0, 10, ScaleMode.min),
        pref('Mood', 0, 10, ScaleMode.max),
      ]);
      expect(t['Tremor'],
          (type: ScaleMode.min, value: 0.0, lower: 0.0, upper: 10.0));
      expect(t['Mood'],
          (type: ScaleMode.max, value: 10.0, lower: 0.0, upper: 10.0));
    });

    test('bounds are swapped when min > max', () {
      final t = parseScaleTargets([pref('Rev', 10, 0, ScaleMode.min)]);
      expect(t['Rev'],
          (type: ScaleMode.min, value: 0.0, lower: 0.0, upper: 10.0));
    });

    test('custom carries the target value, absent custom becomes 0', () {
      final t = parseScaleTargets([
        pref('Sweet', 0, 10, ScaleMode.custom, 5),
        pref('Bare', 0, 10, ScaleMode.custom),
      ]);
      expect(t['Sweet']!.value, 5.0);
      expect(t['Bare']!.value, 0.0);
    });

    test('ignore yields no entry at all', () {
      final t = parseScaleTargets([pref('Skip', 0, 10, ScaleMode.ignore)]);
      expect(t, isEmpty);
    });
  });

  group('scaleModeFromString', () {
    test('accepts the low/high aliases alongside min/max', () {
      expect(scaleModeFromString('low'), ScaleMode.min);
      expect(scaleModeFromString('MIN'), ScaleMode.min);
      expect(scaleModeFromString(' high '), ScaleMode.max);
      expect(scaleModeFromString('max'), ScaleMode.max);
      expect(scaleModeFromString('custom'), ScaleMode.custom);
    });

    test('anything unrecognised becomes ignore', () {
      expect(scaleModeFromString('sideways'), ScaleMode.ignore);
      expect(scaleModeFromString(''), ScaleMode.ignore);
    });
  });

  group('scalePrefFromStrings', () {
    test('unparseable bounds and custom coerce to 0.0', () {
      final p = scalePrefFromStrings(
          name: 'X', min: 'abc', max: '', mode: 'min', custom: 'zz');
      expect(p.min, 0.0);
      expect(p.max, 0.0);
      expect(p.custom, 0.0);
    });
  });

  group('computeAggregateIndex', () {
    test('two scales, min and max over the same range', () {
      // Python: {1: 0.2, 2: 0.6, 3: 0.55}
      final idx = indexOf({
        'Tremor': {1: 8.0, 2: 4.0, 3: 2.0},
        'Mood': {1: 2.0, 2: 6.0, 3: 3.0},
      }, [
        pref('Tremor', 0, 10, ScaleMode.min),
        pref('Mood', 0, 10, ScaleMode.max),
      ]);
      expect(idx[1], closeTo(0.2, 1e-12));
      expect(idx[2], closeTo(0.6, 1e-12));
      expect(idx[3], closeTo(0.55, 1e-12));
    });

    test('an unlisted scale scores 0.5 at half weight', () {
      // Python: {1: 0.833333333333, 2: 0.166666666667}
      final idx = indexOf({
        'Tremor': {1: 0.0, 2: 10.0},
        'Unlisted': {1: 7.0, 2: 7.0},
      }, [
        pref('Tremor', 0, 10, ScaleMode.min),
      ]);
      expect(idx[1], closeTo(0.8333333333333333, 1e-12));
      expect(idx[2], closeTo(0.16666666666666666, 1e-12));
    });

    test('a non-positive span scores a flat 0.5', () {
      // Python: {1: 0.5, 2: 0.5}
      final idx = indexOf({'Flat': {1: 5.0, 2: 9.0}},
          [pref('Flat', 4, 4, ScaleMode.min)]);
      expect(idx[1], 0.5);
      expect(idx[2], 0.5);
    });

    test('a custom target scores 1.0 on the nose and 0.0 at both bounds', () {
      // Python: {1: 0.0, 2: 1.0, 3: 0.0}
      final idx = indexOf({'Sweet': {1: 0.0, 2: 5.0, 3: 10.0}},
          [pref('Sweet', 0, 10, ScaleMode.custom, 5)]);
      expect(idx[1], closeTo(0.0, 1e-12));
      expect(idx[2], closeTo(1.0, 1e-12));
      expect(idx[3], closeTo(0.0, 1e-12));
    });

    test('an ignored scale falls through to the unknown-scale branch', () {
      // Python: targets {} -> {1: 0.5, 2: 0.5}
      final idx = indexOf({'Skip': {1: 1.0, 2: 9.0}},
          [pref('Skip', 0, 10, ScaleMode.ignore)]);
      expect(idx[1], 0.5);
      expect(idx[2], 0.5);
    });

    test('values are clipped into [0, 1] beyond the declared bounds', () {
      final idx = indexOf({'Tremor': {1: -5.0, 2: 20.0}},
          [pref('Tremor', 0, 10, ScaleMode.min)]);
      expect(idx[1], 1.0); // clipped low end -> best
      expect(idx[2], 0.0); // clipped high end -> worst
    });

    test('points where no scale has a value are absent', () {
      final idx = computeAggregateIndex(
        {'Tremor': {1: 5.0}},
        [1, 2, 3],
        parseScaleTargets([pref('Tremor', 0, 10, ScaleMode.min)]),
      );
      expect(idx.keys, [1]);
    });
  });

  group('declaredScaleRange', () {
    test('spans the union of every declared range', () {
      final r = declaredScaleRange(parseScaleTargets([
        pref('Tremor', 0, 10, ScaleMode.min),
        pref('Big', 0, 100, ScaleMode.max),
      ]));
      expect(r, (0.0, 100.0));
    });

    test('null when the span collapses or nothing is declared', () {
      // Python get_declared_scale_range returns None for both.
      expect(
          declaredScaleRange(
              parseScaleTargets([pref('Flat', 4, 4, ScaleMode.min)])),
          isNull);
      expect(declaredScaleRange(const {}), isNull);
    });
  });

  group('findBestAndSecond', () {
    test('highest index wins', () {
      // Python best/2nd for fixture A: (2, 3)
      final idx = indexOf({
        'Tremor': {1: 8.0, 2: 4.0, 3: 2.0},
        'Mood': {1: 2.0, 2: 6.0, 3: 3.0},
      }, [
        pref('Tremor', 0, 10, ScaleMode.min),
        pref('Mood', 0, 10, ScaleMode.max),
      ]);
      expect(findBestAndSecond(idx), (2, 3));
    });

    test('ties resolve by point order, like Python stable sort', () {
      // Python: {1: 0.5, 2: 0.5, 3: 0.5} -> (1, 2)
      final idx = indexOf({'Same': {1: 5.0, 2: 5.0, 3: 5.0}},
          [pref('Same', 0, 10, ScaleMode.min)]);
      expect(findBestAndSecond(idx), (1, 2));
    });

    test('a tie for second resolves to the earlier point', () {
      // Python fixture E: {1: 0.0, 2: 1.0, 3: 0.0} -> (2, 1)
      final idx = indexOf({'Sweet': {1: 0.0, 2: 5.0, 3: 10.0}},
          [pref('Sweet', 0, 10, ScaleMode.custom, 5)]);
      expect(findBestAndSecond(idx), (2, 1));
    });

    test('empty and single-point inputs', () {
      expect(findBestAndSecond(const {}), (null, null));
      expect(findBestAndSecond(const {7: 0.3}), (7, null));
    });
  });

  group('findBestAndSecondBlocks', () {
    test('lower summed score wins, and max flips the sign', () {
      // Python scores: {1: -50.0, 2: -90.0} -> best [2], second [1]
      final r = findBestAndSecondBlocks(
        rowsFor({
          1: [('Tremor', '0'), ('Big', '50')],
          2: [('Tremor', '10'), ('Big', '100')],
        }),
        [
          pref('Tremor', 0, 10, ScaleMode.min),
          pref('Big', 0, 100, ScaleMode.max),
        ],
      );
      expect(r.best, [2]);
      expect(r.second, [1]);
    });

    test('ties return every block at that score', () {
      // Python scores: {1: 3.0, 2: 3.0, 3: 7.0} -> best [1, 2], second [3]
      final r = findBestAndSecondBlocks(
        rowsFor({1: [('A', '3')], 2: [('A', '3')], 3: [('A', '7')]}),
        [pref('A', 0, 10, ScaleMode.min)],
      );
      expect(r.best, [1, 2]);
      expect(r.second, [3]);
    });

    test('an ignored scale excludes a block with nothing else scored', () {
      // Python scores: {1: 3.0} -> best [1], second []
      final r = findBestAndSecondBlocks(
        rowsFor({1: [('A', '3')], 2: [('Skipped', '9')]}),
        [
          pref('A', 0, 10, ScaleMode.min),
          pref('Skipped', 0, 10, ScaleMode.ignore),
        ],
      );
      expect(r.best, [1]);
      expect(r.second, isEmpty);
    });

    test('custom scores by absolute distance to the target', () {
      // Python scores: {1: 0.0, 2: 5.0, 3: 4.0} -> best [1], second [3]
      final r = findBestAndSecondBlocks(
        rowsFor({1: [('S', '5')], 2: [('S', '0')], 3: [('S', '9')]}),
        [pref('S', 0, 10, ScaleMode.custom, 5)],
      );
      expect(r.best, [1]);
      expect(r.second, [3]);
    });

    test('an unlisted scale defaults to min, matching the desktop lookup', () {
      final r = findBestAndSecondBlocks(
        rowsFor({1: [('Nobody', '2')], 2: [('Nobody', '8')]}),
        const [],
      );
      expect(r.best, [1]);
      expect(r.second, [2]);
    });

    test('omitted and non-numeric values are skipped', () {
      final r = findBestAndSecondBlocks(
        rowsFor({
          1: [('A', '1'), ('A2', 'NaN')],
          2: [('A', 'oops')],
        }),
        [pref('A', 0, 10, ScaleMode.min)],
      );
      // Block 2 has no parseable value, so it is not ranked at all.
      expect(r.best, [1]);
      expect(r.second, isEmpty);
    });

    test('duplicate (name, value) pairs in a block are counted once', () {
      final r = findBestAndSecondBlocks(
        rowsFor({
          1: [('A', '4'), ('A', '4')], // deduplicated -> 4, not 8
          2: [('A', '6')],
        }),
        [pref('A', 0, 10, ScaleMode.min)],
      );
      expect(r.best, [1]);
    });

    test('no usable rows returns two empty lists', () {
      expect(findBestAndSecondBlocks(const [], const []).best, isEmpty);
      expect(findBestAndSecondBlocks(const [], const []).second, isEmpty);
    });
  });

  group('defaultScalePrefsFor', () {
    test('every scale gets mode min, bounds from the map or the fallback', () {
      final prefs = defaultScalePrefsFor(
        rowsFor({1: [('Tremor', '3'), ('Custom', '5')]}),
        bounds: {'Custom': (1.0, 4.0)},
        fallback: (0.0, 10.0),
      );
      expect(prefs.map((p) => p.name), ['Tremor', 'Custom']);
      expect(prefs.every((p) => p.mode == ScaleMode.min), isTrue);
      expect(prefs.firstWhere((p) => p.name == 'Tremor').max, 10.0);
      expect(prefs.firstWhere((p) => p.name == 'Custom').min, 1.0);
      expect(prefs.firstWhere((p) => p.name == 'Custom').max, 4.0);
    });

    test('scales are deduplicated and omitted values ignored', () {
      final prefs = defaultScalePrefsFor(rowsFor({
        1: [('Tremor', '3'), ('Gone', 'NaN')],
        2: [('Tremor', '5')],
      }));
      expect(prefs.map((p) => p.name), ['Tremor']);
    });
  });

  // PARITY: the chart bands and the table shading come from two different
  // desktop algorithms and are allowed to disagree. Verified against Python:
  // compute_aggregate_index gives {1: 0.75, 2: 0.5} so the chart bands block 1,
  // while the raw sums are {1: -50.0, 2: -90.0} so the table shades block 2.
  // If this test starts failing because the two now agree, someone has
  // "unified" them and broken parity with the desktop.
  test('the chart ranking and the table ranking may disagree (desktop parity)',
      () {
    final prefs = [
      pref('Tremor', 0, 10, ScaleMode.min),
      pref('Big', 0, 100, ScaleMode.max),
    ];
    final chart = findBestAndSecond(indexOf({
      'Tremor': {1: 0.0, 2: 10.0},
      'Big': {1: 50.0, 2: 100.0},
    }, prefs));
    final table = findBestAndSecondBlocks(
      rowsFor({
        1: [('Tremor', '0'), ('Big', '50')],
        2: [('Tremor', '10'), ('Big', '100')],
      }),
      prefs,
    );

    expect(chart.$1, 1, reason: 'chart normalises, so block 1 wins');
    expect(table.best, [2], reason: 'table sums raw values, so block 2 wins');
    expect(chart.$1, isNot(table.best.first));
  });
}
