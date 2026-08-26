/// Pure computation shared by the session report builders (PDF + Word).
///
/// Turns already-parsed [SessionRow]s into the sections both reports render —
/// header date, initial clinical notes, the lateral session-data table, the
/// electrode-configuration tokens, and the programming summary — so the two
/// output formats stay byte-for-byte consistent with each other and with the
/// desktop's `session_exporter.py`. No widgets, no platform channels: fully
/// headless-testable.
library;

import '../core/session/longitudinal.dart'
    show isScaleValueOmitted, scaleTimeline, splitScalePairs;
import '../core/session/scale_scoring.dart';
import '../core/session/session_row.dart';

typedef ScalePair = ({String name, String value});

/// Anode / cathode token strings for both leads of one configuration.
typedef LateralTokens = ({
  String leftAnode,
  String leftCathode,
  String rightAnode,
  String rightCathode,
});

/// Coerce a TSV cell to an int the way `pd.to_numeric(errors="coerce")
/// .fillna(0)` does: unparsable cells become 0.
int coerceInt(String raw) {
  final v = double.tryParse(raw.trim());
  if (v == null || !v.isFinite) return 0;
  return v.truncate();
}

/// Desktop-identical number trimming: f"{x:.2f}".rstrip("0").rstrip(".").
String _trimZeros(double v) {
  var out = v.toStringAsFixed(2);
  while (out.endsWith('0')) {
    out = out.substring(0, out.length - 1);
  }
  if (out.endsWith('.')) out = out.substring(0, out.length - 1);
  return out;
}

/// The row with the highest session_ID, then highest block_ID (last on
/// ties). Mirrors `_pick_latest_session_row` + `_pick_latest_row`.
SessionRow? _latestRow(List<SessionRow> rows) {
  if (rows.isEmpty) return null;
  var best = rows.first;
  for (final row in rows.skip(1)) {
    final s = coerceInt(row.sessionId).compareTo(coerceInt(best.sessionId));
    if (s > 0 ||
        (s == 0 && coerceInt(row.blockId) >= coerceInt(best.blockId))) {
      best = row;
    }
  }
  return best;
}

/// Separator no TSV cell can contain (tab is the field delimiter), so the
/// dedup key keeps "AB"+"C" distinct from "A"+"BC".
final String _sep = String.fromCharCode(31);

/// Deduplicated (name, value) scale pairs over [rows], skipping blank names
/// and omitted values. Mirrors the seen-set loops in `_add_summary_section`
/// and `_create_lateral_table_data`.
List<ScalePair> _collectScalePairs(Iterable<SessionRow> rows) {
  final seen = <String>{};
  final pairs = <ScalePair>[];
  for (final row in rows) {
    for (final pair in splitScalePairs(row.scaleName, row.scaleValue)) {
      if (pair.name.isEmpty || isScaleValueOmitted(pair.value)) continue;
      if (seen.add('${pair.name}$_sep${pair.value}')) pairs.add(pair);
    }
  }
  return pairs;
}

/// Min/max over a parameter column, mirroring the desktop `_param_range`:
/// blank cells are skipped; with [splitSum] a split amplitude like "1.5_1"
/// counts as its SUM (2.5); otherwise the first numeric token is used, which
/// tolerates units ("60 µs" -> 60). Null when no cell parses.
(double, double)? _paramRange(Iterable<String> raws, {bool splitSum = false}) {
  final numToken = RegExp(r'[-+]?\d*\.?\d+');
  final vals = <double>[];
  for (final raw in raws) {
    final text = raw.trim();
    if (text.isEmpty) continue;
    if (splitSum && text.contains('_')) {
      final parts = text
          .split('_')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .map(double.tryParse)
          .toList();
      if (parts.isNotEmpty && !parts.contains(null)) {
        vals.add(parts.fold(0.0, (a, b) => a + b!));
        continue;
      }
    }
    final m = numToken.firstMatch(text);
    if (m == null) continue;
    final v = double.tryParse(m.group(0)!);
    if (v != null) vals.add(v);
  }
  if (vals.isEmpty) return null;
  vals.sort();
  return (vals.first, vals.last);
}

