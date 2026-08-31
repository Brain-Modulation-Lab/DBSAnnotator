import 'package:dbs_annotator/core/session/scale_scoring.dart';
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
}
