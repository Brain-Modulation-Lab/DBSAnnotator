/// Pure computation shared by the session report builders (PDF + Word).
///
/// Turns already-parsed [SessionRow]s into the sections both reports render —
/// header date, initial clinical notes, the lateral session-data table, the
/// electrode-configuration tokens, and the programming summary — so the two
/// output formats stay byte-for-byte consistent with each other and with the
/// desktop's `session_exporter.py`. No widgets, no platform channels: fully
/// headless-testable.
library;

import 'dart:typed_data';

import '../core/session/longitudinal.dart'
    show isScaleValueOmitted, scaleTimeline, splitScalePairs;
import '../core/session/scale_scoring.dart';
import '../core/session/session_row.dart';

typedef ScalePair = ({String name, String value});

/// Anode / cathode token strings for both leads of one configuration.
/// The amplitudes travel with the tokens because a contact list without its
/// current is not a configuration: `2b 2c` says nothing about whether the
/// steering was 3.3/2.2 or the reverse, and the two behave nothing alike. Both
/// builders' per-lead captions render through [contactsWithCurrent], which needs
/// the pair.
typedef LateralTokens = ({
  String leftAnode,
  String leftCathode,
  String leftAmplitude,
  String rightAnode,
  String rightCathode,
  String rightAmplitude,
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

/// Consecutive integers collapsed: [1,2,3,5] -> "1-3, 5".
String _blockRuns(List<int> blocks) {
  if (blocks.isEmpty) return '';
  final sorted = blocks.toList()..sort();
  final runs = <String>[];
  var start = sorted.first;
  var prev = sorted.first;
  for (final b in sorted.skip(1)) {
    if (b == prev + 1) {
      prev = b;
      continue;
    }
    runs.add(start == prev ? '$start' : '$start-$prev');
    start = b;
    prev = b;
  }
  runs.add(start == prev ? '$start' : '$start-$prev');
  return runs.join(', ');
}

/// The distinct values a parameter took, with the blocks that carried each:
/// `5.5 mA (blocks 1-5), 4.5 mA (blocks 6-7)`, or `125 Hz (unchanged)`.
///
/// Replaces the desktop's min-max "range", which implied a titration that never
/// happened — the example swept nothing, it used two amplitudes — and which
/// reduced an unchanged parameter to the degenerate `L: 125 Hz | R: 125 Hz`.
/// It also silently equated a monopolar 7.0 mA with 7.0 mA split three ways,
/// radically different volumes of tissue activated.
String _valuesText(
  Map<int, List<SessionRow>> blocks,
  String Function(SessionRow) pick,
  String unit,
  int digits, {
  bool splitSum = false,
}) {
  // Value -> the blocks that used it, in block order.
  final byValue = <String, List<int>>{};
  for (final entry in blocks.entries) {
    final r = _paramRange([pick(entry.value.first)], splitSum: splitSum);
    if (r == null) continue;
    final key = r.$1.toStringAsFixed(digits);
    (byValue[key] ??= []).add(entry.key);
  }
  if (byValue.isEmpty) return 'N/A';
  if (byValue.length == 1) return '${byValue.keys.first} $unit (unchanged)';
  return byValue.entries
      .map((e) => '${e.key} $unit (block${e.value.length == 1 ? '' : 's'} '
          '${_blockRuns(e.value)})')
      .join(', ');
}


/// The UTC offset the rows were recorded at, e.g. "+02:00", or ''.
///
/// The `timezone` column holds a Windows display name followed by an offset —
/// `W. Europe Daylight Time +0200` — so only the offset half is portable. A
/// clinical timestamp with no zone is ambiguous by up to a day either side of
/// midnight, and across a DST boundary two sessions cannot be ordered.
String _utcOffset(Iterable<SessionRow> rows) {
  for (final row in rows) {
    final m = RegExp(r'([+-])(\d{2}):?(\d{2})').firstMatch(row.timezone);
    if (m != null) return '${m.group(1)}${m.group(2)}:${m.group(3)}';
  }
  return '';
}

/// Every parseable date+time stamp in [rows], ascending.
///
/// Rows are minted as `yyyy-MM-dd` + `HH:mm:ss` (`core/session/session_file`),
/// so `DateTime.tryParse` of the two joined works.
List<DateTime> _stamps(Iterable<SessionRow> rows) {
  final out = <DateTime>[];
  for (final row in rows) {
    final dt = DateTime.tryParse('${row.date.trim()} ${row.time.trim()}');
    if (dt != null) out.add(dt);
  }
  out.sort();
  return out;
}

/// Span from the first to the last entry, "Xh Ymin" / "X min" / "N/A".
///
/// This is NOT the session's clinical duration and the label says so: it
/// measures the time between the first and last annotation, which is all the
/// data supports.
String _spanText(List<SessionRow> rows) {
  final stamps = _stamps(rows);
  if (stamps.length < 2) return 'N/A';
  final totalMins = stamps.last.difference(stamps.first).inMinutes;
  if (totalMins >= 60) return '${totalMins ~/ 60}h ${totalMins % 60}min';
  return '$totalMins min';
}

/// "+35 s" / "+2 min" / "" — the gap between two blocks.
///
/// A rating taken seconds after a parameter change measures an acute response
/// only. In the worked example two "different" configurations are 9 s apart on
/// identical settings; printing the interval is what lets a reader see it.
String _gapText(DateTime? previous, DateTime? current) {
  if (previous == null || current == null) return '';
  final secs = current.difference(previous).inSeconds;
  if (secs <= 0) return '';
  if (secs < 90) return '+$secs s';
  return '+${(secs / 60).round()} min';
}

/// The stimulation columns that define a configuration. Two blocks with the
/// same tuple were the same setting, however many times they were rated.
List<String> _paramKey(SessionRow r) => [
      r.leftStimFreq.trim(),
      r.leftAmplitude.trim(),
      r.leftPulseWidth.trim(),
      r.leftAnode.trim(),
      r.leftCathode.trim(),
      r.rightStimFreq.trim(),
      r.rightAmplitude.trim(),
      r.rightPulseWidth.trim(),
      r.rightAnode.trim(),
      r.rightCathode.trim(),
    ];

/// Table cell for an amplitude: always the TOTAL delivered current, at the
/// device's own resolution of 0.1 mA.
///
/// Two fixes in one line. A split like `1.67_1.67_1.66` used to be stacked over
/// its own sum, so every row stated the amplitude twice — once here and once
/// inside the contact cell — in two different notations; the share-out now
/// lives in the contact column as percentages, leaving one number here.
///
/// And that number is rounded to a tenth. Files written before
/// [encodeAmplitude] was fixed hold independently-rounded parts, so a 5.0 mA
/// setting is stored as `1.67_1.67_1.67` and sums to **5.01** — printing that
/// asserts a precision no IPG has (the amplitude presets step in tenths). 5.0
/// is both the honest resolution and what was actually set.
String _amplitudeCell(String raw) {
  final text = raw.trim();
  if (!text.contains('_')) return text;
  final parts = _amplitudeParts(text);
  if (parts == null) return text;
  return parts.fold(0.0, (a, b) => a + b).toStringAsFixed(1);
}

/// Frequency / pulse-width cell: integer-valued numbers lose the ".0",
/// everything else (including unit-bearing text) is verbatim.
String _numCell(String raw) {
  final text = raw.trim();
  final v = double.tryParse(text);
  if (v != null && v == v.roundToDouble()) return '${v.toInt()}';
  return text;
}

/// Vendor-style contact list: `2b(60%) 2c(40%)` for a steered configuration,
/// or plain `case` / `2b` when there is nothing to share out.
///
/// Three internal conventions are dropped here, all misreading hazards in a
/// printed clinical document:
/// - the `E` prefix (vendors write `2b`, not `E2b`);
/// - the `_` join — `3.3_2.2` under an "Amp (mA)" heading reads as one number;
/// - the per-contact **milliamp** figures.
///
/// The last is the interesting choice. What the split widget captures is a
/// PERCENTAGE per contact; the stored milliamps are that percentage multiplied
/// out and rounded to hundredths, so printing them showed derived, rounded
/// numbers (`1.67 1.67 1.66`) in place of the thing the clinician actually set.
/// Percentages say the same thing exactly, in the vendors' own idiom, and the
/// dose is then stated once as `= 5.5 mA` instead of being smeared across the
/// row. For current steering the split IS the configuration: `2b 60% / 2c 40%`
/// behaves nothing like the reverse.
///
/// A single contact gets no parenthetical, because "100%" is noise.
String contactsWithCurrent(String tokens, String amplitude) {
  final contacts = tokens
      .split('_')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .map((t) => t.toLowerCase() == 'case'
          ? 'case'
          : (t.startsWith('E') || t.startsWith('e') ? t.substring(1) : t))
      .toList();
  if (contacts.isEmpty) return '';
  if (contacts.length == 1) return contacts.first;

  final split = _amplitudeParts(amplitude);
  // Only share out when the counts agree: a mismatch means we cannot know which
  // share went to which contact, and guessing is worse than the contacts alone.
  if (split == null || split.length != contacts.length) {
    return contacts.join(' ');
  }
  final total = split.fold(0.0, (a, b) => a + b);
  if (total <= 0) return contacts.join(' ');
  final pct = _percentagesTo100(split, total);
  return [
    for (var i = 0; i < contacts.length; i++)
      '${contacts[i]}(${pct[i]}%)',
  ].join(' ');
}

/// Whole percentages of [total] that sum to exactly 100.
///
/// Rounding each share independently gives 33/33/33 for three equal contacts,
/// and a printed 99 % reads as a missing share. Largest remainder first — the
/// same rule `encodeAmplitude` uses to make the milliamps sum to the dose.
List<int> _percentagesTo100(List<double> split, double total) {
  final exact = split.map((v) => v / total * 100).toList();
  final out = exact.map((v) => v.floor()).toList();
  var residual = 100 - out.fold<int>(0, (a, b) => a + b);
  final order = List<int>.generate(exact.length, (i) => i)
    ..sort((a, b) {
      final cmp = (exact[b] - out[b]).compareTo(exact[a] - out[a]);
      return cmp != 0 ? cmp : a.compareTo(b);
    });
  for (var k = 0; residual > 0 && k < order.length; k++, residual--) {
    out[order[k]] += 1;
  }
  return out;
}

/// The `_`-joined per-contact amplitudes as numbers, or null when any part is
/// not numeric. Twin of `parseAmplitude`, kept here so this file stays free of
/// the electrode layer's imports.
List<double>? _amplitudeParts(String amplitude) {
  final parts = amplitude
      .split('_')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .map(double.tryParse)
      .toList();
  if (parts.isEmpty || parts.contains(null)) return null;
  return parts.cast<double>();
}

/// One lead of a configuration as text: "2b(3.3) 2c(2.2)- / case+".
///
/// Shared by both builders so a lead is described one way throughout: the PDF's
/// text fallback and the Word captions each had their own wording, and one of
/// them printed the raw `E2b_E2c` tokens.
String lateralText(LateralTokens tokens, {required bool left}) {
  final anodes = contactsWithCurrent(
      left ? tokens.leftAnode : tokens.rightAnode, '');
  final cathodes = contactsWithCurrent(
      left ? tokens.leftCathode : tokens.rightCathode,
      left ? tokens.leftAmplitude : tokens.rightAmplitude);
  if (anodes.isEmpty && cathodes.isEmpty) return 'not recorded';
  return [
    if (cathodes.isNotEmpty) '$cathodes-',
    if (anodes.isNotEmpty) '$anodes+',
  ].join(' / ');
}

/// "name: value" lines for a block's scales.
String _scalesCell(Iterable<SessionRow> rows) =>
    _collectScalePairs(rows).map((p) => '${p.name}: ${p.value}').join('\n');

/// Column headers for the lateral session-data table (shared by both reports).
const sessionTableHeaders = [
  'Block',
  // A rating taken seconds after a parameter change measures an acute response
  // only, and without the clock the dose-response reading of this table is
  // unfalsifiable. In the worked example two "different" configurations are 9 s
  // apart on identical settings — invisible until the time is printed.
  'Time',
  'Side',
  // "Group" is the vendor's word for a stimulation programme; "Prog" read as
  // an abbreviation of nothing in particular.
  'Group',
  'Freq (Hz)',
  '+',
  '-',
  'Amp (mA)',
  'PW (µs)',
  'Scales',
  // The index the green shading is computed from, and its rank. The table used
  // to shade rows by a number it never showed, which makes the ranking
  // impossible to reproduce or challenge — and it turns on the third decimal.
  'Index',
  'Notes',
];

/// Relative column widths for [sessionTableHeaders], shared by both report
/// formats so the same table looks the same in each.
///
/// Mirrors the desktop's budget: narrow Block/Side/Prog, wide Scales, and Notes
/// absorbing the remainder. Word in particular NEEDS these — with no width hints
/// it runs its auto-fit algorithm on content alone, and since most of these
/// cells hold 1-4 characters the ten columns collapsed to a fraction of the
/// page while the PDF's filled it.
/// Sums to 100 so the split is readable as percentages.
///
/// Sized to the HEADER, not just the data: Block/Side/Group hold one or two
/// characters but their headings are 4-5, and at 5 units (26 pt of a 523 pt
/// content area) Word and the PDF both broke them mid-word into "Blo ck",
/// "Sid e", "Gro up". The +/- columns were widened for the same reason in
/// reverse — they now carry `2c(4.5)`, not `E2c`.
const sessionTableColumnWeights = <double>[
  7, // Block   (a heading in 8 pt bold needs ~33 pt incl. cell padding, and
  //            523 pt of content x 6/100 is only 31 -> "Bloc k")
  8, // Time    ("16:46:37")
  6, // Side
  7, // Group
  6, // Freq (Hz)   (wraps to two lines by design)
  8, // +           (anodes, e.g. "case")
  11, // -          (cathodes with their share, e.g. "2b(60%) 2c(40%)")
  6, // Amp (mA)
  5, // PW (us)
  15, // Scales
  8, // Index       ("0.430" over "(rank 6)")
  13, // Notes  (the slack comes from here: wrapping prose is normal, wrapping
  //            a heading into "Bloc k" looks broken)
];

/// Green fills for the best / second-best ranking, as ARGB ints. Same pair the
/// desktop uses for both the chart bands and the table row shading
/// (`report_chart_utils.py:28-29`, `report_common.py:205`).
const int kBestFill = 0xFF96D2A0;
const int kSecondFill = 0xFFC8EBCD;

/// A built report, plus whether any character had to be replaced to render it.
///
/// [lostCharacters] exists so the UI can say so. Without it the PDF's Latin-1
/// fallback silently turns an unsupported glyph into `?` (or, before the
/// sanitiser, into a blank box) and a note that lost characters is
/// indistinguishable from one that never had them — silent corruption of a
/// clinical record. The flag was computed and tested but had nowhere to go
/// while the builders returned bare bytes.
typedef ReportBytes = ({Uint8List bytes, bool lostCharacters});

/// The disclaimer printed under the session-data table, verbatim from the
/// desktop (`report_common.add_table_legend`). It is a clinical-liability
/// statement, so the wording is deliberately not paraphrased, and it is shared
/// so both report formats carry it identically.
/// Printed in place of the targets line when nobody set any.
///
/// The alternative — what this used to do — was to invent `min` over 0..10 for
/// every scale and print it as `Scale targets: Mood: min; Energy: min`, which
/// asserts a clinical intent no one expressed. In the worked example those
/// scales measure the magnitude of the named thing, so the fabricated targets
/// scored falling mood and falling energy as improvement.
const kNoTargetsText =
    'Scale targets: none set. No ranking was applied — open this session in '
    'the app and set a target per scale to rank the configurations.';

const kRankingDisclaimer =
    'Note: The highlighted rows are derived exclusively from the recorded '
    'session scale values and represent a computational ranking intended '
    'solely as a reference. This color-coded indication does not constitute '
    'clinical guidance. The ranking does not account for side effects, '
    'tolerability, or the observations in the Notes column, and is not a '
    'recommendation to programme these settings.';

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
    required this.amplitude,
    required this.aggregateIndex,
    required this.bestXs,
    required this.secondXs,
    required this.title,
    required this.xLabel,
    required this.yLabel,
    this.xTickLabels = const {},
  });

  /// One entry per scale, in encounter order: name -> {x -> value}. Missing x
  /// values are absent, which the painter renders as a break in the line.
  final Map<String, Map<int, double>> series;

  /// Sorted x positions (block IDs) present in any series.
  final List<int> xs;

  /// Left-axis bounds. Clamped to the union of declared scale ranges when the
  /// prefs supply one, else auto-fitted to the data.
  final double yMin, yMax;

  /// Total delivered current per side, per x, in mA. Drawn as its own strip
  /// under the index so the figure shows the DOSE as well as the response —
  /// without it the x axis is an ordinal with no clinical meaning and the
  /// figure cannot be read as dose-response at all.
  final Map<String, Map<int, double>> amplitude;

  /// Aggregate index per x, on a fixed 0..1 right axis. Empty when the desktop
  /// would not draw it (fewer than two scales).
  final Map<int, double> aggregateIndex;

  /// x positions to band green: EVERY block of the best-scoring setting, and
  /// every block of the second. Empty when there is no index to rank by.
  ///
  /// Lists, not single blocks, because the unit being ranked is a stimulation
  /// setting and a setting may have been rated more than once. Banding only one
  /// of two identical blocks presented a repeat rating as a rival
  /// configuration.
  final List<int> bestXs, secondXs;

  /// First banded block, for callers that only need somewhere to point.
  int? get bestX => bestXs.isEmpty ? null : bestXs.first;
  int? get secondX => secondXs.isEmpty ? null : secondXs.first;

  final String title, xLabel, yLabel;

  /// Text for each x tick, when the position itself is not the label.
  ///
  /// The session figure's x IS the block number, so it needs none. The
  /// longitudinal figures index visits and (visit, block) pairs, where the
  /// index is an internal position and the label is `20260626_01` — printing
  /// the index there would assert that "3" means something.
  final Map<int, String> xTickLabels;

  /// Nothing to draw.
  bool get isEmpty => series.isEmpty || xs.isEmpty;
}

