/// Report for an annotations-only (`task-notes`) session, in PDF and Word.
///
/// The home screen has promised "Notes -> report" for this workflow since it was
/// written, and the screen only ever wrote a TSV. This is the report.
///
/// It shares **nothing** with `SessionReportData` by design: a notes session has
/// no blocks, no stimulation, no scales and no ranking, so there is no common
/// content to factor out and a shared data class would be an abstraction over
/// two things that are not alike. What it does share is the *packaging* — the
/// sanitiser, the fonts, the page geometry, the footer, the OOXML plumbing —
/// because that is where the failure modes live.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app_info.dart' show appVersion;
import '../core/annotation.dart';
import 'docx_ooxml.dart';
import 'report_data.dart' show ReportBytes;
import 'report_fonts.dart';
import 'report_text.dart';

/// Everything both formats print, computed once so they cannot disagree.
class AnnotationsReportData {
  const AnnotationsReportData({
    required this.subjectId,
    required this.sessionDate,
    required this.generatedOn,
    required this.utcOffset,
    required this.entries,
    required this.sourceFile,
  });

  final String subjectId;

  /// The date the notes were TAKEN, from the entries themselves — not the
  /// export clock, which is the mistake the session report used to make.
  final String sessionDate;
  final String generatedOn;

  /// e.g. "+02:00", or '' when the entries carry no parseable offset.
  final String utcOffset;

  /// Oldest first: the order the session happened in, which is the order it has
  /// to be read back in. (The entry UI lists newest first, which is right for
  /// typing and wrong for reading.)
  final List<Annotation> entries;

  final String sourceFile;

  /// "2026-06-26 (UTC+02:00)" for the header and every page footer.
  String get sessionStamp =>
      utcOffset.isEmpty ? sessionDate : '$sessionDate (UTC$utcOffset)';

  String get title => 'DBS session notes - sub-$subjectId - $sessionDate';

  /// The span from the first note to the last, or '' when it cannot be derived.
  String get span {
    if (entries.length < 2) return '';
    final first = DateTime.tryParse(
        '${entries.first.date.trim()} ${entries.first.time.trim()}');
    final last = DateTime.tryParse(
        '${entries.last.date.trim()} ${entries.last.time.trim()}');
    if (first == null || last == null) return '';
    final mins = last.difference(first).inMinutes;
    if (mins <= 0) return '';
    return mins >= 60 ? '${mins ~/ 60}h ${mins % 60}min' : '$mins min';
  }
}

/// Build the shared content from raw [entries].
AnnotationsReportData buildAnnotationsReportData({
  required List<Annotation> entries,
  required String subjectId,
  DateTime? generatedAt,
  String sourceFile = '',
}) {
  final dt = generatedAt ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final generatedOn = '${dt.year}-${two(dt.month)}-${two(dt.day)}';

  final sorted = entries.toList()
    ..sort((a, b) => '${a.date} ${a.time}'.compareTo('${b.date} ${b.time}'));

  // The `timezone` column holds a display name followed by an offset
  // ("W. Europe Daylight Time +0200"); only the offset half is portable.
  String offset() {
    for (final e in sorted) {
      final m = RegExp(r'([+-])(\d{2}):?(\d{2})').firstMatch(e.timezone);
      if (m != null) return '${m.group(1)}${m.group(2)}:${m.group(3)}';
    }
    return '';
  }

  return AnnotationsReportData(
    subjectId: subjectId,
    sessionDate: sorted.isEmpty ? generatedOn : sorted.first.date.trim(),
    generatedOn: generatedOn,
    utcOffset: offset(),
    entries: sorted,
    sourceFile: sourceFile,
  );
}

/// The three attestation rules, drawn the same way as the session report's.
List<pw.Widget> _attestation() => [
      pw.SizedBox(height: 18),
      pw.Text('Attestation',
          style:
              const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 10),
      pw.Row(children: [
        for (final label in ['Recorded by', 'Reviewed by', 'Date'])
          pw.Expanded(
            child: pw.Container(
              margin: const pw.EdgeInsets.only(right: 16),
              padding: const pw.EdgeInsets.only(top: 14),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                    top: pw.BorderSide(color: PdfColors.grey600, width: 0.8)),
              ),
              child: pw.Text(label,
                  style: const pw.TextStyle(
                      fontSize: 8, color: PdfColors.grey700)),
            ),
          ),
      ]),
    ];

