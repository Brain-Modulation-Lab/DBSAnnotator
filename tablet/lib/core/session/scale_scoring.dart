/// Scale-optimisation targets and the two block-ranking algorithms used by the
/// reports.
///
/// Ports, verbatim in behaviour:
/// - `parse_scale_targets`, `compute_aggregate_index`,
///   `get_declared_scale_range`, `find_best_and_second` from
///   `src/dbs_annotator/utils/report_chart_utils.py` — these drive the green
///   best / second-best BANDS on the scales chart;
/// - `_find_best_and_second_best_blocks` from
///   `src/dbs_annotator/utils/session_exporter.py` — this drives the green
///   ROW SHADING in the session data table.
///
/// PARITY: the two are deliberately *different* algorithms and can disagree.
/// The chart normalises each scale into its declared [lower, upper] and
/// averages (higher = better); the table sums raw values with a sign per mode
/// (lower = better). A block can therefore be banded on the chart without being
/// shaded in the table. This mirrors the desktop exactly — do not "fix" it, and
/// see `scale_scoring_test.dart` for the test that pins it.
///
/// Pure Dart: no Flutter imports, so it is testable with no asset bundle.
library;

import 'longitudinal.dart'
    show ScalePair, isScaleValueOmitted, splitScalePairs;
import 'session_row.dart';

/// How a scale should be optimised. Mirrors the desktop's `mode` string in the
/// `(name, min, max, mode, custom)` preference tuples.
enum ScaleMode {
  /// Lower is better.
  min,

  /// Higher is better.
  max,

  /// Closer to [ScalePref.custom] is better.
  custom,

  /// Excluded from both rankings entirely.
  ignore,
}

/// One row of the desktop's scale-optimisation preferences: the 5-tuple
/// `(name, min, max, mode, custom_value)`.
typedef ScalePref = ({
  String name,
  double min,
  double max,
  ScaleMode mode,
  double? custom,
});

/// A resolved optimisation target for one scale — the Dart shape of the
/// `{"type", "value", "lower", "upper"}` dicts `parse_scale_targets` returns.
typedef ScaleTarget = ({
  ScaleMode type,
  double value,
  double lower,
  double upper,
});

/// Coerce a TSV cell to an int the way `pd.to_numeric(errors="coerce")
/// .fillna(0)` does: unparsable cells become 0.
///
/// Twin of the private helper in `longitudinal.dart` and `report/session_pdf.dart`;
/// they collapse into one when the report builder is extracted.
int _coerceInt(String raw) {
  final v = double.tryParse(raw.trim());
  if (v == null || !v.isFinite) return 0;
  return v.truncate();
}

double _clip01(double v) => v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);

/// Parse a desktop mode string, including the `low`/`high` aliases that
/// `parse_scale_targets` accepts alongside `min`/`max`.
///
/// Unrecognised strings become [ScaleMode.ignore], which is also how the
/// desktop behaves in effect: `parse_scale_targets` writes no entry for them,
/// so they contribute nothing to a target lookup.
ScaleMode scaleModeFromString(String raw) => switch (raw.trim().toLowerCase()) {
      'low' || 'min' => ScaleMode.min,
      'high' || 'max' => ScaleMode.max,
      'custom' => ScaleMode.custom,
      _ => ScaleMode.ignore,
    };

/// Build a [ScalePref] from the raw strings a UI or TSV supplies, mirroring the
/// desktop's coercion: unparsable bounds become `0.0`, a blank or unparsable
/// custom value becomes `0.0`.
ScalePref scalePrefFromStrings({
  required String name,
  required String min,
  required String max,
  required String mode,
  String custom = '',
}) =>
    (
      name: name,
      min: double.tryParse(min.trim()) ?? 0.0,
      max: double.tryParse(max.trim()) ?? 0.0,
      mode: scaleModeFromString(mode),
      custom: double.tryParse(custom.trim()) ?? 0.0,
    );

