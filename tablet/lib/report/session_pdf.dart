/// Session (Complete-Workflow) PDF report, tablet counterpart of the
/// desktop's DOCX/PDF session exporter
/// (src/dbs_annotator/utils/session_exporter.py, `_export_to_word_path`).
/// Pure function over already-parsed [SessionRow]s so it is testable
/// headless (no widgets, no platform channels beyond the optional font
/// asset, which falls back to Helvetica when absent).
///
/// Section order mirrors the desktop report: title/patient header, initial
/// clinical notes, session data table, electrode configuration, programming
/// summary.
///
/// TODO(tablet): embed the electrode painter (ui/electrode_view.dart) as a
/// per-side image in the electrode-configuration section, like the desktop's
/// `_render_electrode_png` — v1 conveys the same configuration as anode /
/// cathode token text.
/// TODO(tablet): embed the fl_chart scales-timeline as an image before the
/// session data table (desktop `_add_scales_timeline_chart`).
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/session/longitudinal.dart'
    show isScaleValueOmitted, splitScalePairs;
import '../core/session/session_row.dart';
import 'report_fonts.dart';

/// Coerce a TSV cell to an int the way `pd.to_numeric(errors="coerce")
/// .fillna(0)` does: unparsable cells become 0 (same as
/// core/session/longitudinal.dart).
int _coerceInt(String raw) {
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
    final s = _coerceInt(row.sessionId).compareTo(_coerceInt(best.sessionId));
    if (s > 0 ||
        (s == 0 && _coerceInt(row.blockId) >= _coerceInt(best.blockId))) {
      best = row;
    }
  }
  return best;
}

