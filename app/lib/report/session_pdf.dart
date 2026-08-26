/// Session (Complete-Workflow) PDF report, tablet counterpart of the
/// desktop's DOCX/PDF session exporter
/// (src/dbs_annotator/utils/session_exporter.py, `_export_to_word_path`).
/// Pure function over already-parsed [SessionRow]s so it is testable
/// headless (no widgets, no platform channels beyond the optional font
/// asset, which falls back to Helvetica when absent).
///
/// Section order mirrors the desktop report: title/patient header, initial
/// clinical notes, session data table, electrode configuration, programming
/// summary. All row math lives in report_data.dart, shared with the Word
/// (.docx) builder so the two formats never drift.
///
/// Graphics come in as PNG bytes the caller rasterised: the scales-timeline
/// chart (ui/scales_chart_painter.dart) and the electrode leads
/// (ui/report_images.dart). The desktop does the same — its chart is a
/// matplotlib PNG embedded in the DOCX its PDF is converted from — so the PDF
/// and Word reports here are guaranteed to show the identical graphic, and the
/// builder stays a pure function that needs no Flutter engine.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/session/scale_scoring.dart' show ScalePref;
import '../core/session/session_row.dart';
import 'report_data.dart';
import 'report_fonts.dart';
import 'report_text.dart';

/// A PNG scaled to exactly [width] points, height following its aspect ratio.
///
/// Always size an embedded image explicitly: dart_pdf lays a bare `pw.Image`
/// out at the PNG's PIXEL dimensions, so a print-resolution raster silently
/// becomes a widget hundreds of points tall and the whole page fails to
/// generate.
pw.Widget _fitWidth(Uint8List png, double width) {
  final image = pw.MemoryImage(png);
  final w = image.width ?? 0;
  final h = image.height ?? 0;
  return pw.Image(
    image,
    width: width,
    height: w > 0 ? width * h / w : null,
  );
}

/// One labelled electrode image ("Left"/"Right") for the config grid; an empty
/// placeholder when that PNG is absent.
pw.Widget _electrodeImageCell(String label, Uint8List? png) {
  if (png == null) return pw.SizedBox(width: 130);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
      pw.Image(pw.MemoryImage(png), height: 170),
    ],
  );
}

/// Optional pre-rendered electrode PNGs (Initial/Final × L/R) from the screen's
/// `renderElectrodePng`. When absent (e.g. headless tests) the electrode
/// section falls back to anode/cathode token text.
typedef ElectrodeReportImages = ({
  Uint8List? initLeft,
  Uint8List? initRight,
  Uint8List? finalLeft,
  Uint8List? finalRight,
});

/// Green row fills for the best / second-best block, from the shared tokens.
const _bestFill = PdfColor.fromInt(kBestFill);
const _secondFill = PdfColor.fromInt(kSecondFill);

/// Legend + scale targets + disclaimer, shown under the table whenever a
/// ranking was applied. Mirrors `report_common.add_table_legend`.
List<pw.Widget> _legendBlock(SessionReportData data) {
  if (data.bestBlocks.isEmpty && data.secondBlocks.isEmpty) return const [];
  pw.Widget swatch(PdfColor fill, String label) => pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Container(width: 10, height: 8, color: fill),
          pw.SizedBox(width: 4),
          pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        ],
      );
  return [
    pw.SizedBox(height: 4),
    pw.Row(children: [
      pw.Text('Legend: ',
          style:
              const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      swatch(_bestFill, 'Optimal configuration'),
      pw.SizedBox(width: 14),
      swatch(_secondFill, 'Second-best configuration'),
    ]),
    if (data.targetsText.isNotEmpty)
      pw.Text('Scale targets: ${data.targetsText}',
          style: const pw.TextStyle(fontSize: 9)),
    pw.SizedBox(height: 2),
    pw.Text(kRankingDisclaimer,
        style: const pw.TextStyle(
            fontSize: 9, fontStyle: pw.FontStyle.italic)),
  ];
}