/// Format a [_paramRange] result like the desktop: "N/A", a single value, or
/// "lo - hi", each with [digits] decimals and the [unit] appended.
String _rangeText((double, double)? r, String unit, int digits) {
  if (r == null) return 'N/A';
  final (lo, hi) = r;
  if (lo == hi) return '${lo.toStringAsFixed(digits)} $unit';
  return '${lo.toStringAsFixed(digits)} - ${hi.toStringAsFixed(digits)} $unit';
}

/// Session duration "Xh Ymin" / "X min" / "N/A" from the rows' date+time
/// stamps (max - min), mirroring `_add_programming_summary`.
String _durationText(List<SessionRow> rows) {
  final stamps = <DateTime>[];
  for (final row in rows) {
    final dt = DateTime.tryParse('${row.date.trim()} ${row.time.trim()}');
    if (dt != null) stamps.add(dt);
  }
  if (stamps.length < 2) return 'N/A';
  stamps.sort();
  final totalMins = stamps.last.difference(stamps.first).inMinutes;
  if (totalMins >= 60) return '${totalMins ~/ 60}h ${totalMins % 60}min';
  return '$totalMins min';
}

/// Table cell for an amplitude: a split value like "1.5_1" is stacked with
/// its total ("1.5\n1\n= 2.5"), like the desktop table; anything else is
/// shown verbatim.
String _amplitudeCell(String raw) {
  final text = raw.trim();
  if (!text.contains('_')) return text;
  final parts = text
      .split('_')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  final values = parts.map(double.tryParse).toList();
  if (values.isEmpty || values.contains(null)) return text;
  final total = values.fold(0.0, (a, b) => a + b!);
  return '${parts.join('\n')}\n= ${_trimZeros(total)}';
}

/// Frequency / pulse-width cell: integer-valued numbers lose the ".0",
/// everything else (including unit-bearing text) is verbatim.
String _numCell(String raw) {
  final text = raw.trim();
  final v = double.tryParse(text);
  if (v != null && v == v.roundToDouble()) return '${v.toInt()}';
  return text;
}

/// "name: value" lines for a block's scales.
String _scalesCell(Iterable<SessionRow> rows) =>
    _collectScalePairs(rows).map((p) => '${p.name}: ${p.value}').join('\n');

/// Column headers for the lateral session-data table (shared by both reports).
const sessionTableHeaders = [
  'Block',
  'Side',
  'Prog',
  'Freq (Hz)',
  '+',
  '-',
  'Amp (mA)',
  'PW (µs)',
  'Scales',
  'Notes',
];

/// Green fills for the best / second-best ranking, as ARGB ints. Same pair the
/// desktop uses for both the chart bands and the table row shading
/// (`report_chart_utils.py:28-29`, `report_common.py:205`).
const int kBestFill = 0xFF96D2A0;
const int kSecondFill = 0xFFC8EBCD;

/// The disclaimer printed under the session-data table, verbatim from the
/// desktop (`report_common.add_table_legend`). It is a clinical-liability
/// statement, so the wording is deliberately not paraphrased, and it is shared
/// so both report formats carry it identically.
const kRankingDisclaimer =
    'Note: The highlighted rows are derived exclusively from the recorded '
    'session scale values and represent a computational ranking intended '
    'solely as a reference. This color-coded indication does not constitute '
    'clinical guidance.';

/// Everything needed to draw the scales-timeline chart, computed from the rows
/// so the PDF and Word renderers share one source of truth.
///
/// Mirrors the desktop `build_scales_chart` inputs
/// (`src/dbs_annotator/utils/report_chart_utils.py:216`).
class ScalesChartSpec {
  const ScalesChartSpec({
    required this.series,
    required this.xs,
    required this.yMin,
    required this.yMax,
    required this.aggregateIndex,
    required this.bestX,
    required this.secondX,
    required this.title,
    required this.xLabel,
    required this.yLabel,
  });

