/// Open a TSV, get a report. No authoring.
///
/// The two recording screens produce a report as a side effect of a session you
/// are running now. This is the other half: a file already exists — written
/// here, or on the desktop app, or last month — and you want the document.
///
/// It is deliberately thin, and that is the acceptance test for the extractions
/// this round did: it composes [SessionEntriesTable], [EntryChartsView],
/// [showScaleTargetsDialog], [showReportSectionsDialog], [exportFile] and both
/// report builders, and owns only the file it opened and the choices made about
/// it. If this file starts growing, something that belongs in a shared widget is
/// being written here instead.
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;

import '../app_info.dart';
import '../core/bids.dart';
import '../core/electrode/electrode_model.dart';
import '../core/prefs/user_prefs.dart';
import '../core/session/scale_scoring.dart';
import '../core/session/session_file.dart';
import '../core/session/session_row.dart';
import '../core/session/tsv_kind.dart';
import '../report/annotations_report.dart';
import '../report/entry_charts.dart';
import '../report/report_data.dart';
import '../report/report_sections.dart';
import '../report/session_docx.dart';
import '../report/session_pdf.dart';
import '../core/annotation.dart';
import 'report_images.dart';
import 'report_sections_dialog.dart';
import 'scale_targets_dialog.dart';
import 'session/entries_table.dart';
import 'session/entry_charts_view.dart';
import 'share_util.dart';
import 'theme.dart';

class SingleSessionReportScreen extends StatefulWidget {
  const SingleSessionReportScreen({super.key, this.catalog});

  /// Injected by tests; loaded from the bundled contract otherwise.
  final ElectrodeCatalog? catalog;

  @override
  State<SingleSessionReportScreen> createState() =>
      _SingleSessionReportScreenState();
}

class _SingleSessionReportScreenState extends State<SingleSessionReportScreen> {
  final _exportKey = GlobalKey();

  String? _filename;
  TsvKind _kind = TsvKind.unknown;
  List<SessionRow> _rows = const [];
  List<Annotation> _notes = const [];
  ElectrodeCatalog? _catalog;
  UserPrefs _prefs = UserPrefs();

  /// Null until the user sets them. The report refuses to rank without targets
  /// rather than inventing `min` for every scale, so this is also the flag for
  /// "has anybody said what better means".
  List<ScalePref>? _targets;

  Set<ReportSection> _sections = kAllReportSections;

  @override
  void initState() {
    super.initState();
    _catalog = widget.catalog;
    loadUserPrefs().then((p) {
      if (mounted) setState(() => _prefs = p);
    });
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  bool get _isSession => _kind == TsvKind.programming;
  bool get _hasFile => _rows.isNotEmpty || _notes.isNotEmpty;

  Future<void> _open() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform
          .pickFiles(type: FileType.any, withData: true);
    } catch (e) {
      if (mounted) _snack('Could not open the file picker. ($e)');
      return;
    }
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    String content;
    try {
      content = picked.bytes != null
          ? utf8.decode(picked.bytes!)
          : await File(picked.path!).readAsString();
    } catch (_) {
      if (mounted) _snack('Could not read ${picked.name}.');
      return;
    }