/// Build the session-report PDF and return its bytes.
///
/// [rows] are the programming-session rows (baseline + recording blocks, as
/// parsed by `parseSessionTsv` or authored in the session screen); [subjectId]
/// is the BIDS subject label (without the "sub-" prefix). [electrodeImages] and
/// [chartPng], when supplied by the screen, render the electrode section as
/// lead images and the session-data section as the shared timeline chart.
/// [scalePrefs] carries per-scale optimisation modes; omit for the desktop's
/// defaults.
Future<Uint8List> buildSessionPdf({
  required List<SessionRow> rows,
  required String subjectId,
  DateTime? generatedAt,
  ElectrodeReportImages? electrodeImages,
  Uint8List? chartPng,
  List<ScalePref>? scalePrefs,
  PdfPageFormat pageFormat = PdfPageFormat.a4,
}) async {
  final data = buildSessionReportData(
    rows: rows,
    generatedAt: generatedAt,
    scalePrefs: scalePrefs,
  );

  // Prefer rendered electrode images when the screen supplied them.
  final ei = electrodeImages;
  final hasElectrodeImages = ei != null &&
      (ei.initLeft != null ||
          ei.initRight != null ||
          ei.finalLeft != null ||
          ei.finalRight != null);

  // Row index -> fill, for the green best/second-best shading. tableData holds
  // two rows (L then R) per block in block order, and TableHelper counts the
  // header as row 0, hence the +1.
  final rowFills = <int, PdfColor>{};
  for (var i = 0; i < data.tableData.length; i++) {
    final block = int.tryParse(data.tableData[i].first);
    if (block == null) continue;
    if (data.bestBlocks.contains(block)) {
      rowFills[i + 1] = _bestFill;
    } else if (data.secondBlocks.contains(block)) {
      rowFills[i + 1] = _secondFill;
    }
  }

  // Unicode theme when the IBM Plex assets are bundled; null -> built-in
  // Helvetica, which can only encode Latin-1. dart_pdf does not throw on an
  // unsupported rune — it silently draws an empty placeholder box — so without
  // the sanitiser a smart apostrophe from an iPad note would leave a blank
  // rectangle in a clinical document with no error. See report_text.dart.
  final theme = await loadReportTheme();
  final t = ReportTextSanitiser(active: theme == null);
  final tableData = t.rows(data.tableData);
  final doc = theme == null ? pw.Document() : pw.Document(theme: theme);
  const cellStyle = pw.TextStyle(fontSize: 8);
  doc.addPage(
    pw.MultiPage(
      pageFormat: pageFormat,
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
        pw.Text('Patient: sub-${t(subjectId)}    Session: ${data.date}'),
        pw.Text('Generated on: ${data.date}'),
        pw.SizedBox(height: 12),

        // (b) Initial clinical notes (latest baseline session).
        pw.Header(level: 1, text: 'Initial clinical notes'),
        if (!data.hasInitial)
          pw.Text('No baseline (is_initial = 1) rows recorded.')
        else ...[
          for (final pair in data.initScales)
            pw.Bullet(text: '${t(pair.name)}: ${t(pair.value)}'),
          if (data.initNotes.isNotEmpty)
            pw.Text('Initial notes: ${t(data.initNotes)}'),
          if (data.initScales.isEmpty && data.initNotes.isEmpty)
            pw.Text('(no baseline scales or notes)'),
        ],
        pw.SizedBox(height: 8),

        // (c) Session data: the scales-timeline graph, then the lateral table.
        pw.Header(level: 1, text: 'Session data'),
        if (chartPng != null) ...[
          // Size explicitly to the content width, preserving the aspect ratio.
          // A bare pw.Image lays the PNG out at its PIXEL size — the chart is
          // rasterised at 3x for print, so that is ~1128 pt tall and dart_pdf
          // throws "Widget won't fit into the page".
          _fitWidth(chartPng, pageFormat.availableWidth),
          pw.SizedBox(height: 8),
        ] else if (!data.chart.isEmpty)
          // The screen didn't rasterise one (headless caller); say so rather
          // than silently omitting the section's main graphic.
          pw.Text('(scales timeline chart unavailable)',
              style: const pw.TextStyle(
                  fontSize: 8, color: PdfColors.grey600)),
        if (!data.hasRecording)
          pw.Text('No recording blocks in this session.')
        else ...[
          pw.TableHelper.fromTextArray(
            headerStyle: const pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellStyle: cellStyle,
            cellAlignment: pw.Alignment.centerLeft,
            headers: sessionTableHeaders,
            data: tableData,
            // Green shading for the best / second-best blocks.
            cellDecoration: (col, dynamic cell, row) =>
                rowFills[row] == null
                    ? const pw.BoxDecoration()
                    : pw.BoxDecoration(color: rowFills[row]),
          ),
          ..._legendBlock(data),
        ],
        pw.SizedBox(height: 8),

        // (d) Electrode configuration: rendered lead images (Initial/Final ×
        // L/R) when the screen supplied them, else anode/cathode token text.
        // Before the programming summary, matching the desktop section order.
        pw.Header(level: 1, text: 'Electrode configuration'),
        if (!data.hasElectrodeConfig)
          pw.Text('No electrode configuration recorded.')
        else ...[
          if (data.electrodeModel.isNotEmpty)
            pw.Text('Electrode model: ${t(data.electrodeModel)}'),
          pw.SizedBox(height: 4),
          if (hasElectrodeImages) ...[
            pw.Text('Initial settings',
                style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Row(children: [
              _electrodeImageCell('Left', ei.initLeft),
              pw.SizedBox(width: 24),
              _electrodeImageCell('Right', ei.initRight),
            ]),
            pw.SizedBox(height: 8),
            pw.Text('Final settings',
                style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Row(children: [
              _electrodeImageCell('Left', ei.finalLeft),
              pw.SizedBox(width: 24),
              _electrodeImageCell('Right', ei.finalRight),
            ]),
          ] else ...[
            if (data.initialTokens != null) ...[
              pw.Text('Initial settings',
                  style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('  Left:  anode ${t(data.initialTokens!.leftAnode)}  |  '
                  'cathode ${t(data.initialTokens!.leftCathode)}'),
              pw.Text('  Right: anode ${t(data.initialTokens!.rightAnode)}  |  '
                  'cathode ${t(data.initialTokens!.rightCathode)}'),
            ],
            if (data.finalTokens != null) ...[
              pw.SizedBox(height: 4),
              pw.Text('Final settings',
                  style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('  Left:  anode ${t(data.finalTokens!.leftAnode)}  |  '
                  'cathode ${t(data.finalTokens!.leftCathode)}'),
              pw.Text('  Right: anode ${t(data.finalTokens!.rightAnode)}  |  '
                  'cathode ${t(data.finalTokens!.rightCathode)}'),
            ],
          ],
        ],
        pw.SizedBox(height: 8),

        // (e) Programming summary (desktop _add_programming_summary math).
        pw.Header(level: 1, text: 'Programming summary'),
        if (!data.hasRows)
          pw.Text('No session data available.')
        else ...[
          pw.Text('Session duration: ${data.duration}'),
          pw.Text('Configurations tested: ${data.numConfigs}'),
          pw.Text('Amplitude range:  L: ${data.ampL}  |  R: ${data.ampR}'),
          pw.Text('Frequency range:  L: ${data.freqL}  |  R: ${data.freqR}'),
          pw.Text('Pulse width range:  L: ${data.pwL}  |  R: ${data.pwR}'),
        ],
      ],
    ),
  );
  return doc.save();
}