  /// One entry per scale, in encounter order: name -> {x -> value}. Missing x
  /// values are absent, which the painter renders as a break in the line.
  final Map<String, Map<int, double>> series;

  /// Sorted x positions (block IDs) present in any series.
  final List<int> xs;

  /// Left-axis bounds. Clamped to the union of declared scale ranges when the
  /// prefs supply one, else auto-fitted to the data.
  final double yMin, yMax;

  /// Aggregate index per x, on a fixed 0..1 right axis. Empty when the desktop
  /// would not draw it (fewer than two scales).
  final Map<int, double> aggregateIndex;

  /// x positions of the best / second-best block, for the green bands. Null
  /// when there is no index to rank by.
  final int? bestX, secondX;

  final String title, xLabel, yLabel;

  /// Nothing to draw.
  bool get isEmpty => series.isEmpty || xs.isEmpty;
}

/// Everything the report builders need, computed once from the raw rows.
class SessionReportData {
  const SessionReportData({
    required this.date,
    required this.hasInitial,
    required this.initScales,
    required this.initNotes,
    required this.tableData,
    required this.electrodeModel,
    required this.hasElectrodeConfig,
    required this.initialTokens,
    required this.finalTokens,
    required this.hasRows,
    required this.duration,
    required this.numConfigs,
    required this.ampL,
    required this.ampR,
    required this.freqL,
    required this.freqR,
    required this.pwL,
    required this.pwR,
    required this.timeline,
    required this.chart,
    required this.bestBlocks,
    required this.secondBlocks,
    required this.targetsText,
    required this.initialRow,
    required this.finalRow,
  });

  /// Generated-on / session date, "yyyy-MM-dd".
  final String date;

  /// Whether any baseline (is_initial == 1) row exists.
  final bool hasInitial;

  /// Deduplicated baseline scales (latest initial session).
  final List<ScalePair> initScales;

  /// Latest baseline notes (may be empty).
  final String initNotes;

  /// Lateral table rows (two rows — L then R — per recording block); uses
  /// [sessionTableHeaders]. Cells may contain '\n' for stacked values.
  final List<List<String>> tableData;

  /// Electrode model label (first non-empty of initial/final), may be empty.
  final String electrodeModel;

  /// Whether any electrode configuration (initial or final) exists.
  final bool hasElectrodeConfig;

  /// Initial / final anode-cathode tokens for the text fallback (null when
  /// that configuration is absent).
  final LateralTokens? initialTokens;
  final LateralTokens? finalTokens;

  /// Whether there is any session data at all (for the summary section).
  final bool hasRows;

  /// Programming-summary fields (desktop `_add_programming_summary`).
  final String duration;
  final int numConfigs;
  final String ampL, ampR, freqL, freqR, pwL, pwR;

  /// scale -> {block -> value} for the scales-timeline graph.
  final Map<String, Map<int, double>> timeline;

  /// Everything needed to draw the scales chart, ready for the shared painter.
  final ScalesChartSpec chart;

  /// Block IDs to shade green in the session-data table. Note these come from
  /// a *different* algorithm than the chart's [ScalesChartSpec.bestX] — the
  /// desktop deliberately uses signed raw sums for the table and a normalised
  /// weighted index for the chart, and they can disagree. See
  /// `core/session/scale_scoring.dart`.
  final List<int> bestBlocks, secondBlocks;

  /// "Scale targets: name: min; other: max" for the table legend block, or ''
  /// when no scale has an active optimisation mode.
  final String targetsText;

  /// The rows the electrode configuration was taken from, so the caller can
  /// render images of exactly the configurations the text describes.
  final SessionRow? initialRow, finalRow;

  /// True when there are recording blocks to tabulate.
  bool get hasRecording => tableData.isNotEmpty;
}