/// Everything the report builders need, computed once from the raw rows.
class SessionReportData {
  const SessionReportData({
    required this.sessionDate,
    required this.generatedOn,
    required this.startTime,
    required this.endTime,
    required this.utcOffset,
    required this.sourceFile,
    required this.rowCount,
    required this.lastConfig,
    required this.firstConfig,
    required this.configChanges,
    required this.replicateSpread,
    required this.anomalies,
    required this.numDistinctConfigs,
    required this.hasInitial,
    required this.initScales,
    required this.initNotes,
    required this.tableData,
    required this.electrodeModel,
    required this.hasElectrodeConfig,
    required this.initialTokens,
    required this.finalTokens,
    required this.hasRows,
    required this.span,
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
    required this.hasTargets,
    required this.blockIndex,
    required this.observations,
    required this.response,
    required this.scalesRated,
    required this.initialRow,
    required this.finalRow,
  });

  /// The date the session was RECORDED, "yyyy-MM-dd", from the rows' own
  /// timestamps — or [generatedOn] when no row carries a parseable one.
  ///
  /// These used to be the same value, both taken from the export clock, so a
  /// report produced a fortnight later asserted in writing that the session
  /// happened the day the button was pressed.
  final String sessionDate;

  /// The date the document was produced, "yyyy-MM-dd".
  final String generatedOn;