    // The kind decides which report gets built, so it is read from the header
    // rather than the filename: a BIDS `task-` entity is a convention a user
    // can rename, and the columns are the actual contract.
    final kind = sniffTsvKind(content);
    if (kind == TsvKind.unknown || kind == TsvKind.unreadable) {
      if (mounted) {
        _snack('${picked.name} is not a DBS Annotator TSV.');
      }
      return;
    }
    final catalog = _catalog ?? await loadElectrodeCatalog();
    if (!mounted) return;
    setState(() {
      _catalog = catalog;
      _filename = picked.name;
      _kind = kind;
      _rows = kind == TsvKind.programming
          ? parseSessionTsv(content)
          : const <SessionRow>[];
      _notes = kind == TsvKind.notes
          ? parseAnnotations(content)
          : const <Annotation>[];
      // A new file's targets are not the old file's.
      _targets = null;
    });
    _snack('Opened ${picked.name}.');
  }

  /// Targets for the ranking. Never defaulted silently — see [_targets].
  Future<void> _editTargets() async {
    final seed = _targets ?? defaultScalePrefsFor(_recordingRows);
    if (seed.isEmpty) {
      _snack('This file has no session scale ratings to rank.');
      return;
    }
    final updated = await showScaleTargetsDialog(context, seed);
    if (updated != null && mounted) setState(() => _targets = updated);
  }

  Iterable<SessionRow> get _recordingRows =>
      _rows.where((r) => coerceInt(r.isInitial) != 1);

  SessionReportData _sessionData() => buildSessionReportData(
        rows: _rows,
        scalePrefs: _targets,
        sourceFile: _filename ?? '',
      );

  AnnotationsReportData _notesData() => buildAnnotationsReportData(
        entries: _notes,
        subjectId: BidsName.parse(_filename ?? '')?.subject ?? 'unknown',
        sourceFile: _filename ?? '',
      );

  Future<void> _export({required bool docx}) async {
    if (!_hasFile) return;
    final sections = _isSession
        ? await showReportSectionsDialog(context, _sections)
        : kAllReportSections;
    if (sections == null || !mounted) return;
    if (_isSession) setState(() => _sections = sections);

    final letter =
        (_prefs.reportPageSize ?? kDefaultReportPageSize) == 'letter';
    final base = (_filename ?? 'report').replaceAll(RegExp(r'\.tsv$'), '');
    final name = '${base}_report.${docx ? 'docx' : 'pdf'}';

    await exportFile(
      context,
      filename: name,
      anchor: _exportKey,
      failureLabel: 'Report export failed',
      build: () async {
        if (!_isSession) {
          final data = _notesData();
          if (docx) {
            return (
              bytes: buildAnnotationsDocx(data,
                  pageSize: letter ? DocxPageSize.letter : DocxPageSize.a4),
              warning: null,
            );
          }
          final report = await buildAnnotationsPdf(data,
              pageFormat: letter ? PdfPageFormat.letter : PdfPageFormat.a4);
          return (bytes: report.bytes, warning: _warn(report.lostCharacters));
        }

        final data = _sessionData();
        final gfx = await renderReportGraphics(
            data, _catalog?.models[electrodeModelIn(_rows)], sections);
        if (docx) {
          return (
            bytes: buildSessionDocx(
              data: data,
              subjectId: BidsName.parse(_filename ?? '')?.subject ?? 'unknown',
              electrodeImages: gfx.electrodes,
              chartPng: gfx.chart,
              pageSize: letter ? DocxPageSize.letter : DocxPageSize.a4,
              sections: sections,
            ),
            warning: null,
          );
        }
        final report = await buildSessionPdf(
          data: data,
          subjectId: BidsName.parse(_filename ?? '')?.subject ?? 'unknown',
          electrodeImages: gfx.electrodes,
          chartPng: gfx.chart,
          pageFormat: letter ? PdfPageFormat.letter : PdfPageFormat.a4,
          sections: sections,
        );
        return (bytes: report.bytes, warning: _warn(report.lostCharacters));
      },
    );
  }

  String? _warn(bool lost) => lost
      ? 'Some characters could not be rendered in the PDF and were replaced '
          'with "?". Add the IBM Plex fonts to assets/fonts/ for full Unicode, '
          'or export to Word instead.'
      : null;



  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Single session report'),
        actions: [
          if (_hasFile)
            MenuAnchor(
              builder: (context, controller, child) => IconButton(
                key: _exportKey,
                icon: const Icon(Icons.ios_share),
                tooltip: 'Export report',
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
              menuChildren: [
                MenuItemButton(
                  leadingIcon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: () => _export(docx: false),
                  child: const Text('Report (PDF)'),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.description_outlined),
                  onPressed: () => _export(docx: true),
                  child: const Text('Report (Word)'),
                ),
              ],
            ),
          const TextSizeButtons(),
          const HelpButton(),
          const ThemeToggleButton(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            FilledButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open TSV'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _filename ?? 'No file opened.',
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          if (!_hasFile)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'Open a session or notes TSV to produce its report.\n'
                  'The file type is detected from its columns.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.disabledColor),
                ),
              ),
            )
          else ...[
            const Divider(height: 28),
            if (_isSession) ..._sessionPreview(theme) else ..._notesPreview(),
          ],
        ],
      ),
    );
  }

  List<Widget> _notesPreview() => [
        Text('${_notes.length} notes'),
        const SizedBox(height: 8),
        for (final n in _notes.take(50))
          ListTile(
            dense: true,
            leading: Text(n.time),
            title: Text(n.notes),
          ),
      ];

  List<Widget> _sessionPreview(ThemeData theme) {
    final model = electrodeModelIn(_rows);
    final known = _catalog?.models.containsKey(model) ?? false;
    return [
      Row(children: [
        Expanded(
          child: Text(
            '${blockCount(_rows)} blocks'
            '${model.isEmpty ? '' : '   ·   $model'}',
            style: theme.textTheme.titleMedium,
          ),
        ),
        OutlinedButton.icon(
          onPressed: _editTargets,
          icon: const Icon(Icons.adjust, size: 18),
          label: Text(_targets == null ? 'Set scale targets' : 'Scale targets'),
        ),
      ]),
      if (model.isNotEmpty && !known)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Electrode model "$model" is not in the catalogue, so the report '
            'will carry contact text instead of lead diagrams.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      if (_targets == null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'No scale targets set, so no configuration will be ranked. Setting '
            'them says what "better" means for each scale.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      const SizedBox(height: 12),
      EntryChartsView(data: _chartData(), visibleConfigs: kDefaultVisibleConfigs),
      const SizedBox(height: 12),
      SessionEntriesTable(rows: _rows),
    ];
  }

  EntryChartData _chartData() =>
      buildEntryChartData(_rows, scalePrefs: _targets ?? const []);
}