/// Build the scales-chart spec, applying the same target/index/ranking rules as
/// the desktop chart (`report_chart_utils.build_scales_chart`).
ScalesChartSpec buildScalesChartSpec({
  required Map<String, Map<int, double>> timeline,
  required List<ScalePref> prefs,
  String title = 'Session Scales Timeline',
  String xLabel = 'Block',
  String yLabel = 'Scale Value',
}) {
  final xs = <int>{};
  var dataMin = double.infinity;
  var dataMax = double.negativeInfinity;
  for (final byX in timeline.values) {
    for (final e in byX.entries) {
      xs.add(e.key);
      if (e.value < dataMin) dataMin = e.value;
      if (e.value > dataMax) dataMax = e.value;
    }
  }
  final sortedXs = xs.toList()..sort();

  final targets = parseScaleTargets(prefs);

  // Left axis: prefer the union of declared ranges (desktop
  // `get_declared_scale_range`), else fit the data, widening a flat series so
  // the axis always has height.
  var yMin = dataMin;
  var yMax = dataMax;
  final declared = declaredScaleRange(targets);
  if (declared != null) {
    (yMin, yMax) = declared;
  } else if (!dataMin.isFinite || dataMin == dataMax) {
    yMin = dataMin.isFinite ? dataMin - 1 : 0;
    yMax = dataMax.isFinite ? dataMax + 1 : 1;
  }

  // The desktop only draws the index (and therefore the bands) with >= 2
  // scales — a single-scale index would just restate that scale.
  final index = timeline.length >= 2
      ? computeAggregateIndex(timeline, sortedXs, targets)
      : const <int, double>{};
  final (bestX, secondX) = findBestAndSecond(index);

  return ScalesChartSpec(
    series: timeline,
    xs: sortedXs,
    yMin: yMin,
    yMax: yMax,
    aggregateIndex: index,
    bestX: bestX,
    secondX: secondX,
    title: title,
    xLabel: xLabel,
    yLabel: yLabel,
  );
}

/// "name: min; other: max; third: 4.5" for the table legend, or '' when every
/// scale is ignored. Mirrors the targets line in `report_common.add_table_legend`.
String _targetsText(List<ScalePref> prefs) {
  final parts = <String>[];
  for (final p in prefs) {
    switch (p.mode) {
      case ScaleMode.min:
        parts.add('${p.name}: min');
      case ScaleMode.max:
        parts.add('${p.name}: max');
      case ScaleMode.custom:
        parts.add('${p.name}: ${p.custom ?? 0}');
      case ScaleMode.ignore:
        break;
    }
  }
  return parts.join('; ');
}

