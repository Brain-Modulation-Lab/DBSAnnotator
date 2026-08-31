/// Turns inserted session rows into the four stacked panels of the entry-review
/// figure: session scales, amplitude, pulse width and stimulation frequency.
///
/// Pure Dart — no Flutter — so the whole shape of the figure is unit-testable
/// without pumping a widget. The painter and the panel widget consume this.
///
/// ## Why blocks are the x axis
///
/// The x positions are **configurations** (blocks) in time order, evenly spaced,
/// and each tick is labelled with that block's clock time. Plotting against real
/// elapsed time instead would bunch a rapid titration into a few pixels and
/// stretch a coffee break across the panel, and "show the last 10
/// configurations" would stop being well defined. Even spacing keeps zoom and
/// horizontal scrolling meaningful; the time labels keep the axis readable as a
/// progression.
library;

import '../core/electrode/amplitude.dart';
import '../core/session/longitudinal.dart'
    show isScaleValueOmitted, splitScalePairs;
import '../core/session/scale_scoring.dart';
import '../core/session/session_row.dart';
import 'report_data.dart' show coerceInt;

/// One stacked panel: a title, its series, and the y range to draw.
///
/// [id] is stable across rebuilds and across app runs, so the user's panel
/// order can be persisted by id rather than by position.
typedef ParamPanel = ({
  String id,
  String title,
  Map<String, Map<int, double>> series,
  double yMin,
  double yMax,

  /// Set when every series in the panel held one value throughout, e.g.
  /// "90 µs, unchanged". The view then draws a single line with this as its
  /// label instead of a full plot: an invariant parameter needs a sentence, not
  /// a third of the figure, and `_padRange` used to draw a constant 90 dead
  /// centre of an 89-91 axis, which reads as a measured mid-range value.
  String? constantLabel,

  /// Series that are numerically identical to another in the same panel, e.g.
  /// Left exactly under Right. Without this the reader cannot tell whether both
  /// sides are plotted or one is missing.
  List<String> coincident,
});

/// Everything the four-panel figure needs, sharing one x domain so the panels
/// line up vertically.
typedef EntryChartData = ({
  /// Block IDs in time order — the x positions, evenly spaced.
  List<int> xs,

  /// Block ID -> "HH:MM" for the axis ticks.
  Map<int, String> xLabels,
  List<ParamPanel> panels,

  /// Blocks with the best and second-best aggregate index against the scale
  /// targets, for the green bands. Null when nothing was rated.
  int? bestX,
  int? secondX,
});

/// Canonical panel ids, also the default top-to-bottom order.
const List<String> kEntryPanelIds = ['scales', 'amplitude', 'pulseWidth', 'freq'];

/// Human titles per panel id, for a persisted order that no longer matches the
/// default list.
const Map<String, String> kEntryPanelTitles = {
  'scales': 'Session scales',
  'amplitude': 'Amplitude (mA)',
  'pulseWidth': 'Pulse width (µs)',
  'freq': 'Frequency (Hz)',
};

/// Trim a trailing ".0" so "90.0 us" reads as "90 us".
String _trim(double v) => v == v.roundToDouble()
    ? v.toStringAsFixed(0)
    : v.toString();

/// Sum a possibly-split amplitude cell ("1.5_1" -> 2.5). Null when unparsable.
///
/// Reuses [parseAmplitude] rather than re-splitting on '_' by hand, which is
/// what the report table still does in its own copy.
double? _amplitudeTotal(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  try {
    final parsed = parseAmplitude(text);
    return parsed.total;
  } on FormatException {
    return null;
  }
}

/// First numeric token, tolerating a unit suffix ("60 µs" -> 60).
double? _numeric(String raw) {
  final m = RegExp(r'[-+]?\d*\.?\d+').firstMatch(raw.trim());
  return m == null ? null : double.tryParse(m.group(0)!);
}