  /// Clock time of the first and last entry, "HH:mm", or '' when unknown.
  final String startTime, endTime;

  /// UTC offset of those times, e.g. "+02:00", or '' when the rows carry none.
  final String utcOffset;

  /// The file the rows came from, and how many there were.
  ///
  /// Provenance: without them the report cannot be tied back to one file among
  /// several runs of the same session, which is what makes it evidence rather
  /// than a printout.
  final String sourceFile;
  final int rowCount;

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
  ///
  /// [span] is the first-to-last annotation interval — named for what it
  /// measures, not "session duration", which it is not.
  final String span;

  /// Recording blocks, baseline excluded. Counting every block (as this used to)
  /// reported 8 for a 7-block session and blended the pre-session settings into
  /// the "tested" parameter ranges, so you could not tell whether 7.0 mA was
  /// tried or was where the patient started.
  final int numConfigs;

  /// Distinct stimulation settings among those blocks. Lower than [numConfigs]
  /// whenever a setting was rated more than once — in the worked example, 7
  /// blocks are 5 distinct settings.
  final int numDistinctConfigs;
  final String ampL, ampR, freqL, freqR, pwL, pwR;

  /// scale -> {block -> value} for the scales-timeline graph.
  final Map<String, Map<int, double>> timeline;

  /// Everything needed to draw the scales chart, ready for the shared painter.
  final ScalesChartSpec chart;