/// Compute all report sections from the session [rows].
///
/// [scalePrefs] carries the per-scale optimisation modes and bounds that drive
/// the chart's aggregate index, its green bands and the table's row shading.
/// When omitted they default to [defaultScalePrefsFor], which reproduces the
/// desktop export dialog's initial state (every scale included, "min" mode) —
/// so a TSV opened from elsewhere still gets the same ranking the desktop would
/// give it out of the box.
SessionReportData buildSessionReportData({
  required List<SessionRow> rows,
  DateTime? generatedAt,
  List<ScalePref>? scalePrefs,
}) {
  final dt = generatedAt ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final date = '${dt.year}-${two(dt.month)}-${two(dt.day)}';

  // Split like the desktop: is_initial coerced == 1 -> baseline (Step 1),
  // everything else -> recording blocks (the session-data table).
  final initialRows = rows.where((r) => coerceInt(r.isInitial) == 1).toList();
  final recordingRows =
      rows.where((r) => coerceInt(r.isInitial) != 1).toList();

  // Initial clinical notes come from the LATEST initial session only.
  final latestInit = _latestRow(initialRows);
  final initSessionRows = latestInit == null
      ? const <SessionRow>[]
      : initialRows
          .where((r) =>
              coerceInt(r.sessionId) == coerceInt(latestInit.sessionId))
          .toList();
  final initScales = _collectScalePairs(initSessionRows);
  final initNotes = latestInit?.notes.trim() ?? '';

  // Recording rows grouped by (coerced) block_ID in encounter order.
  final blocks = <int, List<SessionRow>>{};
  for (final row in recordingRows) {
    (blocks[coerceInt(row.blockId)] ??= []).add(row);
  }

  // Programming summary over ALL rows (desktop uses the full DataFrame).
  final duration = _durationText(rows);
  final numConfigs = rows.map((r) => coerceInt(r.blockId)).toSet().length;
  final ampL = _rangeText(
      _paramRange(rows.map((r) => r.leftAmplitude), splitSum: true), 'mA', 1);
  final ampR = _rangeText(
      _paramRange(rows.map((r) => r.rightAmplitude), splitSum: true), 'mA', 1);
  final freqL =
      _rangeText(_paramRange(rows.map((r) => r.leftStimFreq)), 'Hz', 0);
  final freqR =
      _rangeText(_paramRange(rows.map((r) => r.rightStimFreq)), 'Hz', 0);
  final pwL =
      _rangeText(_paramRange(rows.map((r) => r.leftPulseWidth)), 'µs', 0);
  final pwR =
      _rangeText(_paramRange(rows.map((r) => r.rightPulseWidth)), 'µs', 0);

  // Electrode configuration: latest baseline row = initial settings, latest
  // recording row = final settings.
  final latestFinal = _latestRow(recordingRows);
  final electrodeModel = [
    latestInit?.electrodeModel.trim() ?? '',
    latestFinal?.electrodeModel.trim() ?? '',
  ].firstWhere((m) => m.isNotEmpty, orElse: () => '');

  LateralTokens? tokensOf(SessionRow? r) => r == null
      ? null
      : (
          leftAnode: r.leftAnode,
          leftCathode: r.leftCathode,
          rightAnode: r.rightAnode,
          rightCathode: r.rightCathode,
        );

  // Lateral session-data table: two rows (L / R) per block.
  final tableData = <List<String>>[];
  for (final entry in blocks.entries) {
    final first = entry.value.first;
    final scales = _scalesCell(entry.value);
    tableData.add([
      '${entry.key}',
      'L',
      first.programId,
      _numCell(first.leftStimFreq),
      first.leftAnode,
      first.leftCathode.replaceAll('_', '\n'),
      _amplitudeCell(first.leftAmplitude),
      _numCell(first.leftPulseWidth),
      scales,
      first.notes,
    ]);
    tableData.add([
      '${entry.key}',
      'R',
      first.programId,
      _numCell(first.rightStimFreq),
      first.rightAnode,
      first.rightCathode.replaceAll('_', '\n'),
      _amplitudeCell(first.rightAmplitude),
      _numCell(first.rightPulseWidth),
      scales,
      first.notes,
    ]);
  }

  // Optimisation prefs drive the chart's index/bands and the table's shading.
  // Built from the RECORDING rows only: these are the session scales the
  // desktop ranks (`scale_optimization_prefs`), and including the baseline
  // clinical scales would list them as targets in the legend too. Bounds are
  // unknown for an externally-authored TSV, so fall back to the desktop's
  // default 0..10 session-scale range.
  final prefs = scalePrefs ?? defaultScalePrefsFor(recordingRows);
  final timeline = scaleTimeline(rows);
  final ranking = findBestAndSecondBlocks(recordingRows, prefs);

  return SessionReportData(
    date: date,
    chart: buildScalesChartSpec(timeline: timeline, prefs: prefs),
    bestBlocks: ranking.best,
    secondBlocks: ranking.second,
    targetsText: _targetsText(prefs),
    initialRow: latestInit,
    finalRow: latestFinal,
    hasInitial: latestInit != null,
    initScales: initScales,
    initNotes: initNotes,
    tableData: tableData,
    electrodeModel: electrodeModel,
    hasElectrodeConfig: latestInit != null || latestFinal != null,
    initialTokens: tokensOf(latestInit),
    finalTokens: tokensOf(latestFinal),
    hasRows: rows.isNotEmpty,
    duration: duration,
    numConfigs: numConfigs,
    ampL: ampL,
    ampR: ampR,
    freqL: freqL,
    freqR: freqR,
    pwL: pwL,
    pwR: pwR,
    timeline: timeline,
  );
}