/// Resolve [prefs] into per-scale targets keyed by scale name.
///
/// Port of `parse_scale_targets`. Bounds are swapped when `min > max`;
/// [ScaleMode.min] targets the lower bound, [ScaleMode.max] the upper, and
/// [ScaleMode.custom] the custom value (0.0 when absent). [ScaleMode.ignore]
/// yields **no entry**, which is what makes an ignored scale fall through to
/// the unknown-scale branch of [computeAggregateIndex].
Map<String, ScaleTarget> parseScaleTargets(List<ScalePref> prefs) {
  final targets = <String, ScaleTarget>{};
  for (final pref in prefs) {
    var lower = pref.min;
    var upper = pref.max;
    if (lower > upper) {
      final swap = lower;
      lower = upper;
      upper = swap;
    }
    switch (pref.mode) {
      case ScaleMode.min:
        targets[pref.name] =
            (type: ScaleMode.min, value: lower, lower: lower, upper: upper);
      case ScaleMode.max:
        targets[pref.name] =
            (type: ScaleMode.max, value: upper, lower: lower, upper: upper);
      case ScaleMode.custom:
        targets[pref.name] = (
          type: ScaleMode.custom,
          value: pref.custom ?? 0.0,
          lower: lower,
          upper: upper,
        );
      case ScaleMode.ignore:
        break;
    }
  }
  return targets;
}

/// Weighted aggregate index per x-point: 1.0 is best, 0.0 worst.
///
/// Port of `compute_aggregate_index`. Per point, every scale that has a value
/// there contributes a score:
/// - a scale **with** a target is normalised into `[lower, upper]` and scored
///   `1 - z` (min), `z` (max), or `1 - |v - target| / maxDistance` (custom), at
///   weight 1.0. A non-positive span, or a custom target equidistant from both
///   bounds, scores a flat 0.5;
/// - a scale **without** a target scores 0.5 at weight **0.5**.
///
/// Points where no scale has a value are absent from the result. [allPoints]
/// must be sorted — the returned map preserves that order, which
/// [findBestAndSecond] relies on to break ties the way Python does.
Map<int, double> computeAggregateIndex(
  Map<String, Map<int, double>> scaleData,
  List<int> allPoints,
  Map<String, ScaleTarget> targets,
) {
  final indexVals = <int, double>{};
  for (final pt in allPoints) {
    var weightedSum = 0.0;
    var totalWeight = 0.0;
    var any = false;

    for (final entry in scaleData.entries) {
      final value = entry.value[pt];
      if (value == null) continue;
      any = true;

      final target = targets[entry.key];
      if (target == null) {
        // Unknown scale: a neutral score at half weight.
        weightedSum += 0.5 * 0.5;
        totalWeight += 0.5;
        continue;
      }

      final denom = target.upper - target.lower;
      double score;
      if (denom <= 0) {
        score = 0.5;
      } else {
        final z = _clip01((value - target.lower) / denom);
        score = switch (target.type) {
          ScaleMode.min => 1.0 - z,
          ScaleMode.max => z,
          ScaleMode.custom => () {
              final maxDistance = [
                (target.value - target.lower).abs(),
                (target.upper - target.value).abs(),
              ].reduce((a, b) => a > b ? a : b);
              if (maxDistance <= 0) return 0.5;
              return 1.0 - _clip01((value - target.value).abs() / maxDistance);
            }(),
          ScaleMode.ignore => 0.5,
        };
      }
      weightedSum += score;
      totalWeight += 1.0;
    }

    if (!any) continue;
    indexVals[pt] = totalWeight > 0 ? weightedSum / totalWeight : 0.5;
  }
  return indexVals;
}

/// Overall `(min, max)` across every declared per-scale range, or null when
/// nothing is declared or the span collapses.
///
/// Port of `get_declared_scale_range`; used to clamp the chart's left y-axis.
(double, double)? declaredScaleRange(Map<String, ScaleTarget> targets) {
  if (targets.isEmpty) return null;
  var overallMin = double.infinity;
  var overallMax = double.negativeInfinity;
  for (final t in targets.values) {
    var lower = t.lower;
    var upper = t.upper;
    if (upper < lower) {
      final swap = lower;
      lower = upper;
      upper = swap;
    }
    if (lower < overallMin) overallMin = lower;
    if (upper > overallMax) overallMax = upper;
  }
  if (overallMax <= overallMin) return null;
  return (overallMin, overallMax);
}

/// The x-points with the best and second-best aggregate index.
///
/// Port of `find_best_and_second`. Python sorts with a **stable** sort, so ties
/// resolve by the key order of [indexVals] — which is why
/// [computeAggregateIndex] builds its map in sorted-point order. Dart's
/// `List.sort` is not stable, so the original index is used as an explicit
/// tie-breaker here.
(int?, int?) findBestAndSecond(Map<int, double> indexVals) {
  if (indexVals.isEmpty) return (null, null);
  final keys = indexVals.keys.toList();
  final ranked = List<int>.generate(keys.length, (i) => i)
    ..sort((a, b) {
      final cmp = indexVals[keys[b]]!.compareTo(indexVals[keys[a]]!);
      return cmp != 0 ? cmp : a.compareTo(b);
    });
  final best = keys[ranked[0]];
  final second = ranked.length > 1 ? keys[ranked[1]] : null;
  return (best, second);
}

