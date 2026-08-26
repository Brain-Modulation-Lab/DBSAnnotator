/// Longitudinal PDF report, tablet counterpart of the desktop's DOCX/PDF
/// longitudinal exporter. Pure function over already-parsed data so it is
/// testable headless (no widgets, no platform channels).
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/session/longitudinal.dart' show extractPatientId;

String _fmtValue(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Build the longitudinal report PDF and return its bytes.
///
/// [filenames] are the imported source TSVs (patient ID is extracted from
/// them); [timeline] is scale name -> {block index -> value}, as produced by
/// `scaleTimeline` / the screen's `combinedScaleTimeline`.
///
/// TODO(tablet): embed the fl_chart timeline as an image (capture the chart
/// with RepaintBoundary and pass the PNG in) — for now the report carries
/// the per-block table only.
Future<Uint8List> buildLongitudinalPdf({
  required List<String> filenames,
  required Map<String, Map<int, double>> timeline,
  DateTime? generatedAt,
}) async {
  final dt = generatedAt ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final date = '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  final patientId = filenames
      .map(extractPatientId)
      .firstWhere((id) => id.isNotEmpty, orElse: () => 'unknown');

  final scales = timeline.keys.toList()..sort();
  final blocks = <int>{for (final m in timeline.values) ...m.keys}.toList()
    ..sort();

  // ponytail: ASCII-only report text so the built-in Helvetica renders it.
  // Bundle a Unicode TTF (Roboto/Noto) as the theme base+fontFallback when the
  // M5 session report adds `µs` and free-text notes.
  final doc = pw.Document();
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
        pw.Header(
          level: 0,
          child: pw.Text(
            'DBS Annotator - Longitudinal report',
            style: const pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Text('Patient: sub-$patientId'),
        pw.Text('Generated on: $date'),
        pw.SizedBox(height: 12),
        pw.Text('Source files',
            style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        if (filenames.isEmpty)
          pw.Text('(none)')
        else
          for (final name in filenames) pw.Bullet(text: name),
        pw.SizedBox(height: 8),
        pw.Header(level: 1, text: 'Scales'),
        if (scales.isEmpty)
          pw.Text('No session scale values found in the imported files.')
        else
          for (final scale in scales)
            pw.Bullet(
              text: () {
                final values = timeline[scale]!.values.toList();
                final min = values.reduce((a, b) => a < b ? a : b);
                final max = values.reduce((a, b) => a > b ? a : b);
                return '$scale: ${values.length} value(s), '
                    'range ${_fmtValue(min)}-${_fmtValue(max)}';
              }(),
            ),
        if (scales.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Header(level: 1, text: 'Scale values per block'),
          pw.TableHelper.fromTextArray(
            headerStyle: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerRight,
            cellAlignments: {0: pw.Alignment.centerLeft},
            headers: ['Block', ...scales],
            data: [
              for (final block in blocks)
                [
                  '$block',
                  for (final scale in scales)
                    switch (timeline[scale]![block]) {
                      null => '',
                      final v => _fmtValue(v),
                    },
                ],
            ],
          ),
        ],
      ],
    ),
  );
  return doc.save();
}
