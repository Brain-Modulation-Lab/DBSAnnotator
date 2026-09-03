/// Pure computation behind the longitudinal report: one entry per visit, and
/// the two figures the desktop draws.
///
/// ## Why two figures, and why the old x axis was wrong
///
/// The report used to plot a single series set against a **concatenated block
/// index** — every imported file's blocks laid end to end. That number means
/// nothing across visits: block 3 of June and block 3 of September are
/// different configurations of different sessions, and the axis silently
/// asserted they were comparable points on one scale.
///
/// The desktop draws two figures instead, and they answer different questions:
///
/// - **Clinical scales, x = visit.** One assessment per visit, so the axis is
///   the visit itself. This is the "is the patient better than last time"
///   figure. It carries **no aggregate index and no green bands** — the index is
///   normalised within a session, so ranking across visits would be comparing
///   numbers that were never on the same scale.
/// - **Session scales, x = visit + block.** Several configurations per visit, so
///   each visit contributes a run of points. This is the "what did we try, and
///   how did it go" figure.
library;

import '../core/session/longitudinal.dart'
    show extractPatientId, isScaleValueOmitted, splitScalePairs;
import '../core/session/session_row.dart';
import 'report_data.dart' show ScalesChartSpec, coerceInt;

/// One imported file: a visit.
typedef LongitudinalVisit = ({
  String filename,

  /// From the rows themselves, "yyyy-MM-dd", or '' when none parse.
  String date,

  /// The BIDS `run-` entity, or ''.
  String run,

  /// "20260626_01" — the desktop's `{date}_{run}` tick label.
  String label,

  /// Baseline (`is_initial == 1`) scale scores: the clinical assessment.
  Map<String, double> clinicalScales,

  /// Recording block IDs, ascending.
  List<int> blocks,

  /// Session scale -> block -> value, over the recording blocks.
  Map<String, Map<int, double>> sessionScales,

  /// The last recording row, i.e. the configuration in force at visit end.
  SessionRow? finalRow,
});

/// Everything the longitudinal builders render.
class LongitudinalReportData {
  const LongitudinalReportData({
    required this.patientId,
    required this.generatedOn,
    required this.visits,
    required this.clinicalChart,
    required this.sessionChart,
    required this.visitTable,
    required this.mismatchedPatients,
  });

  final String patientId;
  final String generatedOn;

  /// Visits in date order, oldest first.
  final List<LongitudinalVisit> visits;

  /// Clinical scales against the visit. No index, no bands — see the library
  /// comment.
  final ScalesChartSpec clinicalChart;

  /// Session scales against visit + block.
  final ScalesChartSpec sessionChart;

  /// The per-visit summary: date, programme at visit end, primary scale, delta.
  final List<List<String>> visitTable;

  /// Patient IDs found beyond [patientId]. Non-empty means the import mixed
  /// people, which is a safety issue, not a formatting one.
  final List<String> mismatchedPatients;

  bool get isEmpty => visits.isEmpty;
}

/// Column headers for [LongitudinalReportData.visitTable].
const longitudinalTableHeaders = [
  'Visit',
  'Date',
  'Programme at visit end',
  'Blocks',
  'Primary clinical scale',
  'Change',
];

/// The `run-` entity of a BIDS filename, or ''.
String _runOf(String filename) =>
    RegExp(r'run-([A-Za-z0-9]+)').firstMatch(filename)?.group(1) ?? '';

/// Build one visit from a file's rows.
LongitudinalVisit _visitOf(String filename, List<SessionRow> rows) {
  final initial = rows.where((r) => coerceInt(r.isInitial) == 1).toList();
  final recording = rows.where((r) => coerceInt(r.isInitial) != 1).toList();

  // The visit's date is the earliest stamp in the file.
  final dates = rows
      .map((r) => r.date.trim())
      .where((d) => d.isNotEmpty)
      .toList()
    ..sort();
  final date = dates.isEmpty ? '' : dates.first;

  double? value(String raw) {
    if (isScaleValueOmitted(raw)) return null;
    final v = double.tryParse(raw.trim());
    return (v == null || !v.isFinite) ? null : v;
  }

  // Clinical scores come from the baseline rows. Where a scale appears more
  // than once, the LAST wins: the desktop takes the highest-block baseline, and
  // a re-entered score supersedes the one it corrects.
  final clinical = <String, double>{};
  for (final row in initial) {
    for (final pair in splitScalePairs(row.scaleName, row.scaleValue)) {
      final v = value(pair.value);
      if (pair.name.isEmpty || v == null) continue;
      clinical[pair.name] = v;
    }
  }

  final blocks = <int>[];
  final session = <String, Map<int, double>>{};
  for (final row in recording) {
    final block = coerceInt(row.blockId);
    if (!blocks.contains(block)) blocks.add(block);
    for (final pair in splitScalePairs(row.scaleName, row.scaleValue)) {
      final v = value(pair.value);
      if (pair.name.isEmpty || v == null) continue;
      (session[pair.name] ??= <int, double>{})[block] = v;
    }
  }
  blocks.sort();

  final run = _runOf(filename);
  return (
    filename: filename,
    date: date,
    run: run,
    label: [date.replaceAll('-', ''), if (run.isNotEmpty) run].join('_'),
    clinicalScales: clinical,
    blocks: blocks,
    sessionScales: session,
    finalRow: recording.isEmpty ? null : recording.last,
  );
}