/// The notes report as a PDF.
Future<ReportBytes> buildAnnotationsPdf(
  AnnotationsReportData data, {
  PdfPageFormat pageFormat = PdfPageFormat.a4,
}) async {
  final fonts = await loadReportFonts();
  final theme = fonts.theme;
  final t = ReportTextSanitiser(coverage: fonts.coverage);
  final doc = pw.Document(
    theme: theme,
    title: data.title,
    author: kDocxCreator,
    creator: kDocxCreator,
    subject: 'Deep brain stimulation session notes',
  );

  doc.addPage(pw.MultiPage(
    // Same margins as the session report, so a clinician filing both does not
    // get two different page geometries for one patient.
    pageFormat: pageFormat.copyWith(
      marginLeft: 36,
      marginRight: 36,
      marginTop: 54,
      marginBottom: 54,
    ),
    footer: (context) => pw.Container(
      alignment: pw.Alignment.center,
      margin: const pw.EdgeInsets.only(top: 6),
      child: pw.Text(
        'sub-${t(data.subjectId)}  |  ${data.sessionStamp}  |  '
        'DBS Annotator v$appVersion  |  '
        'Page ${context.pageNumber} of ${context.pagesCount}',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
      ),
    ),
    build: (context) => [
      pw.Header(
        level: 0,
        child: pw.Text('DBS Annotator - Session notes',
            style: const pw.TextStyle(
                fontSize: 20, fontWeight: pw.FontWeight.bold)),
      ),
      pw.Text(
          'Patient: sub-${t(data.subjectId)}    Session: ${data.sessionStamp}'),
      pw.Text(
          'Generated on: ${data.generatedOn} by DBS Annotator v$appVersion'
          '${data.sourceFile.isEmpty ? '' : '  |  Source: '
              '${t(data.sourceFile)} (${data.entries.length} notes)'}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      pw.SizedBox(height: 12),
      pw.Header(
          level: 1,
          text: 'Notes (${data.entries.length}'
              '${data.span.isEmpty ? '' : ', over ${data.span}'})'),
      if (data.entries.isEmpty)
        pw.Text('No notes recorded.')
      else
        // A fixed time column beside the text, rather than the timestamp inline:
        // the reading task is "what happened, in order", and a column lets the
        // eye run down it.
        pw.TableHelper.fromTextArray(
          headers: const ['Time', 'Note'],
          data: [
            for (final e in data.entries) [t(e.time.trim()), t(e.notes.trim())],
          ],
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerStyle:
              const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellAlignment: pw.Alignment.topLeft,
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(7),
          },
        ),
      ..._attestation(),
    ],
  ));
  return (bytes: await doc.save(), lostCharacters: t.lostCharacters);
}

/// The notes report as a .docx, saying the same things in the same words.
Uint8List buildAnnotationsDocx(
  AnnotationsReportData data, {
  DocxPageSize pageSize = DocxPageSize.a4,
}) {
  final body = StringBuffer()
    ..write(docxPara('DBS Annotator - Session notes', bold: true, size: 40))
    ..write(docxPara(
        'Patient: sub-${data.subjectId}    Session: ${data.sessionStamp}'))
    ..write(docxPara(
        'Generated on: ${data.generatedOn} by DBS Annotator v$appVersion'
        '${data.sourceFile.isEmpty ? '' : '  |  Source: ${data.sourceFile} '
            '(${data.entries.length} notes)'}',
        size: 18))
    ..write(docxHeading('Notes (${data.entries.length}'
        '${data.span.isEmpty ? '' : ', over ${data.span}'})'));

  if (data.entries.isEmpty) {
    body.write(docxPara('No notes recorded.'));
  } else {
    body.write(docxTable(
      const ['Time', 'Note'],
      [
        for (final e in data.entries) [e.time.trim(), e.notes.trim()],
      ],
      weights: const [1, 7],
      contentTwips: pageSize.contentWidthTwips,
    ));
  }

  body
    ..write(docxHeading2('Attestation'))
    ..write(docxPara('Recorded by: ${'_' * 26}    '
        'Reviewed by: ${'_' * 26}    Date: ${'_' * 14}'));

  return packDocx(
    body: body.toString(),
    pageSize: pageSize,
    title: data.title,
    subject: 'Deep brain stimulation session notes',
    createdDate: data.generatedOn,
    footerPrefix: 'sub-${data.subjectId}  |  ${data.sessionStamp}  |  '
        'DBS Annotator v$appVersion  |  Page ',
  );
}