/// Deduplicated (name, value) scale pairs over [rows], skipping blank names
/// and omitted values. Mirrors the seen-set loops in `_add_summary_section`
/// and `_create_lateral_table_data`.
List<({String name, String value})> _collectScalePairs(
    Iterable<SessionRow> rows) {
  final seen = <String>{};
  final pairs = <({String name, String value})>[];
  for (final row in rows) {
    for (final pair in splitScalePairs(row.scaleName, row.scaleValue)) {
      if (pair.name.isEmpty || isScaleValueOmitted(pair.value)) continue;
      if (seen.add('${pair.name}\u0000${pair.value}')) pairs.add(pair);
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
String _scalesCell(Iterable<SessionRow> rows) => _collectScalePairs(rows)
    .map((p) => '${p.name}: ${p.value}')
    .join('\n');

/// Build the session-report PDF and return its bytes.
///
/// [rows] are the programming-session rows (baseline + recording blocks,
/// as parsed by `parseSessionTsv` or authored in the session screen);
/// [subjectId] is the BIDS subject label (without the "sub-" prefix).
Future<Uint8List> buildSessionPdf({
  required List<SessionRow> rows,
  required String subjectId,
  DateTime? generatedAt,
}) async {
  final dt = generatedAt ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final date = '${dt.year}-${two(dt.month)}-${two(dt.day)}';

  // Split like the desktop: is_initial coerced == 1 -> baseline (Step 1),
  // everything else -> recording blocks (the session-data table).
  final initialRows =
      rows.where((r) => _coerceInt(r.isInitial) == 1).toList();
  final recordingRows =
      rows.where((r) => _coerceInt(r.isInitial) != 1).toList();

  // Initial clinical notes come from the LATEST initial session only.
  final latestInit = _latestRow(initialRows);
  final initSessionRows = latestInit == null
      ? const <SessionRow>[]
      : initialRows
          .where((r) =>
              _coerceInt(r.sessionId) == _coerceInt(latestInit.sessionId))
          .toList();
  final initScales = _collectScalePairs(initSessionRows);
  final initNotes = latestInit?.notes.trim() ?? '';

  // Recording rows grouped by (coerced) block_ID in encounter order,
  // mirroring `groupby(..., sort=False)` after block-ID normalization.
  final blocks = <int, List<SessionRow>>{};
  for (final row in recordingRows) {
    (blocks[_coerceInt(row.blockId)] ??= []).add(row);
  }

  // Programming summary is computed over ALL rows (desktop uses the full
  // DataFrame for duration, distinct configurations, and ranges).
  final duration = _durationText(rows);
  final numConfigs = rows.map((r) => _coerceInt(r.blockId)).toSet().length;
  final ampL = _rangeText(
      _paramRange(rows.map((r) => r.leftAmplitude), splitSum: true), 'mA', 1);
  final ampR = _rangeText(
      _paramRange(rows.map((r) => r.rightAmplitude), splitSum: true), 'mA', 1);
  final freqL = _rangeText(_paramRange(rows.map((r) => r.leftStimFreq)),
      'Hz', 0);
  final freqR = _rangeText(_paramRange(rows.map((r) => r.rightStimFreq)),
      'Hz', 0);
  final pwL = _rangeText(_paramRange(rows.map((r) => r.leftPulseWidth)),
      'µs', 0);
  final pwR = _rangeText(_paramRange(rows.map((r) => r.rightPulseWidth)),
      'µs', 0);

  // Electrode configuration: latest baseline row = initial settings, latest
  // recording row = final settings (desktop `_add_electrode_config_section`).
  final latestFinal = _latestRow(recordingRows);
  final electrodeModel = [
    latestInit?.electrodeModel.trim() ?? '',
    latestFinal?.electrodeModel.trim() ?? '',
  ].firstWhere((m) => m.isNotEmpty, orElse: () => '');

  // Session data table: two rows (L / R) per block, like the desktop's
  // lateral table. Column choice: the desktop's 21 TSV columns collapse to
  // Block / Side / Prog / freq / anode / cathode / amplitude / pulse width /
  // scales / notes; date-time, session_ID, is_initial and electrode_model
  // are dropped exactly as in its `columns_to_exclude`.
  const tableHeaders = [
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

  // Unicode theme when the Roboto assets are bundled; null -> built-in
  // Helvetica (ASCII-only, fine for tests / font-less checkouts).
  final theme = await loadReportTheme();
  final doc = theme == null ? pw.Document() : pw.Document(theme: theme);
  const cellStyle = pw.TextStyle(fontSize: 8);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ),
      build: (context) => [
        // (a) Title + patient + generated-on.
        pw.Header(
          level: 0,
          child: pw.Text(
            'DBS Annotator - Session report',
            style: const pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Text('Patient: sub-$subjectId    Session: $date'),
        pw.Text('Generated on: $date'),
        pw.SizedBox(height: 12),

        // (b) Initial clinical notes (latest baseline session).
        pw.Header(level: 1, text: 'Initial clinical notes'),
        if (latestInit == null)
          pw.Text('No baseline (is_initial = 1) rows recorded.')
        else ...[
          for (final pair in initScales)
            pw.Bullet(text: '${pair.name}: ${pair.value}'),
          if (initNotes.isNotEmpty) pw.Text('Initial notes: $initNotes'),
          if (initScales.isEmpty && initNotes.isEmpty)
            pw.Text('(no baseline scales or notes)'),
        ],
        pw.SizedBox(height: 8),

        // (c) Session data table (recording blocks, lateral L/R rows).
        pw.Header(level: 1, text: 'Session data'),
        if (tableData.isEmpty)
          pw.Text('No recording blocks in this session.')
        else
          pw.TableHelper.fromTextArray(
            headerStyle: const pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellStyle: cellStyle,
            cellAlignment: pw.Alignment.centerLeft,
            headers: tableHeaders,
            data: tableData,
          ),
        pw.SizedBox(height: 8),

        // (d) Electrode configuration — text-only for v1 (see the TODO at
        // the top of this file about embedding the electrode painter).
        // Before the programming summary, matching the desktop section order.
        pw.Header(level: 1, text: 'Electrode configuration'),
        if (latestInit == null && latestFinal == null)
          pw.Text('No electrode configuration recorded.')
        else ...[
          if (electrodeModel.isNotEmpty)
            pw.Text('Electrode model: $electrodeModel'),
          if (latestInit != null) ...[
            pw.SizedBox(height: 4),
            pw.Text('Initial settings',
                style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text('  Left:  anode ${latestInit.leftAnode}  |  '
                'cathode ${latestInit.leftCathode}'),
            pw.Text('  Right: anode ${latestInit.rightAnode}  |  '
                'cathode ${latestInit.rightCathode}'),
          ],
          if (latestFinal != null) ...[
            pw.SizedBox(height: 4),
            pw.Text('Final settings',
                style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text('  Left:  anode ${latestFinal.leftAnode}  |  '
                'cathode ${latestFinal.leftCathode}'),
            pw.Text('  Right: anode ${latestFinal.rightAnode}  |  '
                'cathode ${latestFinal.rightCathode}'),
          ],
        ],
        pw.SizedBox(height: 8),

        // (e) Programming summary (desktop _add_programming_summary math).
        pw.Header(level: 1, text: 'Programming summary'),
        if (rows.isEmpty)
          pw.Text('No session data available.')
        else ...[
          pw.Text('Session duration: $duration'),
          pw.Text('Configurations tested: $numConfigs'),
          pw.Text('Amplitude range:  L: $ampL  |  R: $ampR'),
          pw.Text('Frequency range:  L: $freqL  |  R: $freqR'),
          pw.Text('Pulse width range:  L: $pwL  |  R: $pwR'),
        ],
      ],
    ),
  );
  return doc.save();
}
