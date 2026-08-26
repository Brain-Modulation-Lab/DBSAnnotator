/// Session (Complete-Workflow) Word (.docx) report — the tablet counterpart of
/// the desktop's DOCX exporter (src/dbs_annotator/utils/session_exporter.py).
///
/// A .docx is a zip of OOXML parts, built here by hand with the `archive`
/// package, so this stays a PURE function over already-parsed [SessionRow]s (no
/// widgets, no platform channels) and is headless-testable.
///
/// Sections and row math are shared with the PDF via report_data.dart, and the
/// graphics are the *same PNG bytes* the PDF embeds, so the two formats cannot
/// drift: the scales-timeline chart (ui/scales_chart_painter.dart) and the four
/// electrode leads (ui/report_images.dart) are passed in by the caller.
///
/// Unlike the PDF there is no font concern here — the XML is UTF-8 and Word uses
/// system fonts, so any character renders correctly without sanitising.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/session/session_row.dart';
import '../core/session/scale_scoring.dart' show ScalePref;
import 'report_data.dart';
import 'session_pdf.dart' show ElectrodeReportImages;

/// XML-escape text content (&, <, > and, for safety, quotes).
String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// A run of text (size in half-points), with embedded newlines turned into
/// `<w:br/>` so multi-line table cells / notes wrap inside one paragraph.
String _run(String text, {bool bold = false, int size = 20}) {
  final rPr = '<w:rPr>${bold ? '<w:b/>' : ''}'
      '<w:sz w:val="$size"/><w:szCs w:val="$size"/></w:rPr>';
  final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final parts = <String>[];
  for (var i = 0; i < lines.length; i++) {
    if (i > 0) parts.add('<w:br/>');
    parts.add('<w:t xml:space="preserve">${_esc(lines[i])}</w:t>');
  }
  return '<w:r>$rPr${parts.join()}</w:r>';
}

/// A body paragraph.
String _para(String text, {bool bold = false, int size = 20}) =>
    '<w:p>${_run(text, bold: bold, size: size)}</w:p>';

/// A section heading (14pt bold, with spacing above).
String _heading(String text) =>
    '<w:p><w:pPr><w:spacing w:before="240" w:after="60"/></w:pPr>'
    '${_run(text, bold: true, size: 28)}</w:p>';

/// One table cell (8pt to match the PDF), optionally bold / shaded / ruled.
String _cell(String text,
    {bool bold = false, String? fill, bool topRule = false}) {
  final shd = fill == null
      ? ''
      : '<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>';
  // 3 pt (sz=24) top border, the desktop's block separator.
  final borders = topRule
      ? '<w:tcBorders><w:top w:val="single" w:sz="24" w:space="0" '
          'w:color="auto"/></w:tcBorders>'
      : '';
  return '<w:tc><w:tcPr>$shd$borders</w:tcPr>'
      '<w:p>${_run(text, bold: bold, size: 16)}</w:p></w:tc>';
}

/// One table row. [fill] shades every cell (the green best/second-best
/// highlight); [topRule] draws the 3 pt rule the desktop uses to separate
/// blocks.
String _tr(List<String> cells,
        {bool header = false, String? fill, bool topRule = false}) =>
    '<w:tr>${cells.map((c) => _cell(
          c,
          bold: header,
          fill: header ? 'D9D9D9' : fill,
          topRule: topRule,
        )).join()}</w:tr>';

/// A bordered table with a shaded header row. [rowFills] and [rowRules] are
/// keyed by data-row index.
String _table(
  List<String> headers,
  List<List<String>> rows, {
  Map<int, String> rowFills = const {},
  Set<int> rowRules = const {},
}) {
  final b = StringBuffer('<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/>'
      '<w:tblBorders>');
  for (final side in ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']) {
    b.write('<w:$side w:val="single" w:sz="4" w:space="0" w:color="auto"/>');
  }
  b.write('</w:tblBorders></w:tblPr>');
  b.write(_tr(headers, header: true));
  for (var i = 0; i < rows.length; i++) {
    b.write(_tr(rows[i], fill: rowFills[i], topRule: rowRules.contains(i)));
  }
  b.write('</w:tbl>');
  return b.toString();
}

/// A borderless table, used for the electrode-image grid so the images sit in a
/// clean 4-column layout with no visible cell edges (the desktop does the same
/// with explicit `w:val="none"` borders).
String _borderlessTable(List<String> rowsXml) {
  final b = StringBuffer('<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/>'
      '<w:tblBorders>');
  for (final side in ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']) {
    b.write('<w:$side w:val="none" w:sz="0" w:space="0" w:color="auto"/>');
  }
  b.write('</w:tblBorders></w:tblPr>');
  b.writeAll(rowsXml);
  b.write('</w:tbl>');
  return b.toString();
}