/// Pad a y range so markers do not sit exactly on the frame.
///
/// [zeroBased] anchors the bottom at 0, which is right for a magnitude: an
/// amplitude axis that starts at 4.4 makes a 5.5 -> 4.5 mA step occupy a third
/// of the panel and read as a collapse.
(double, double) _padRange(double lo, double hi, {bool zeroBased = false}) {
  if (!lo.isFinite || !hi.isFinite) return (0, 1);
  if (lo == hi) return zeroBased ? (0, hi + 1) : (lo - 1, hi + 1);
  final margin = (hi - lo) * 0.12;
  return (zeroBased ? 0 : lo - margin, hi + margin);
}

/// The single value every series in [maps] holds, or null when anything varies
/// or nothing was recorded.
double? _constantOf(Iterable<Map<int, double>> maps) {
  double? only;
  for (final m in maps) {
    for (final v in m.values) {
      if (only == null) {
        only = v;
      } else if ((v - only).abs() > 1e-9) {
        return null;
      }
    }
  }
  return only;
}

/// Names in [series] whose values duplicate an earlier series exactly.
List<String> _coincidentSeries(Map<String, Map<int, double>> series) {
  final out = <String>[];
  final seen = <String, String>{};
  for (final e in series.entries) {
    final key = (e.value.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
        .map((p) => '${p.key}:${p.value}')
        .join(',');
    if (key.isEmpty) continue;
    final first = seen[key];
    if (first != null) {
      out.add(e.key);
    } else {
      seen[key] = e.key;
    }
  }
  return out;
}

/// Build the four panels from [rows].
///
/// Only recording rows are plotted (`is_initial != 1`): the baseline block is
/// the pre-session state, not a tested configuration.
///
/// [scalePrefs] carries the scale bounds AND the optimisation mode per scale, so
/// one input drives both the scales panel's y axis (the range the user declared
/// in Step 2, rather than auto-fitting to whatever happens to be recorded) and
/// the aggregate index behind the green best/second bands. When it is empty the
/// axis auto-fits and no block is banded.
EntryChartData buildEntryChartData(
  List<SessionRow> rows, {
  List<ScalePref> scalePrefs = const [],
}) {
  final targets = parseScaleTargets(scalePrefs);
  final scaleBounds = <String, (double, double)>{
    for (final t in targets.entries) t.key: (t.value.lower, t.value.upper),
  };
  // Blocks in first-seen order, with the earliest timestamp for each.
  final blockOrder = <int>[];
  final blockTime = <int, DateTime>{};
  final scales = <String, Map<int, double>>{};
  final ampL = <int, double>{};
  final ampR = <int, double>{};
  final pwL = <int, double>{};
  final pwR = <int, double>{};
  final freqL = <int, double>{};
  final freqR = <int, double>{};

  for (final row in rows) {
    if (coerceInt(row.isInitial) == 1) continue;
    final block = coerceInt(row.blockId);
    if (!blockTime.containsKey(block)) blockOrder.add(block);
    final ts = row.timestamp;
    if (ts != null) {
      final existing = blockTime[block];
      if (existing == null || ts.isBefore(existing)) blockTime[block] = ts;
    }

    for (final pair in splitScalePairs(row.scaleName, row.scaleValue)) {
      if (pair.name.isEmpty || isScaleValueOmitted(pair.value)) continue;
      final v = double.tryParse(pair.value.trim());
      if (v == null || !v.isFinite) continue;
      (scales[pair.name] ??= <int, double>{})[block] = v;
    }

    void put(Map<int, double> into, double? v) {
      if (v != null && v.isFinite) into[block] = v;
    }

    put(ampL, _amplitudeTotal(row.leftAmplitude));
    put(ampR, _amplitudeTotal(row.rightAmplitude));
    put(pwL, _numeric(row.leftPulseWidth));
    put(pwR, _numeric(row.rightPulseWidth));
    put(freqL, _numeric(row.leftStimFreq));
    put(freqR, _numeric(row.rightStimFreq));
  }

  // Time order, falling back to block id for rows with no parseable stamp so
  // the axis is always deterministic.
  blockOrder.sort((a, b) {
    final ta = blockTime[a];
    final tb = blockTime[b];
    if (ta != null && tb != null) {
      final c = ta.compareTo(tb);
      if (c != 0) return c;
    } else if (ta != null) {
      return -1;
    } else if (tb != null) {
      return 1;
    }
    return a.compareTo(b);
  });

  String two(int n) => n.toString().padLeft(2, '0');
  final xLabels = <int, String>{
    for (final b in blockOrder)
      if (blockTime[b] != null)
        b: '${two(blockTime[b]!.hour)}:${two(blockTime[b]!.minute)}',
  };

  /// y range over every series in a panel.
  (double, double) rangeOf(Iterable<Map<int, double>> maps,
      {bool zeroBased = false}) {
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (final m in maps) {
      for (final v in m.values) {
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    return _padRange(lo, hi, zeroBased: zeroBased);
  }

  // Session scales: prefer the declared bounds, so the panel matches the
  // sliders the user actually configured.
  var scalesLo = double.infinity;
  var scalesHi = double.negativeInfinity;
  for (final name in scales.keys) {
    final bounds = scaleBounds[name];
    if (bounds == null) continue;
    if (bounds.$1 < scalesLo) scalesLo = bounds.$1;
    if (bounds.$2 > scalesHi) scalesHi = bounds.$2;
  }
  final scalesRange = scalesHi > scalesLo
      ? (scalesLo, scalesHi)
      : rangeOf(scales.values);

  ParamPanel panel(String id, Map<String, Map<int, double>> series,
      (double, double) range, {String unit = ''}) {
    // Drop empty series so an unused side does not claim a legend slot.
    final used = <String, Map<int, double>>{
      for (final e in series.entries)
        if (e.value.isNotEmpty) e.key: e.value,
    };
    final constant = _constantOf(used.values);
    return (
      id: id,
      title: kEntryPanelTitles[id]!,
      series: used,
      yMin: range.$1,
      yMax: range.$2,
      constantLabel: constant == null || used.isEmpty
          ? null
          : '${_trim(constant)}${unit.isEmpty ? '' : ' $unit'}, unchanged'
              '${used.length > 1 ? ' (both sides)' : ''}',
      coincident: _coincidentSeries(used),
    );
  }

  final (bestX, secondX) =
      findBestAndSecond(computeAggregateIndex(scales, blockOrder, targets));

  return (
    xs: blockOrder,
    xLabels: xLabels,
    bestX: targets.isEmpty ? null : bestX,
    secondX: targets.isEmpty ? null : secondX,
    panels: [
      panel('scales', scales, scalesRange),
      // Dose is a magnitude, so its axis starts at zero: an amplitude panel
      // spanning 4.4-7.4 makes 5.5 -> 4.5 mA look like a collapse.
      panel('amplitude', {'Left': ampL, 'Right': ampR},
          rangeOf([ampL, ampR], zeroBased: true), unit: 'mA'),
      panel('pulseWidth', {'Left': pwL, 'Right': pwR}, rangeOf([pwL, pwR]),
          unit: 'µs'),
      panel('freq', {'Left': freqL, 'Right': freqR}, rangeOf([freqL, freqR]),
          unit: 'Hz'),
    ],
  );
}

/// Reorder [panels] to match a persisted list of ids.
///
/// Unknown ids are ignored and missing ones appended in their default order, so
/// a stale preference (from an older version, or a hand-edited file) degrades to
/// a sensible order instead of losing a panel.
List<ParamPanel> orderPanels(List<ParamPanel> panels, List<String>? order) {
  if (order == null || order.isEmpty) return panels;
  final byId = {for (final p in panels) p.id: p};
  final out = <ParamPanel>[];
  for (final id in order) {
    final p = byId.remove(id);
    if (p != null) out.add(p);
  }
  out.addAll(panels.where((p) => byId.containsKey(p.id)));
  return out;
}