/// Round-trip-safe number text: "8" not "8.0", "7.25" as typed.
String _fmt(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Build the whole report from the imported files.
///
/// [files] is filename -> rows, in the order they were imported; visits are
/// sorted by date here so the figures read left to right in time.
LongitudinalReportData buildLongitudinalReportData({
  required Map<String, List<SessionRow>> files,
  DateTime? generatedAt,
}) {
  final dt = generatedAt ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final generatedOn = '${dt.year}-${two(dt.month)}-${two(dt.day)}';

  final visits = [
    for (final e in files.entries) _visitOf(e.key, e.value),
  ]..sort((a, b) => a.date.compareTo(b.date));

  // Patient identity. Mixing two people into one longitudinal report is a
  // safety problem, so it is surfaced rather than silently merged.
  final ids = files.keys
      .map(extractPatientId)
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  final patientId = ids.isEmpty ? 'unknown' : ids.first;

  // ---- Figure 1: clinical scales, one point per visit ---------------------
  final clinicalSeries = <String, Map<int, double>>{};
  final clinicalLabels = <int, String>{};
  for (final (i, visit) in visits.indexed) {
    clinicalLabels[i] = visit.label;
    visit.clinicalScales.forEach((name, v) {
      (clinicalSeries[name] ??= <int, double>{})[i] = v;
    });
  }

  // ---- Figure 2: session scales, one point per (visit, block) -------------
  final sessionSeries = <String, Map<int, double>>{};
  final sessionLabels = <int, String>{};
  var x = 0;
  for (final visit in visits) {
    for (final (bi, block) in visit.blocks.indexed) {
      // The desktop labels the first block of a visit with the full
      // `{date}_{run}_{block}` and later blocks with the bare block number, so
      // a long session does not stamp its date under every point.
      sessionLabels[x] = bi == 0 ? '${visit.label}_$block' : '$block';
      visit.sessionScales.forEach((name, byBlock) {
        final v = byBlock[block];
        if (v != null) (sessionSeries[name] ??= <int, double>{})[x] = v;
      });
      x++;
    }
  }

  ScalesChartSpec spec(
    Map<String, Map<int, double>> series,
    Map<int, String> labels,
    String title,
    String xLabel,
  ) {
    final xs = <int>{for (final m in series.values) ...m.keys}.toList()..sort();
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (final m in series.values) {
      for (final v in m.values) {
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    if (!lo.isFinite) {
      lo = 0;
      hi = 1;
    } else if (lo == hi) {
      lo -= 1;
      hi += 1;
    }
    return ScalesChartSpec(
      series: series,
      amplitude: const {},
      xs: xs,
      yMin: lo,
      yMax: hi,
      // No index and no bands on either figure: the aggregate index is
      // normalised WITHIN a session, so a value from June and one from
      // September were never on the same scale. The desktop passes
      // `show_general_index=False` here for the same reason.
      aggregateIndex: const {},
      bestXs: const [],
      secondXs: const [],
      title: title,
      xLabel: xLabel,
      yLabel: 'Scale value',
      xTickLabels: labels,
    );
  }

  // ---- The per-visit table ------------------------------------------------
  // The primary clinical scale is the one recorded at the most visits; ties go
  // to the alphabetically first, so the choice is stable across exports.
  final counts = <String, int>{};
  for (final v in visits) {
    for (final name in v.clinicalScales.keys) {
      counts[name] = (counts[name] ?? 0) + 1;
    }
  }
  String? primary;
  var best = 0;
  for (final name in counts.keys.toList()..sort()) {
    if (counts[name]! > best) {
      best = counts[name]!;
      primary = name;
    }
  }

  final table = <List<String>>[];
  double? previous;
  for (final (i, visit) in visits.indexed) {
    final score = primary == null ? null : visit.clinicalScales[primary];
    final delta = (score != null && previous != null) ? score - previous : null;
    table.add([
      '${i + 1}',
      visit.date.isEmpty ? 'unknown' : visit.date,
      _programmeText(visit.finalRow),
      '${visit.blocks.length}',
      score == null ? '-' : '${primary!}: ${_fmt(score)}',
      delta == null ? '-' : '${delta > 0 ? '+' : ''}${_fmt(delta)}',
    ]);
    if (score != null) previous = score;
  }

  return LongitudinalReportData(
    patientId: patientId,
    generatedOn: generatedOn,
    visits: visits,
    clinicalChart: spec(clinicalSeries, clinicalLabels,
        'Clinical scales by visit', 'Visit (date_run)'),
    sessionChart: spec(sessionSeries, sessionLabels,
        'Session scales by visit and block', 'Visit and block'),
    visitTable: table,
    mismatchedPatients: ids.length <= 1 ? const [] : ids.skip(1).toList(),
  );
}

/// The stimulation in force at the end of a visit, in one line.
String _programmeText(SessionRow? r) {
  if (r == null) return '-';
  String side(String amp, String freq, String pw) {
    final parts = [
      if (amp.trim().isNotEmpty) '${_sum(amp)} mA',
      if (freq.trim().isNotEmpty) '${freq.trim()} Hz',
      if (pw.trim().isNotEmpty) '${pw.trim()} µs',
    ];
    return parts.isEmpty ? '-' : parts.join('/');
  }

  final group = r.programId.trim();
  return 'L ${side(r.leftAmplitude, r.leftStimFreq, r.leftPulseWidth)}   '
      'R ${side(r.rightAmplitude, r.rightStimFreq, r.rightPulseWidth)}'
      '${group.isEmpty ? '' : '   Group $group'}';
}

/// Sum a possibly-split amplitude, at the device's 0.1 mA resolution.
String _sum(String raw) {
  final parts = raw
      .split('_')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .map(double.tryParse)
      .toList();
  if (parts.isEmpty || parts.contains(null)) return raw.trim();
  final total = parts.fold(0.0, (a, b) => a + b!);
  return total.toStringAsFixed(1);
}
