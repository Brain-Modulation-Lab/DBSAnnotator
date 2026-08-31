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

import '../app_info.dart' show appVersion;
import 'report_data.dart';
import 'report_fonts.dart';
import 'report_sections.dart';
import 'report_text.dart';

/// Page margins, matching the desktop report's document (0.5 in sides,
/// 0.75 in top/bottom) rather than dart_pdf's 2 cm default.
///
/// This is not cosmetic: the Word builder uses the desktop's margins, so with
/// dart_pdf's the same "a quarter of the content width" formula produced
/// 114.5 pt leads in the PDF and 126.3 pt in Word for identical data. Matching
/// the geometry is what actually makes the two documents agree — and it gives
/// the ten-column table 523 pt instead of 482 pt.
const _marginSide = 36.0; // 0.5 in
const _marginEnd = 54.0; // 0.75 in

/// Horizontal gap between electrode cells, in POINTS. The Word builder converts
/// it to px at 96 dpi, so the leads are the same physical size in both.
const kElectrodeCellGapPt = 6.0;

/// "Scales rated per block: 5 throughout." / "..: 3-5, so blocks are not
/// directly comparable." Null when nothing was rated.
String? _ratedNote(SessionReportData data) {
  final counts = data.scalesRated.values.toSet();
  if (counts.isEmpty) return null;
  if (counts.length == 1) {
    return 'Scales rated per block: ${counts.first} throughout.';
  }
  final lo = counts.reduce((a, b) => a < b ? a : b);
  final hi = counts.reduce((a, b) => a > b ? a : b);
  return 'Scales rated per block: $lo-$hi. The index averages only the scales '
      'rated at each block, so blocks with different rated sets are not '
      'directly comparable.';
}

/// One lead's configuration in words, for the caption under its drawing.
String _leadDetail(LateralTokens? tokens, bool left) =>
    tokens == null ? '' : lateralText(tokens, left: left);

/// One decimal unless the value is whole — so a delta reads "-5" not "-5.0".
String _num(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  var out = v.toStringAsFixed(2);
  while (out.endsWith('0')) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

/// A signed delta: "-5", "+0.25", or "0" for no change — never "+0".
String _delta(double v) => v == 0 ? '0' : '${v > 0 ? '+' : ''}${_num(v)}';

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

/// One column of the electrode grid: a caption and, under it, that lead.
///
/// [width] is a fixed quarter of the content area, so all four leads come out
/// the same size — and the same size as the Word document's, which quarters the
/// content area too. Sizing by HEIGHT (as this used to) makes the drawn width
/// depend on the raster's aspect ratio, which is why the PDF's leads were 80 pt
/// wide against Word's 126 pt for identical data.
///
/// A missing lead still occupies its full cell. The old placeholder was a
/// zero-height `SizedBox(width: 130)`, so one absent lead shifted the others
/// sideways and shortened the row.
pw.Widget _electrodeCell(String caption, Uint8List? png, double width,
    {double? imageHeight, String detail = ''}) {
  return pw.SizedBox(
    width: width,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(caption, style: const pw.TextStyle(fontSize: 8)),
        // The configuration in words, under its own lead. The drawing shows
        // WHICH contacts are active but not how the current is shared between
        // them, so `2b 60% / 2c 40%` and its reverse are the same picture -
        // and for current steering that split IS the configuration.
        if (detail.isNotEmpty)
          pw.Text(detail,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 6.5)),
        pw.SizedBox(height: 2),
        if (png != null)
          _fitWidth(png, width)
        else
          pw.SizedBox(
            height: imageHeight,
            child: pw.Center(
              child: pw.Text('(not recorded)',
                  style: const pw.TextStyle(
                      fontSize: 7, color: PdfColors.grey600)),
            ),
          ),
      ],
    ),
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
List<pw.Widget> _legendBlock(SessionReportData data, ReportTextSanitiser t) {
  // No targets, no ranking, and the document says so rather than leaving the
  // reader to wonder why nothing is green.
  if (!data.hasTargets) {
    return [
      pw.SizedBox(height: 4),
      pw.Text(t(data.targetsText),
          style: const pw.TextStyle(
              fontSize: 9, fontStyle: pw.FontStyle.italic)),
    ];
  }
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
      swatch(_bestFill, 'Highest aggregate index (rank 1)'),
      pw.SizedBox(width: 14),
      swatch(_secondFill, 'Second highest (rank 2)'),
    ]),
    if (data.targetsText.isNotEmpty)
      pw.Text('Scale targets: ${t(data.targetsText)}',
          style: const pw.TextStyle(fontSize: 9)),
    // The index averages only the scales rated AT that block, so blocks with
    // different rated sets are not comparable — one where a single low scale
    // was rated can outrank a fully-rated block.
    if (_ratedNote(data) != null)
      pw.Text(_ratedNote(data)!, style: const pw.TextStyle(fontSize: 8)),
    // Which blocks the top setting covers, and what a margin on this index is
    // actually worth in this session.
    if (data.bestSettingText.isNotEmpty)
      pw.Text(data.bestSettingText, style: const pw.TextStyle(fontSize: 8)),
    if (data.rankingResolutionNote != null)
      pw.Text(data.rankingResolutionNote!,
          style: const pw.TextStyle(fontSize: 8)),
    // State the method, not just the modes: the equal weighting across every
    // scale is a clinical judgement and was invisible.
    pw.Text(data.indexMethod, style: const pw.TextStyle(fontSize: 8)),
    pw.SizedBox(height: 2),
    pw.Text(kRankingDisclaimer,
        style: const pw.TextStyle(
            fontSize: 9, fontStyle: pw.FontStyle.italic)),
  ];
}