  /// Block IDs to shade green in the session-data table.
  ///
  /// These are now the SAME blocks the chart bands mark, from the same
  /// aggregate index against the same targets. The desktop runs two different
  /// algorithms here — signed raw sums for the table, a normalised weighted
  /// index for the chart — and its own comment admits they can disagree. Two
  /// green markers pointing at different blocks in one clinical document is
  /// indefensible, so the raw-sum twin is gone.
  final List<int> bestBlocks, secondBlocks;

  /// Things about this session a reader should not have to notice unaided.
  ///
  /// A record that surfaces its own anomalies is auditable; one that ranks
  /// straight through them is not. Two shapes are reported, both present in the
  /// worked example: the same stimulation rated more than once (so a "second
  /// best" may be a repeat, not a rival), and identical ratings under different
  /// stimulation (so it cannot be told whether a block was re-rated or the
  /// previous values were carried forward).
  final List<String> anomalies;

  /// The largest index spread between repeat ratings of one setting, or null
  /// when nothing was rated twice. See [rankingResolutionNote].
  final double? replicateSpread;

  /// What the ranking's numbers are worth, in the session's own terms.
  ///
  /// In the worked example the two top "configurations" are the SAME setting
  /// rated 9 s apart, and they differ by 0.075 — 7.5x the 0.010 separating
  /// three genuinely different settings. Without this sentence the reader is
  /// invited to treat a third-decimal difference as a finding.
  String? get rankingResolutionNote {
    final spread = replicateSpread;
    if (spread == null) return null;
    return 'Repeat ratings of an unchanged setting differ by up to '
        '${spread.toStringAsFixed(3)} on this index in this session, so two '
        'settings closer together than that are not distinguishable by these '
        'ratings.';
  }

  /// The blocks that share the top-ranked setting, described for the legend.
  String get bestSettingText => bestBlocks.length <= 1
      ? ''
      : 'The highest-scoring setting was rated in blocks '
          '${bestBlocks.join(', ')}.';

  /// The configuration in force at the START of the session, same shape as
  /// [lastConfig]. From the baseline row, which is the state the patient
  /// arrived in.
  final Map<String, String> firstConfig;