/// A centred cell holding arbitrary run XML, optionally spanning [span]
/// columns.
String _xmlCell(String runsXml, {int span = 1}) {
  final grid = span > 1 ? '<w:gridSpan w:val="$span"/>' : '';
  return '<w:tc><w:tcPr>$grid</w:tcPr>'
      '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>$runsXml</w:p></w:tc>';
}

/// A centred text cell for the electrode grid's caption rows.
String _captionCell(String text, {bool bold = false, int span = 1}) =>
    _xmlCell(_run(text, bold: bold, size: 16), span: span);

/// "Anode: case / Cathode: E2b" under an electrode image, matching the
/// desktop's per-lead caption.
String _tokenCaption(String? anode, String? cathode) =>
    'Anode: ${anode ?? ''}\nCathode: ${cathode ?? ''}';

/// ARGB int -> the RRGGBB hex Word expects in `w:fill`.
String _hex(int argb) =>
    (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

/// Legend + scale targets + disclaimer under the session-data table, mirroring
/// `report_common.add_table_legend`. Returns '' when nothing was ranked.
String _legendBlock(SessionReportData data) {
  if (data.bestBlocks.isEmpty && data.secondBlocks.isEmpty) return _para('');
  // A coloured square run, standing in for the desktop's coloured "■" glyph.
  String swatch(int argb) =>
      '<w:r><w:rPr><w:sz w:val="18"/><w:shd w:val="clear" w:color="auto" '
      'w:fill="${_hex(argb)}"/></w:rPr><w:t xml:space="preserve">    </w:t></w:r>';
  final b = StringBuffer()
    ..write('<w:p>')
    ..write(_run('Legend: ', bold: true, size: 18))
    ..write(swatch(kBestFill))
    ..write(_run(' Optimal configuration    ', size: 18))
    ..write(swatch(kSecondFill))
    ..write(_run(' Second-best configuration', size: 18))
    ..write('</w:p>');
  if (data.targetsText.isNotEmpty) {
    b.write(_para('Scale targets: ${data.targetsText}', size: 18));
  }
  b.write(_para(kRankingDisclaimer, size: 18));
  return b.toString();
}

const _contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Default Extension="png" ContentType="image/png"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '</Types>';

const _rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '</Relationships>';

/// English Metric Units per pixel at 96 dpi — the unit every OOXML drawing
/// extent is expressed in (1 inch = 914 400 EMU).
const int _emuPerPx = 9525;

/// Page size for the Word report, in twentieths of a point (twips), with the
/// desktop's margins (0.5 in sides, 0.75 in top/bottom).
enum DocxPageSize {
  a4(11906, 16838),
  letter(12240, 15840);

  const DocxPageSize(this.widthTwips, this.heightTwips);

  final int widthTwips, heightTwips;

  static const _sideMarginTwips = 720; // 0.5 in
  static const _endMarginTwips = 1080; // 0.75 in

  /// Usable width in px at 96 dpi, for sizing embedded images.
  double get contentWidthPx =>
      (widthTwips - 2 * _sideMarginTwips) / 1440.0 * 96.0;

  String get sectPr => '<w:sectPr>'
      '<w:pgSz w:w="$widthTwips" w:h="$heightTwips"/>'
      '<w:pgMar w:top="$_endMarginTwips" w:right="$_sideMarginTwips" '
      'w:bottom="$_endMarginTwips" w:left="$_sideMarginTwips" '
      'w:header="708" w:footer="708" w:gutter="0"/>'
      '</w:sectPr>';
}

/// Collects the images a document embeds and emits the OOXML they need: the
/// `word/media/*` parts, the `word/_rels/document.xml.rels` entries, and the
/// `<w:drawing>` run for each placement.
///
/// Word is strict about this: an image needs a media part, a relationship, a
/// `png` content-type default, the `r`/`wp`/`a`/`pic` namespaces on
/// `<w:document>`, and matching `cx`/`cy` extents in both `wp:extent` and
/// `a:ext`. Getting any of it wrong yields a repair prompt rather than a
/// diagnostic, which is why this is centralised in one place.
class _MediaBag {
  final _bytes = <String, Uint8List>{};
  int _next = 1;

  final _relTargets = <String, String>{};

  bool get isEmpty => _bytes.isEmpty;

  /// An inline image run, drawn [widthPx] wide with the PNG's own aspect ratio
  /// preserved (read from its IHDR, so nothing is stretched).
  String drawing(Uint8List png, {required double widthPx}) {
    final n = _next++;
    final id = 'rId$n';
    _bytes['image$n.png'] = png;
    _relTargets[id] = 'media/image$n.png';

    final size = pngSize(png);
    final aspect = size == null ? 1.0 : size.$2 / size.$1;
    final cx = (widthPx * _emuPerPx).round();
    final cy = (widthPx * aspect * _emuPerPx).round();
    final docPrId = n;
    return '<w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/>'
        '<wp:docPr id="$docPrId" name="Picture $docPrId"/>'
        '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:nvPicPr>'
        '<pic:cNvPr id="$docPrId" name="Picture $docPrId"/>'
        '<pic:cNvPicPr/>'
        '</pic:nvPicPr>'
        '<pic:blipFill>'
        '<a:blip r:embed="$id"/>'
        '<a:stretch><a:fillRect/></a:stretch>'
        '</pic:blipFill>'
        '<pic:spPr>'
        '<a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
        '</pic:spPr>'
        '</pic:pic>'
        '</a:graphicData>'
        '</a:graphic>'
        '</wp:inline>'
        '</w:drawing></w:r>';
  }

  /// `word/_rels/document.xml.rels`, or null when no image was embedded.
  String? get relsXml {
    if (_relTargets.isEmpty) return null;
    final b = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    for (final e in _relTargets.entries) {
      b.write('<Relationship Id="${e.key}" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
          'Target="${e.value}"/>');
    }
    b.write('</Relationships>');
    return b.toString();
  }

  Map<String, Uint8List> get media => _bytes;
}

/// Read a PNG's pixel dimensions from its IHDR chunk, so an embedded image
/// keeps its aspect ratio instead of being stretched to a guessed box.
///
/// PNG layout: 8-byte signature, then the IHDR chunk whose data starts at byte
/// 16 with big-endian width and height.
(int, int)? pngSize(Uint8List bytes) {
  if (bytes.length < 24) return null;
  // Signature check, so a non-PNG can't be silently mis-sized.
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < sig.length; i++) {
    if (bytes[i] != sig[i]) return null;
  }
  int be32(int o) =>
      (bytes[o] << 24) | (bytes[o + 1] << 16) | (bytes[o + 2] << 8) | bytes[o + 3];
  final w = be32(16);
  final h = be32(20);
  if (w <= 0 || h <= 0) return null;
  return (w, h);
}