/// Block IDs with the best and second-best raw scores, for the table's green
/// row shading.
///
/// Port of `_find_best_and_second_best_blocks`. Per block, every non-omitted
/// numeric scale value contributes to a running total by its mode: `min` adds
/// the value, `max` subtracts it, `custom` adds the absolute distance to the
/// target. **Lower total wins.** [ScaleMode.ignore] scales are skipped, and a
/// scale with no matching pref defaults to [ScaleMode.min] — the same default
/// the desktop applies via `pref_lookup.get(scale_name, ("min", ""))`.
///
/// Blocks with no usable value are excluded. Ties return every block at that
/// score, in block-encounter order.
///
/// The desktop reads its derived lateral table and filters to `laterality == "L"`
/// to avoid double-counting; the tablet has no laterality column, and each
/// lateral row pair shares one scale set, so the equivalent is the per-block
/// deduplicated (name, value) set built here.
({List<int> best, List<int> second}) findBestAndSecondBlocks(
  List<SessionRow> rows,
  List<ScalePref> prefs,
) {
  final lookup = <String, ScalePref>{
    for (final p in prefs) p.name.trim().toLowerCase(): p,
  };

  // Per block, the deduplicated non-omitted (name, value) pairs, in encounter
  // order — mirroring `_create_lateral_table_data`'s seen-set grouping.
  final blockPairs = <int, List<ScalePair>>{};
  final blockSeen = <int, Set<String>>{};
  for (final row in rows) {
    final blockId = _coerceInt(row.blockId);
    final pairs = blockPairs[blockId] ??= <ScalePair>[];
    final seen = blockSeen[blockId] ??= <String>{};
    for (final pair in splitScalePairs(row.scaleName, row.scaleValue)) {
      if (pair.name.isEmpty || isScaleValueOmitted(pair.value)) continue;
      if (seen.add('${pair.name}\u0000${pair.value}')) pairs.add(pair);
    }
  }

  final scores = <int, double>{};
  for (final entry in blockPairs.entries) {
    var total = 0.0;
    var hasValue = false;
    for (final pair in entry.value) {
      final value = double.tryParse(pair.value.trim());
      if (value == null || value.isNaN) continue;

      final pref = lookup[pair.name.trim().toLowerCase()];
      final mode = pref?.mode ?? ScaleMode.min;
      if (mode == ScaleMode.ignore) continue;
      hasValue = true;

      switch (mode) {
        case ScaleMode.min:
          total += value;
        case ScaleMode.max:
          total -= value;
        case ScaleMode.custom:
          total += (value - (pref?.custom ?? 0.0)).abs();
        case ScaleMode.ignore:
          break;
      }
    }
    if (hasValue) scores[entry.key] = total;
  }

  if (scores.isEmpty) return (best: const [], second: const []);

  final unique = scores.values.toSet().toList()..sort();
  List<int> at(double score) =>
      [for (final e in scores.entries) if (e.value == score) e.key];

  return (
    best: at(unique.first),
    second: unique.length > 1 ? at(unique[1]) : const [],
  );
}

/// Default preferences for every scale present in [rows]: mode
/// [ScaleMode.min], with bounds from [bounds] when the scale is listed there
/// and [fallback] otherwise.
///
/// This reproduces the desktop's out-of-the-box scoring without any UI: its
/// export dialog starts with every scale checked and "Min" selected
/// (`export_dialog.py`), i.e. `(name, min, max, "min", "")`.
///
/// [bounds] is supplied by the caller so this stays free of Flutter imports —
/// build it from the live session-scale editors, or from
/// `sessionRows(presets, preset)`; [fallback] is normally
/// `limits.sessionScale`.
List<ScalePref> defaultScalePrefsFor(
  Iterable<SessionRow> rows, {
  Map<String, (double, double)> bounds = const {},
  (double, double) fallback = (0.0, 10.0),
}) {
  final names = <String>[];
  final seen = <String>{};
  for (final row in rows) {
    for (final pair in splitScalePairs(row.scaleName, row.scaleValue)) {
      if (pair.name.isEmpty || isScaleValueOmitted(pair.value)) continue;
      if (seen.add(pair.name)) names.add(pair.name);
    }
  }
  return [
    for (final name in names)
      () {
        final (lo, hi) = bounds[name] ?? fallback;
        return (
          name: name,
          min: lo,
          max: hi,
          mode: ScaleMode.min,
          custom: null,
        );
      }(),
  ];
}