  /// What changed between [firstConfig] and [lastConfig], one line per side
  /// that moved, plus an explicit line for anything that did not.
  ///
  /// The question the next clinician asks first is "what did you change?", and
  /// answering it previously meant diffing block 1 against block 7 by eye
  /// across a fourteen-row table.
  final List<String> configChanges;

  /// The last recorded configuration, as a printable summary: side -> lines.
  ///
  /// Honestly named. Nothing in the TSV records that a clinician *chose* it —
  /// it is simply the final row — so calling it "final settings" asserts a
  /// decision the data does not contain.
  final Map<String, String> lastConfig;

  /// One line per block that carries a note: block, time, parameters, note.
  ///
  /// The notes column holds the only adverse-event data the format captures —
  /// "warm rush", "anxiety and sadness" — and buried in a 14 %-wide cell inside
  /// a fourteen-row table nobody reads it. This is the safety content of the
  /// session, so it also gets its own section.
  final List<String> observations;

  /// Per scale: its first and last recorded value and the delta.
  ///
  /// Every stimulation parameter got a range and no scale did, so the clinical
  /// bottom line of the encounter appeared nowhere in three pages.
  final List<({String name, double first, double last})> response;

  /// Block -> how many scales were rated there.
  ///
  /// The index averages only the scales present at that block, so blocks with
  /// different rated sets are not comparable: one where only Anxiety was rated,
  /// and it was low, scores 0.625 and can outrank a fully-rated block.
  final Map<int, int> scalesRated;

  /// Caption for the session-scales figure.
  ///
  /// The chart is one click out of a .docx and was leaving the document with no
  /// subject, no session, no n and no explanation of its two green rectangles.
  String get figureCaption {
    final rated = scalesRated.values.fold<int>(0, (a, b) => a + b);
    final scales = chart.series.length;
    return 'Figure 1. Session scales by rated block. '
        '${chart.xs.length} block${chart.xs.length == 1 ? '' : 's'} x '
        '$scales scale${scales == 1 ? '' : 's'} '
        '($rated of ${chart.xs.length * scales} rated). '
        '${hasTargets ? 'Green bands: highest and second-highest aggregate '
            'index (right axis, 0-1; 1 = best).' : 'No scale targets were set, '
            'so no ranking is shown.'}';
  }

  /// What the scale numbers are, and what the record does not say about them.
  ///
  /// The clinical review's point: "Obsessions: 7.25" is 0-10 of *what*? The TSV
  /// stores no anchors and no administration method, and the app prints two
  /// decimals while the contract declares a coarser step — so the document must
  /// not imply a precision or a provenance it cannot support.
  String get instrumentNote =>
      'Session scales are point ratings recorded during the session, printed '
      'as recorded. The source data carries no scale anchors, administration '
      'method or rater, so those cannot be reproduced from this document.';

  /// How the index is computed, for the legend. Printing the modes alone left
  /// the equal weighting across every scale invisible — and for OCD, Obsessions
  /// and Compulsions are the primary outcome while Mood and Energy are
  /// side-effect monitors, so equal weighting is a clinical judgement.
  String get indexMethod =>
      'Aggregate index: unweighted mean over the scales rated at that block of '
      'each value normalised into its declared range and oriented by its '
      'target, clipped to 0-1; 1 = best. A scale with no target contributes a '
      'neutral 0.5 at half weight.';

  /// "Scale targets: name: min; other: max" for the table legend block, or ''
  /// when no scale has an active optimisation mode.
  final String targetsText;

  /// Whether any scale carries an optimisation target.
  ///
  /// False for a TSV opened from elsewhere, where nobody chose one. Both
  /// builders then print [kNoTargetsText] and draw no green anywhere, rather
  /// than ranking against invented targets.
  final bool hasTargets;

  /// Rank -> (index value, the blocks that share it), best first.
  ///
  /// The document shades rows by this number, so it has to be printable: a
  /// ranking a reader cannot reproduce or challenge is not auditable, and this
  /// one turns on the third decimal.
  final Map<int, double> blockIndex;

  /// The rows the electrode configuration was taken from, so the caller can
  /// render images of exactly the configurations the text describes.
  final SessionRow? initialRow, finalRow;

  /// True when there are recording blocks to tabulate.
  bool get hasRecording => tableData.isNotEmpty;

  /// "2026-06-26, 09:12-11:40" — the encounter, for the header/footer.
  ///
  /// ASCII on purpose. Text this file GENERATES (unlike text the user typed)
  /// must be Latin-1: with no Unicode TTF bundled the PDF falls back to
  /// Helvetica, which cannot draw an en dash at all, and the sanitiser only
  /// runs over user content. An en dash here dropped the glyph.
  String get sessionStamp => startTime.isEmpty
      ? sessionDate
      : '$sessionDate, $startTime-$endTime'
          '${utcOffset.isEmpty ? '' : ' (UTC$utcOffset)'}';
}