/// Build the session-report PDF.
///
/// Takes the **already-computed** [data] rather than raw rows. The caller needs
/// it anyway (to rasterise the chart and pick the electrode rows), and computing
/// it twice meant `DateTime.now()` ran twice — so an export at 23:59:59.999 could
/// print two different dates in one document. Passing it in also guarantees the
/// PDF and the Word document are built from identical numbers and identical
/// scale targets.
///
/// [subjectId] is the BIDS subject label (without the "sub-" prefix).
/// [electrodeImages] and [chartPng], when supplied, render the electrode section
/// as lead images and the session-data section as the shared timeline chart.
///
/// [sections] gates each section; the title/patient header is always present, so
/// the document is never anonymous.
Future<ReportBytes> buildSessionPdf({
  required SessionReportData data,
  required String subjectId,
  ElectrodeReportImages? electrodeImages,
  Uint8List? chartPng,
  PdfPageFormat pageFormat = PdfPageFormat.a4,
  Set<ReportSection> sections = kAllReportSections,
}) async {
  // Prefer rendered electrode images when the screen supplied them.
  //
  // Document properties first: the PDF carried no /Info dictionary at all, so
  // once the file is in a document system its filename was the only clue to
  // what it is.
  final ei = electrodeImages;
  final hasElectrodeImages = ei != null &&
      (ei.initLeft != null ||
          ei.initRight != null ||
          ei.finalLeft != null ||
          ei.finalRight != null);

  // Row index -> fill, for the green best/second-best shading. tableData holds
  // two rows (L then R) per block in block order, and TableHelper counts the
  // header as row 0, hence the +1.
  // Data-row indices that begin a new block. TableHelper counts the header as
  // row 0, and `cellDecoration` is called with the same numbering.
  final blockStartRows = <int>{};
  var previousLabel = '';
  for (var i = 0; i < data.tableData.length; i++) {
    final label = data.tableData[i].first;
    if (label != previousLabel) {
      if (i > 0) blockStartRows.add(i + 1);
      previousLabel = label;
    }
  }

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
  // Document properties. The PDF carried NO /Info dictionary at all, so once
  // the file reached a document system its filename was the only clue to what
  // it was, who made it or when.
  final title = 'DBS session report - sub-$subjectId - ${data.sessionDate}';
  final doc = pw.Document(
    theme: theme,
    title: title,
    author: 'DBS Annotator v$appVersion',
    creator: 'DBS Annotator v$appVersion',
    subject: 'Deep brain stimulation programming session',
  );
  const cellStyle = pw.TextStyle(fontSize: 8);
  final wantsChart = sections.contains(ReportSection.chart);
  final wantsTable = sections.contains(ReportSection.table);

  // Same margins as the Word document, so "a quarter of the content width"
  // means the same number of points in both.
  final format = pageFormat.copyWith(
    marginLeft: _marginSide,
    marginRight: _marginSide,
    marginTop: _marginEnd,
    marginBottom: _marginEnd,
  );

  // A quarter of the content width per lead, less a little breathing room —
  // the same budget the Word builder uses. The height is only needed for the
  // missing-lead placeholder, and follows the renderer's 900x1920 aspect.
  final leadWidth = format.availableWidth / 4 - kElectrodeCellGapPt;
  final leadHeight = leadWidth * 1920 / 900;
  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      // Every page attributable on its own. Page numbers alone left a
      // continuation page that escaped the staple with no patient, no date and
      // no provenance — the .docx had no footer at all. Both formats now carry
      // the same line.
      footer: (context) => pw.Container(
        alignment: pw.Alignment.center,
        margin: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          'sub-${t(subjectId)}  |  ${data.sessionStamp}  |  '
          'DBS Annotator v$appVersion  |  '
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
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
        pw.Text('Patient: sub-${t(subjectId)}    '
            'Session: ${data.sessionStamp}'),
        pw.Text(
            'Generated on: ${data.generatedOn} by DBS Annotator v$appVersion'
            '${data.sourceFile.isEmpty ? '' : '  |  Source: '
                '${t(data.sourceFile)} (${data.rowCount} rows)'}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 8),

        // The one thing the clinician looks for first: what the patient left
        // on. Deliberately labelled "last recorded", not "final" — nothing in
        // the TSV says a clinician confirmed it.
        if (data.lastConfig.isNotEmpty) ...[
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border.all(color: PdfColors.grey500, width: 0.8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Arrived on | left on, side by side. The question the next
                    // clinician asks first is what changed, and answering it
                    // used to mean diffing block 1 against block 7 by eye.
                    if (data.firstConfig.isNotEmpty)
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('At start of session',
                                style: const pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.grey700)),
                            for (final e in data.firstConfig.entries)
                              pw.Text('${e.key}:  ${t(e.value)}',
                                  style: const pw.TextStyle(fontSize: 9)),
                          ],
                        ),
                      ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Last recorded configuration',
                              style: const pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold)),
                          for (final e in data.lastConfig.entries)
                            pw.Text('${e.key}:  ${t(e.value)}',
                                style: const pw.TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (data.configChanges.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  for (final line in data.configChanges)
                    pw.Text('Changed: ${t(line)}',
                        style: const pw.TextStyle(fontSize: 9)),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 12),
        ],

        // (b) Initial clinical notes (latest baseline session).
        if (sections.contains(ReportSection.baseline)) ...[
          pw.Header(level: 1, text: 'Baseline assessment (pre-session)'),
          if (!data.hasInitial)
            pw.Text('No baseline (is_initial = 1) rows recorded.')
          else ...[
            if (data.initScales.isNotEmpty)
              pw.TableHelper.fromTextArray(
                headers: const ['Scale', 'Score'],
                data: [
                  for (final pair in data.initScales)
                    [t(pair.name), t(pair.value)],
                ],
                cellStyle: const pw.TextStyle(fontSize: 9),
                headerStyle: const pw.TextStyle(
                    fontSize: 9, fontWeight: pw.FontWeight.bold),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey300),
                cellAlignment: pw.Alignment.centerLeft,
                columnWidths: const {
                  0: pw.FlexColumnWidth(4),
                  1: pw.FlexColumnWidth(1),
                },
                // A quarter of the page is plenty for a scale list; full width
                // would strand the two columns at opposite edges.
                tableWidth: pw.TableWidth.min,
              ),
            if (data.initNotes.isNotEmpty)
              pw.Text('Notes: ${t(data.initNotes)}'),
            if (data.initScales.isEmpty && data.initNotes.isEmpty)
              pw.Text('(no baseline scales or notes)'),
          ],
          pw.SizedBox(height: 8),
        ],

        // (c) Session data: the scales-timeline graph, then the lateral table.
        // Graph and table are independent sections, so the heading appears only
        // when at least one of them does.
        if (wantsChart || wantsTable) ...[
          pw.Header(level: 1, text: 'Session data'),
          if (wantsChart && chartPng != null) ...[
            // Size explicitly to the content width, preserving the aspect
            // ratio. A bare pw.Image lays the PNG out at its PIXEL size — the
            // chart is rasterised at 3x for print, so that is ~1128 pt tall and
            // dart_pdf throws "Widget won't fit into the page".
            _fitWidth(chartPng, format.availableWidth),
            // A real caption: subject, session, n, and what the green means.
            // Extracted from a .docx the figure travels alone.
            pw.Text(t(data.figureCaption),
                style: const pw.TextStyle(
                    fontSize: 8, fontStyle: pw.FontStyle.italic)),
            pw.SizedBox(height: 8),
          ] else if (wantsChart && !data.chart.isEmpty)
            // The screen didn't rasterise one (headless caller); say so rather
            // than silently omitting the section's main graphic.
            pw.Text('(scales timeline chart unavailable)',
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey600)),
          if (wantsTable && !data.hasRecording)
            pw.Text('No recording blocks in this session.')
          else if (wantsTable) ...[
            pw.TableHelper.fromTextArray(
              headerStyle: const pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellStyle: cellStyle,
              cellAlignment: pw.Alignment.centerLeft,
              headers: sessionTableHeaders,
              data: tableData,
              columnWidths: {
                for (final (i, w) in sessionTableColumnWeights.indexed)
                  i: pw.FlexColumnWidth(w),
              },
              // Green shading for the best / second-best blocks, plus a heavy
              // rule where one BLOCK ends and the next begins. The rule used to
              // be absent from the PDF entirely, so its inside borders drew an
              // identical line between a block's own L and R rows as between
              // two different blocks — nothing said where a configuration
              // started. (Word has had this via `rowRules` all along.)
              cellDecoration: (col, dynamic cell, row) {
                final fill = rowFills[row];
                final isBoundary = blockStartRows.contains(row);
                if (fill == null && !isBoundary) {
                  return const pw.BoxDecoration();
                }
                return pw.BoxDecoration(
                  color: fill,
                  border: isBoundary
                      ? const pw.Border(
                          top: pw.BorderSide(width: 1.6, color: PdfColors.black))
                      : null,
                );
              },
            ),
            ..._legendBlock(data, t),
          ],
          pw.SizedBox(height: 8),
        ],

        // (d) Electrode configuration: rendered lead images (Initial/Final ×
        // L/R) when the screen supplied them, else anode/cathode token text.
        // Before the programming summary, matching the desktop section order.
        // Wrapped so the heading, the model line, the column captions and the
        // four leads cannot be split: the merged Initial/Final header used to
        // sit at the foot of one page with its figures on the next, which reads
        // as a printing fault.
        if (sections.contains(ReportSection.electrodes))
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Header(level: 1, text: 'Electrode configuration'),
          if (!data.hasElectrodeConfig)
            pw.Text('No electrode configuration recorded.')
          else ...[
            if (data.electrodeModel.isNotEmpty)
              pw.Text('Electrode model: ${t(data.electrodeModel)}'),
            pw.SizedBox(height: 4),
            if (hasElectrodeImages) ...[
              // ONE row of four leads under a merged Initial/Final header, as
              // Word and the desktop lay it out. Two stacked rows cost ~380 pt
              // of height, which is why this section used to break across
              // pages; 4 x ~114 pt of width fits in 482 pt and halves that.
              pw.Row(children: [
                for (final title in ['Initial settings', 'Final settings'])
                  pw.SizedBox(
                    width: leadWidth * 2,
                    child: pw.Text(title,
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(
                            fontWeight: pw.FontWeight.bold)),
                  ),
              ]),
              pw.SizedBox(height: 2),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _electrodeCell('Left', ei.initLeft, leadWidth,
                      imageHeight: leadHeight,
                      detail: t(_leadDetail(data.initialTokens, true))),
                  _electrodeCell('Right', ei.initRight, leadWidth,
                      imageHeight: leadHeight,
                      detail: t(_leadDetail(data.initialTokens, false))),
                  _electrodeCell('Left', ei.finalLeft, leadWidth,
                      imageHeight: leadHeight,
                      detail: t(_leadDetail(data.finalTokens, true))),
                  _electrodeCell('Right', ei.finalRight, leadWidth,
                      imageHeight: leadHeight,
                      detail: t(_leadDetail(data.finalTokens, false))),
                ],
              ),
              // A key, because the drawing encodes polarity by COLOUR alone -
              // useless on a mono printer or to a colour-blind reader.
              pw.SizedBox(height: 3),
              pw.Text(
                  'Red = anode (+)   Blue = cathode (-)   Grey = inactive.   '
                  "A percentage is that contact's share of the total current.",
                  style: const pw.TextStyle(
                      fontSize: 7, color: PdfColors.grey700)),
            ] else ...[
              // Text fallback (no rasteriser available). Vendor nomenclature
              // here too — the raw `E2b_E2c` tokens are internal identifiers,
              // and printing them in one place and `2b(3.3)` in another
              // described the same lead two ways.
              for (final pair in [
                ('Initial settings', data.initialTokens),
                ('Last recorded settings', data.finalTokens),
              ])
                if (pair.$2 != null) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(pair.$1,
                      style:
                          const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('  Left:   ${t(lateralText(pair.$2!, left: true))}'),
                  pw.Text('  Right:  ${t(lateralText(pair.$2!, left: false))}'),
                ],
            ],
          ],
          pw.SizedBox(height: 8),
        ]),

        // (e) Programming summary (desktop _add_programming_summary math).
        if (sections.contains(ReportSection.summary)) ...[
          pw.Header(level: 1, text: 'Programming summary'),
          if (!data.hasRows)
            pw.Text('No session data available.')
          else ...[
            pw.Text('Annotation span (first to last entry): ${data.span}'),
            pw.Text('Configurations tested: ${configCountText(data)}'),
            pw.Text('Amplitude:  L: ${data.ampL}  |  R: ${data.ampR}'),
            pw.Text('Frequency:  L: ${data.freqL}  |  R: ${data.freqR}'),
            pw.Text('Pulse width:  L: ${data.pwL}  |  R: ${data.pwR}'),

            // The response half of a dose-response record. Every parameter got
            // a range above and no scale did, so the clinical bottom line of
            // the encounter appeared nowhere in the document.
            if (data.response.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text('Response (first to last rated block)',
                  style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              for (final r in data.response)
                pw.Text('  ${t(r.name)}: '
                    '${_num(r.first)} -> ${_num(r.last)} '
                    '(${_delta(r.last - r.first)})'),
            ],

            // Anomalies the reader should not have to spot unaided.
            if (data.anomalies.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text('Data notes',
                  style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              for (final line in data.anomalies)
                pw.Bullet(
                    text: t(line),
                    style: const pw.TextStyle(fontSize: 9),
                    bulletSize: 1.5),
            ],

            // The notes column holds the only adverse-event data the format
            // captures, and inside a fourteen-row table nobody reads it.
            // What the numbers are, and what the record cannot say about them.
            pw.SizedBox(height: 6),
            pw.Text(data.instrumentNote,
                style: const pw.TextStyle(
                    fontSize: 8, fontStyle: pw.FontStyle.italic)),

            if (data.observations.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text('Recorded observations',
                  style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              for (final line in data.observations)
                pw.Bullet(
                    text: t(line),
                    style: const pw.TextStyle(fontSize: 9),
                    bulletSize: 1.5),
            ],
          ],
        ],
        // Attestation. The document otherwise asserts that a machine produced
        // it and that no human stands behind it.
        pw.SizedBox(height: 18),
        pw.Text('Attestation',
            style: const pw.TextStyle(
                fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),
        pw.Row(
          children: [
            for (final label in ['Recorded by', 'Reviewed by', 'Date'])
              pw.Expanded(
                child: pw.Container(
                  margin: const pw.EdgeInsets.only(right: 16),
                  padding: const pw.EdgeInsets.only(top: 14),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      top: pw.BorderSide(color: PdfColors.grey600, width: 0.8),
                    ),
                  ),
                  child: pw.Text(label,
                      style: const pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey700)),
                ),
              ),
          ],
        ),
      ],
    ),
  );
  return (bytes: await doc.save(), lostCharacters: t.lostCharacters);
}