/// Build the session-report .docx and return its bytes.
///
/// [rows] are the programming-session rows; [subjectId] is the BIDS subject
/// label (without the "sub-" prefix). Mirrors the PDF section order.
Uint8List buildSessionDocx({
  required List<SessionRow> rows,
  required String subjectId,
  DateTime? generatedAt,
  ElectrodeReportImages? electrodeImages,
  Uint8List? chartPng,
  List<ScalePref>? scalePrefs,
  DocxPageSize pageSize = DocxPageSize.a4,
}) {
  final data = buildSessionReportData(
    rows: rows,
    generatedAt: generatedAt,
    scalePrefs: scalePrefs,
  );
  final media = _MediaBag();
  final body = StringBuffer();

  // (a) Title + patient + generated-on.
  body.write(_para('DBS Annotator - Session report', bold: true, size: 40));
  body.write(_para('Patient: sub-$subjectId    Session: ${data.date}'));
  body.write(_para('Generated on: ${data.date}'));

  // (b) Initial clinical notes.
  body.write(_heading('Initial clinical notes'));
  if (!data.hasInitial) {
    body.write(_para('No baseline (is_initial = 1) rows recorded.'));
  } else {
    for (final pair in data.initScales) {
      body.write(_para('• ${pair.name}: ${pair.value}'));
    }
    if (data.initNotes.isNotEmpty) {
      body.write(_para('Initial notes: ${data.initNotes}'));
    }
    if (data.initScales.isEmpty && data.initNotes.isEmpty) {
      body.write(_para('(no baseline scales or notes)'));
    }
  }

  // (c) Session data: the scales-timeline chart, then the lateral table.
  body.write(_heading('Session data'));
  if (chartPng != null) {
    body.write('<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
        '${media.drawing(chartPng, widthPx: pageSize.contentWidthPx)}</w:p>');
  }
  if (!data.hasRecording) {
    body.write(_para('No recording blocks in this session.'));
  } else {
    // Green shading for the best / second-best blocks, and a 3 pt rule on the
    // first row of each block (tableData is two rows — L then R — per block).
    final fills = <int, String>{};
    final rules = <int>{};
    var previousBlock = '';
    for (var i = 0; i < data.tableData.length; i++) {
      final label = data.tableData[i].first;
      if (label != previousBlock) {
        if (i > 0) rules.add(i);
        previousBlock = label;
      }
      final block = int.tryParse(label);
      if (block == null) continue;
      if (data.bestBlocks.contains(block)) {
        fills[i] = _hex(kBestFill);
      } else if (data.secondBlocks.contains(block)) {
        fills[i] = _hex(kSecondFill);
      }
    }
    body.write(_table(sessionTableHeaders, data.tableData,
        rowFills: fills, rowRules: rules));
    body.write(_legendBlock(data));
  }

  // (d) Electrode configuration: the four rendered leads in a borderless grid
  // when the caller supplied them (desktop `_add_electrode_config_section`),
  // else anode/cathode token text.
  body.write(_heading('Electrode configuration'));
  final ei = electrodeImages;
  final hasImages = ei != null &&
      (ei.initLeft != null ||
          ei.initRight != null ||
          ei.finalLeft != null ||
          ei.finalRight != null);
  if (!data.hasElectrodeConfig) {
    body.write(_para('No electrode configuration recorded.'));
  } else {
    if (data.electrodeModel.isNotEmpty) {
      body.write(_para('Electrode model: ${data.electrodeModel}'));
    }
    final it = data.initialTokens;
    final ft = data.finalTokens;
    if (hasImages) {
      // One quarter of the content width per lead, less a little breathing room.
      final cellPx = pageSize.contentWidthPx / 4 - 6;
      String img(Uint8List? png) =>
          png == null ? '' : media.drawing(png, widthPx: cellPx);
      body.write(_borderlessTable([
        '<w:tr>${_captionCell('Initial settings', bold: true, span: 2)}'
            '${_captionCell('Final settings', bold: true, span: 2)}</w:tr>',
        '<w:tr>${_captionCell('Left')}${_captionCell('Right')}'
            '${_captionCell('Left')}${_captionCell('Right')}</w:tr>',
        '<w:tr>'
            '${_captionCell(_tokenCaption(it?.leftAnode, it?.leftCathode))}'
            '${_captionCell(_tokenCaption(it?.rightAnode, it?.rightCathode))}'
            '${_captionCell(_tokenCaption(ft?.leftAnode, ft?.leftCathode))}'
            '${_captionCell(_tokenCaption(ft?.rightAnode, ft?.rightCathode))}'
            '</w:tr>',
        '<w:tr>${_xmlCell(img(ei.initLeft))}${_xmlCell(img(ei.initRight))}'
            '${_xmlCell(img(ei.finalLeft))}${_xmlCell(img(ei.finalRight))}</w:tr>',
      ]));
      body.write(_para(''));
    } else {
      if (it != null) {
        body.write(_para('Initial settings', bold: true));
        body.write(_para(
            '  Left:  anode ${it.leftAnode}  |  cathode ${it.leftCathode}'));
        body.write(_para(
            '  Right: anode ${it.rightAnode}  |  cathode ${it.rightCathode}'));
      }
      if (ft != null) {
        body.write(_para('Final settings', bold: true));
        body.write(_para(
            '  Left:  anode ${ft.leftAnode}  |  cathode ${ft.leftCathode}'));
        body.write(_para(
            '  Right: anode ${ft.rightAnode}  |  cathode ${ft.rightCathode}'));
      }
    }
  }

  // (e) Programming summary.
  body.write(_heading('Programming summary'));
  if (!data.hasRows) {
    body.write(_para('No session data available.'));
  } else {
    body.write(_para('Session duration: ${data.duration}'));
    body.write(_para('Configurations tested: ${data.numConfigs}'));
    body.write(_para('Amplitude range:  L: ${data.ampL}  |  R: ${data.ampR}'));
    body.write(_para('Frequency range:  L: ${data.freqL}  |  R: ${data.freqR}'));
    body.write(_para('Pulse width range:  L: ${data.pwL}  |  R: ${data.pwR}'));
  }

  // The drawing namespaces must be declared even when no image is embedded is
  // harmless, but Word requires them the moment one is — declare them always so
  // the two code paths can't diverge.
  final document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document '
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<w:body>$body${pageSize.sectPr}</w:body></w:document>';

  final archive = Archive()
    ..addFile(
        ArchiveFile.bytes('[Content_Types].xml', utf8.encode(_contentTypes)))
    ..addFile(ArchiveFile.bytes('_rels/.rels', utf8.encode(_rels)))
    ..addFile(ArchiveFile.bytes('word/document.xml', utf8.encode(document)));

  // Image parts and their relationships, only when something was embedded.
  final rels = media.relsXml;
  if (rels != null) {
    archive.addFile(
        ArchiveFile.bytes('word/_rels/document.xml.rels', utf8.encode(rels)));
    for (final e in media.media.entries) {
      archive.addFile(ArchiveFile.bytes('word/media/${e.key}', e.value));
    }
  }

  return Uint8List.fromList(ZipEncoder().encode(archive));
}