/// Build the scales-chart spec, applying the same target/index/ranking rules as
/// the desktop chart (`report_chart_utils.build_scales_chart`).
ScalesChartSpec buildScalesChartSpec({
  required Map<String, Map<int, double>> timeline,
  required List<ScalePref> prefs,
  /// Block -> a key identifying its stimulation setting. Blocks sharing a key
  /// are the SAME configuration rated more than once, so they rank together.
  /// Omit to fall back to ranking each block on its own.
  Map<int, String> settingOf = const {},
  Map<String, Map<int, double>> amplitude = const {},
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

  // Two suppressions, one dropped and one added.
  //
  // DROPPED: the desktop draws no index below two scales. The user asked for the
  // ranking to work "no matter how many scales there are", and a single scale
  // against its own target ranks the blocks perfectly well.
  //
  // ADDED: no targets means no index at all. With an empty target map every
  // scale scores a neutral 0.5 at half weight, so every block ties on 0.5 and
  // `findBestAndSecond` hands back whichever two came first — a green band
  // placed by iteration order. Ranking requires knowing what "better" means.
  final index = targets.isEmpty
      ? const <int, double>{}
      : computeAggregateIndex(timeline, sortedXs, targets);
  final ranking = rankSettings(index, settingOf);

  return ScalesChartSpec(
    series: timeline,
    amplitude: amplitude,
    xs: sortedXs,
    yMin: yMin,
    yMax: yMax,
    aggregateIndex: index,
    bestXs: ranking.best,
    secondXs: ranking.second,
    title: title,
    xLabel: xLabel,
    yLabel: yLabel,
  );
}

/// Rank stimulation SETTINGS by their mean aggregate index and return the
/// blocks of the best and second-best.
///
/// [settingOf] maps a block to a key identifying its configuration; blocks
/// sharing a key were the same setting rated more than once, so they score
/// together and are banded together. A block with no entry ranks alone.
///
/// Ties resolve to the setting whose first block came earlier, matching
/// `findBestAndSecond`'s stable-sort behaviour.
({List<int> best, List<int> second}) rankSettings(
  Map<int, double> index,
  Map<int, String> settingOf,
) {
  if (index.isEmpty) return (best: const [], second: const []);

  final blocksOf = <String, List<int>>{};
  for (final block in index.keys) {
    (blocksOf[settingOf[block] ?? 'block:$block'] ??= []).add(block);
  }

  final keys = blocksOf.keys.toList();
  double meanOf(String k) {
    final vals = blocksOf[k]!.map((b) => index[b]!);
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  final order = List<int>.generate(keys.length, (i) => i)
    ..sort((a, b) {
      final cmp = meanOf(keys[b]).compareTo(meanOf(keys[a]));
      return cmp != 0 ? cmp : a.compareTo(b);
    });

  final best = blocksOf[keys[order[0]]]!..sort();
  final second =
      order.length > 1 ? (blocksOf[keys[order[1]]]!..sort()) : const <int>[];
  return (best: best, second: second);
}

/// The spread between repeat ratings of one setting — the session's own
/// measure of how much the ranking's numbers move when nothing changes.
///
/// Null when no setting was rated twice, i.e. when the session offers no
/// estimate at all. Two settings closer together than this are not
/// distinguishable by these ratings, and the report says so.
double? replicateSpread(Map<int, double> index, Map<int, String> settingOf) {
  final byKey = <String, List<double>>{};
  for (final e in index.entries) {
    final key = settingOf[e.key];
    if (key == null) continue;
    (byKey[key] ??= []).add(e.value);
  }
  double? worst;
  for (final vals in byKey.values) {
    if (vals.length < 2) continue;
    final spread = vals.reduce((a, b) => a > b ? a : b) -
        vals.reduce((a, b) => a < b ? a : b);
    if (worst == null || spread > worst) worst = spread;
  }
  return worst;
}

/// "name: min; other: max; third: 4.5" for the table legend, or '' when every
/// scale is ignored. Mirrors the targets line in `report_common.add_table_legend`.
String _targetsText(List<ScalePref> prefs) {
  final parts = <String>[];
  for (final p in prefs) {
    switch (p.mode) {
      // The bounds travel with the mode: the index normalises into them, so a
      // reader cannot reproduce the score without knowing what they were.
      case ScaleMode.min:
        parts.add('${p.name}: min of ${_trimZeros(p.min)}-${_trimZeros(p.max)}');
      case ScaleMode.max:
        parts.add('${p.name}: max of ${_trimZeros(p.min)}-${_trimZeros(p.max)}');
      case ScaleMode.custom:
        parts.add('${p.name}: ${_trimZeros(p.custom ?? 0)} '
            'of ${_trimZeros(p.min)}-${_trimZeros(p.max)}');
      case ScaleMode.ignore:
        break;
    }
  }
  return parts.join('; ');
}

/// The anode/cathode/amplitude tokens of [r], or null when there is no row.
LateralTokens? tokensOf(SessionRow? r) => r == null
    ? null
    : (
        leftAnode: r.leftAnode,
        leftCathode: r.leftCathode,
        leftAmplitude: r.leftAmplitude,
        rightAnode: r.rightAnode,
        rightCathode: r.rightCathode,
        rightAmplitude: r.rightAmplitude,
      );

/// One line per side that changed between [from] and [to], and one saying so
/// when a parameter held steady on both sides.
///
/// Compares the printable per-side summaries rather than raw columns, so the
/// output speaks the same language as the box above it.
List<String> _configChanges(SessionRow? from, SessionRow? to) {
  if (from == null || to == null) return const [];
  final out = <String>[];
  for (final left in [true, false]) {
    final side = left ? 'Left' : 'Right';
    final before = lateralText(tokensOf(from)!, left: left);
    final after = lateralText(tokensOf(to)!, left: left);
    if (before == after) continue;
    out.add('$side: $before -> $after');
  }
  // Frequency and pulse width are usually untouched across a session, and
  // saying so is more useful than leaving the reader to check.
  bool same(String Function(SessionRow) pick) =>
      pick(from).trim() == pick(to).trim();
  final steady = <String>[
    if (same((r) => r.leftStimFreq) && same((r) => r.rightStimFreq))
      'frequency',
    if (same((r) => r.leftPulseWidth) && same((r) => r.rightPulseWidth))
      'pulse width',
  ];
  if (steady.isNotEmpty) out.add('Unchanged: ${steady.join(' and ')}.');
  if (out.isEmpty) out.add('No change from the pre-session configuration.');
  return out;
}

/// "7" or, when a setting was rated more than once, "7 (6 distinct settings)".
///
/// Shared by both builders. Printing the block count alone overstates how much
/// was actually explored: in the worked example blocks 6 and 7 are
/// byte-identical in every stimulation column and were rated 9 seconds apart,
/// so "7 configurations tested" describes 6 settings. Pinned by
/// `test/ranking_values_test.dart` — an earlier version of this comment claimed
/// five, which was wrong about its own worked example.
String configCountText(SessionReportData data) =>
    data.numDistinctConfigs > 0 && data.numDistinctConfigs != data.numConfigs
        ? '${data.numConfigs} (${data.numDistinctConfigs} distinct settings)'
        : '${data.numConfigs}';

/// One printable line per side for the last recorded configuration, plus the
/// programme, for the page-1 summary box.
///
/// Answers the clinician's central complaint — "it tells me everything that
/// happened and never tells me what we decided" — with the strongest claim the
/// data actually supports.
Map<String, String> _lastConfigLines(SessionRow? r) {
  if (r == null) return const {};
  String side(String anode, String cathode, String amp, String freq,
      String pw) {
    final cathodes = contactsWithCurrent(cathode, amp);
    final anodes = contactsWithCurrent(anode, '');
    if (cathodes.isEmpty && anodes.isEmpty) return '';
    final total = _paramRange([amp], splitSum: true);
    final dose = total == null ? '' : ' = ${_trimZeros(total.$2)} mA';
    final f = freq.trim().isEmpty ? '' : ', ${_numCell(freq)} Hz';
    final p = pw.trim().isEmpty ? '' : ', ${_numCell(pw)} \u00B5s';
    return '$cathodes-'
        '${anodes.isEmpty ? '' : ' / $anodes+'}$dose$f$p';
  }

  final out = <String, String>{};
  final left = side(r.leftAnode, r.leftCathode, r.leftAmplitude,
      r.leftStimFreq, r.leftPulseWidth);
  final right = side(r.rightAnode, r.rightCathode, r.rightAmplitude,
      r.rightStimFreq, r.rightPulseWidth);
  if (left.isNotEmpty) out['Left'] = left;
  if (right.isNotEmpty) out['Right'] = right;
  if (r.programId.trim().isNotEmpty) out['Group'] = r.programId.trim();
  return out;
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
  String sourceFile = '',
}) {
  final dt = generatedAt ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  String ymd(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
  String hm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
  final generatedOn = ymd(dt);

  // The encounter's own date and clock span, from the rows.
  final stamps = _stamps(rows);
  final sessionDate = stamps.isEmpty ? generatedOn : ymd(stamps.first);
  final startTime = stamps.isEmpty ? '' : hm(stamps.first);
  final endTime = stamps.isEmpty ? '' : hm(stamps.last);

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

  // Programming summary over the RECORDING rows: the baseline block is the
  // state the patient arrived in, not a configuration that was tested, and
  // including it both inflated the count and widened every "tested" range.
  final span = _spanText(rows);
  final numConfigs =
      recordingRows.map((r) => coerceInt(r.blockId)).toSet().length;
  final numDistinctConfigs =
      recordingRows.map((r) => _paramKey(r).join(_sep)).toSet().length;
  final ampL = _valuesText(blocks, (r) => r.leftAmplitude, 'mA', 1,
      splitSum: true);
  final ampR = _valuesText(blocks, (r) => r.rightAmplitude, 'mA', 1,
      splitSum: true);
  final freqL = _valuesText(blocks, (r) => r.leftStimFreq, 'Hz', 0);
  final freqR = _valuesText(blocks, (r) => r.rightStimFreq, 'Hz', 0);
  final pwL = _valuesText(blocks, (r) => r.leftPulseWidth, 'µs', 0);
  final pwR = _valuesText(blocks, (r) => r.rightPulseWidth, 'µs', 0);

  // Electrode configuration: latest baseline row = initial settings, latest
  // recording row = final settings.
  final latestFinal = _latestRow(recordingRows);
  final electrodeModel = [
    latestInit?.electrodeModel.trim() ?? '',
    latestFinal?.electrodeModel.trim() ?? '',
  ].firstWhere((m) => m.isNotEmpty, orElse: () => '');

  // Optimisation targets drive the chart's index and bands AND the table's
  // shading and Index column, so they are resolved before the table is built.
  //
  // There is deliberately NO fallback to `defaultScalePrefsFor`: fabricating
  // `min` over 0..10 for a file nobody configured produced a ranking, two green
  // bands and a printed "Scale targets" line that all asserted a clinical
  // intent no one expressed. Targets come from the Step-2 editors, or from the
  // export dialog, or there is no ranking.
  final prefs = scalePrefs ?? const <ScalePref>[];
  final hasTargets = parseScaleTargets(prefs).isNotEmpty;
  final timeline = scaleTimeline(rows);

  // Which blocks were the same setting. The ranking groups on this, so a
  // configuration rated twice scores once and is banded once.
  final settingOf = <int, String>{
    for (final entry in blocks.entries)
      entry.key: _paramKey(entry.value.first).join(_sep),
  };
  // Total current per side per block, for the figure's dose strip.
  final amplitudeSeries = <String, Map<int, double>>{};
  for (final entry in blocks.entries) {
    void put(String side, String raw) {
      final r = _paramRange([raw], splitSum: true);
      // Rounded to a tenth, matching the table cell: an IPG steps in 0.1 mA,
      // and files written before encodeAmplitude was fixed hold sums like 5.01.
      if (r != null) {
        (amplitudeSeries[side] ??= <int, double>{})[entry.key] =
            (r.$1 * 10).round() / 10;
      }
    }
    put('Left', entry.value.first.leftAmplitude);
    put('Right', entry.value.first.rightAmplitude);
  }

  final chart = buildScalesChartSpec(
      timeline: timeline,
      prefs: prefs,
      settingOf: settingOf,
      amplitude: amplitudeSeries);

  // Anomalies, from the groupings already computed.
  final anomalies = <String>[];
  {
    final blocksPerSetting = <String, List<int>>{};
    settingOf.forEach((block, key) =>
        (blocksPerSetting[key] ??= []).add(block));
    for (final e in blocksPerSetting.entries) {
      if (e.value.length < 2) continue;
      final list = e.value..sort();
      anomalies.add('Blocks ${list.join(', ')} record the same stimulation '
          'setting, so their ratings are repeats rather than separate '
          'configurations.');
    }
    // The mirror image: same ratings, different stimulation.
    final byRatings = <String, List<int>>{};
    for (final entry in blocks.entries) {
      final key = _collectScalePairs(entry.value)
          .map((p) => '${p.name}=${p.value}')
          .join('|');
      if (key.isEmpty) continue;
      (byRatings[key] ??= []).add(entry.key);
    }
    for (final e in byRatings.entries) {
      if (e.value.length < 2) continue;
      final list = e.value..sort();
      if (list.map((b) => settingOf[b]).toSet().length < 2) continue;
      anomalies.add('Blocks ${list.join(', ')} carry identical ratings under '
          'different stimulation settings; the record does not distinguish a '
          're-rating from values carried forward.');
    }
  }

  // Table shading and chart bands from ONE ranking, so they cannot disagree.
  final bestBlocks = chart.bestXs;
  final secondBlocks = chart.secondXs;
  final spread = replicateSpread(chart.aggregateIndex, settingOf);

  // Rank per block, best first, so the table can print "1" / "2" beside the
  // index. Colour alone stakes the claim today, and #96D2A0 / #C8EBCD are
  // luminance 0.78 / 0.88 — photocopied they are indistinguishable from white
  // and from each other.
  final ranked = chart.aggregateIndex.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final rankOf = <int, int>{
    for (var i = 0; i < ranked.length; i++) ranked[i].key: i + 1,
  };

  // n scales rated per block, and the per-block note lines.
  final scalesRated = <int, int>{};
  final observations = <String>[];
  for (final entry in blocks.entries) {
    scalesRated[entry.key] = _collectScalePairs(entry.value).length;
    final first = entry.value.first;
    final note = first.notes.trim();
    if (note.isEmpty) continue;
    final where = [
      if (first.time.trim().isNotEmpty) first.time.trim(),
      if (first.leftAmplitude.trim().isNotEmpty)
        'L ${lateralText(tokensOf(first)!, left: true)}',
      if (first.rightAmplitude.trim().isNotEmpty)
        'R ${lateralText(tokensOf(first)!, left: false)}',
    ].join(', ');
    observations.add('Block ${entry.key}'
        '${where.isEmpty ? '' : ' ($where)'}: $note');
  }

  // First-to-last delta per session scale, over the recording blocks in time
  // order — the response half of a dose-response record.
  final response = <({String name, double first, double last})>[];
  {
    final firstSeen = <String, double>{};
    final lastSeen = <String, double>{};
    for (final row in recordingRows) {
      for (final pair in splitScalePairs(row.scaleName, row.scaleValue)) {
        if (pair.name.isEmpty || isScaleValueOmitted(pair.value)) continue;
        final v = double.tryParse(pair.value.trim());
        if (v == null || !v.isFinite) continue;
        firstSeen.putIfAbsent(pair.name, () => v);
        lastSeen[pair.name] = v;
      }
    }
    for (final name in firstSeen.keys) {
      response.add(
          (name: name, first: firstSeen[name]!, last: lastSeen[name]!));
    }
  }

  DateTime? previousBlockTime;

  // Lateral session-data table: two rows (L / R) per block. Scales and notes
  // belong to the BLOCK, not to a side, so they are written on the L row only
  // and left blank on the R row — the Word builder vertically merges the pair,
  // and the PDF reads as merged. Printed twice, a 7-block x 5-scale session
  // repeated the scale list 14 times and every note twice, and a duplicated
  // note can read as two separate observations.
  final tableData = <List<String>>[];
  for (final entry in blocks.entries) {
    final first = entry.value.first;
    final scales = _scalesCell(entry.value);
    // Earliest stamp in this block, and the gap from the previous block's.
    final stamps = _stamps(entry.value);
    final when = stamps.isEmpty ? null : stamps.first;
    final gap = _gapText(previousBlockTime, when);
    previousBlockTime = when ?? previousBlockTime;

    final idx = chart.aggregateIndex[entry.key];
    final indexCell = idx == null
        ? ''
        : '${idx.toStringAsFixed(3)}\n(rank ${rankOf[entry.key]})';
    List<String> side(bool left) => [
          '${entry.key}',
          left
              ? [first.time.trim(), if (gap.isNotEmpty) '($gap)'].join('\n')
              : '',
          left ? 'L' : 'R',
          first.programId,
          _numCell(left ? first.leftStimFreq : first.rightStimFreq),
          contactsWithCurrent(left ? first.leftAnode : first.rightAnode, ''),
          contactsWithCurrent(left ? first.leftCathode : first.rightCathode,
              left ? first.leftAmplitude : first.rightAmplitude),
          _amplitudeCell(left ? first.leftAmplitude : first.rightAmplitude),
          _numCell(left ? first.leftPulseWidth : first.rightPulseWidth),
          left ? scales : '',
          left ? indexCell : '',
          left ? first.notes : '',
        ];
    tableData.add(side(true));
    tableData.add(side(false));
  }


  return SessionReportData(
    sessionDate: sessionDate,
    generatedOn: generatedOn,
    startTime: startTime,
    endTime: endTime,
    utcOffset: _utcOffset(rows),
    sourceFile: sourceFile,
    rowCount: rows.length,
    lastConfig: _lastConfigLines(latestFinal),
    firstConfig: _lastConfigLines(latestInit),
    configChanges: _configChanges(latestInit, latestFinal),
    observations: observations,
    response: response,
    scalesRated: scalesRated,
    numDistinctConfigs: numDistinctConfigs,
    chart: chart,
    bestBlocks: bestBlocks,
    secondBlocks: secondBlocks,
    replicateSpread: spread,
    anomalies: anomalies,
    targetsText: hasTargets ? _targetsText(prefs) : kNoTargetsText,
    hasTargets: hasTargets,
    blockIndex: chart.aggregateIndex,
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
    span: span,
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
