import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_info.dart';
import '../core/bids.dart';
import '../core/bids_dataset.dart';
import '../core/bids_sidecar.dart';
import '../core/session/aggregate.dart';
import '../core/session/longitudinal.dart';
import '../core/session/tsv_kind.dart';
import '../core/session/session_file.dart';
import '../core/session/session_row.dart';
import '../report/longitudinal_data.dart';
import '../report/longitudinal_pdf.dart';
import '../report/session_docx.dart' show DocxPageSize;
import '../report/report_data.dart' show ScalesChartSpec, buildScalesChartSpec;
import 'bids_export.dart';
import 'save_target.dart';
import 'scales_chart_painter.dart';
import 'share_util.dart';
import 'theme.dart';

/// One imported programming-session TSV.
class ImportedSessionFile {
  const ImportedSessionFile({required this.name, required this.rows});

  final String name;
  final List<SessionRow> rows;
}

/// Merge per-file [scaleTimeline]s onto one x-axis. Each file's block indices
/// are offset by the running block count of the files before it, in import
/// order, so sessions render sequentially instead of colliding at block 0.
Map<String, Map<int, double>> combinedScaleTimeline(
  Iterable<List<SessionRow>> perFileRows,
) {
  final combined = <String, Map<int, double>>{};
  var offset = 0;
  for (final rows in perFileRows) {
    final timeline = scaleTimeline(rows);
    var maxBlock = -1;
    timeline.forEach((scale, byBlock) {
      final dest = combined.putIfAbsent(scale, () => <int, double>{});
      byBlock.forEach((block, value) {
        dest[block + offset] = value;
        if (block > maxBlock) maxBlock = block;
      });
    });
    offset += maxBlock + 1;
  }
  return combined;
}

/// Longitudinal review: import several programming-session TSVs, chart the
/// session scales across blocks, and export a PDF report. The counterpart of
/// the desktop's longitudinal report view.
class LongitudinalScreen extends StatefulWidget {
  const LongitudinalScreen({super.key, this.initialFiles});

  /// Pre-imported files, for headless tests and the documentation
  /// screenshots: importing goes through the platform file picker, which a
  /// widget test cannot drive, so without this seam the only capturable state
  /// is the empty one. Mirrors the `authoring` seam on [SessionScreen].
  final List<ImportedSessionFile>? initialFiles;

  @override
  State<LongitudinalScreen> createState() => _LongitudinalScreenState();
}

class _LongitudinalScreenState extends State<LongitudinalScreen> {
  late final _files = <ImportedSessionFile>[...?widget.initialFiles];

  /// Anchors the iPadOS share popover to the export button. See
  /// [shareOriginFrom].
  final _exportKey = GlobalKey();

  Map<String, Map<int, double>> get _timeline =>
      combinedScaleTimeline(_files.map((f) => f.rows));

  bool get _idsMismatch => !patientIdsMatch(_files.map((f) => f.name).toList());

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _import() async {
    // The genuine multi-file case, so `pickFiles` is right here and
    // `allowMultiple` is file_picker 12's default. Without the catch, a Linux
    // box lacking zenity/kdialog rejects into an unhandled async error and
    // Import becomes an inert button with no message at all.
    final List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(type: FileType.any);
    } catch (e) {
      if (mounted) _snack('Could not open the file picker. ($e)');
      return;
    }
    if (files.isEmpty) return; // v12 returns an empty list, never null
    final added = <ImportedSessionFile>[];
    final failed = <String>[];
    final wrongKind = <String>[];
    for (final picked in files) {
      final content = await readPickedText(picked);
      if (content == null) {
        failed.add(picked.name);
        continue;
      }
      // Check the kind before parsing. `SessionRow.fromMap` is total: every
      // column it cannot find becomes '', so a notes TSV would import
      // "successfully" as a page of empty rows, with no explanation.
      final kind = sniffTsvKind(content);
      if (kind != TsvKind.programming) {
        wrongKind.add(tsvKindMismatch(picked.name, kind, TsvKind.programming));
        continue;
      }
      try {
        added.add(
          ImportedSessionFile(
            name: picked.name,
            rows: parseSessionTsv(content),
          ),
        );
      } catch (_) {
        failed.add(picked.name);
      }
    }
    if (!mounted) return;
    setState(() => _files.addAll(added));
    if (failed.isNotEmpty) _snack('Could not read: ${failed.join(', ')}');
    if (wrongKind.isNotEmpty) _snack(wrongKind.join(' '));
  }

  /// The report content, computed once so both formats and both figures come
  /// from the same numbers.
  LongitudinalReportData _reportData() => buildLongitudinalReportData(
    files: {for (final f in _files) f.name: f.rows},
  );

  /// Lay the imported files out as a BIDS dataset and export it, zipped.
  ///
  /// Entities come from each file's own name. A file whose name carries none,
  /// having been renamed by hand, is skipped rather than guessed at: a wrong
  /// `sub-` label in a shared dataset is worse than a missing file.
  Future<void> _exportBids() async {
    if (_files.isEmpty) {
      _snack('Import at least one session first.');
      return;
    }
    final Map<String, dynamic> contract;
    try {
      contract = await loadTsvContract();
    } catch (e) {
      if (mounted) _snack('BIDS export failed: $e');
      return;
    }
    final entries = <DatasetEntry>[];
    final skipped = <String>[];
    for (final file in _files) {
      final name = BidsName.parse(file.name);
      if (name == null || name.session.isEmpty) {
        skipped.add(file.name);
        continue;
      }
      entries.add(
        datasetEntry(
          // Re-emit with the current suffix and column names, so a 0.4.x
          // `_events.tsv` lands in the dataset as a valid `_beh.tsv`.
          name: BidsName(
            subject: name.subject,
            session: name.session,
            task: name.task.isEmpty ? 'programming' : name.task,
            run: name.run,
          ),
          tsv: serializeSessionTsv(file.rows),
          contract: contract,
          kind: 'session_tsv',
          acqTime: file.rows.isEmpty ? '' : file.rows.first.acqTime,
        ),
      );
    }
    if (!mounted) return;
    if (entries.isEmpty) {
      _snack('No imported file carries BIDS entities in its name.');
      return;
    }
    // The combined table goes where BIDS puts a cross-session derivation: its
    // own directory under `derivatives/`, with its own
    // dataset_description.json, without which the whole dataset is invalid.
    final aggregate = buildAggregate([
      for (final f in _files) (filename: f.name, rows: f.rows),
    ]);
    final extraFiles = <DatasetFile>[
      if (aggregate.rowCount > 0) ...[
        derivativeDescription(
          dir: aggregateDerivativeDir,
          name: '$appName combined sessions',
          appName: appName,
          appVersion: appVersion,
          repoUrl: repoUrl,
        ),
        (
          path: '$aggregateDerivativeDir/$aggregateStem.tsv',
          content: aggregate.tsv,
        ),
        (
          path: '$aggregateDerivativeDir/$aggregateStem.json',
          content: aggregateSidecarJson(contract, appVersion: appVersion),
        ),
      ],
    ];

    await exportBidsDataset(
      context,
      anchor: _exportKey,
      entries: entries,
      extraFiles: extraFiles,
    );
    if (mounted && skipped.isNotEmpty) {
      _snack(
        'Skipped (no BIDS entities in the filename): '
        '${skipped.join(', ')}',
      );
    }
  }

  /// The imported sessions as one long table, for sharing and analysis.
  ///
  /// Delivered as a standalone TSV with its sidecar beside it: one openable
  /// file is a better sharing artefact than a zip. The same table also goes
  /// into the BIDS zip as a derivative; see [_exportBids].
  Future<void> _exportAggregate() async {
    if (_files.isEmpty) {
      _snack('Import at least one session first.');
      return;
    }
    final out = buildAggregate([
      for (final f in _files) (filename: f.name, rows: f.rows),
    ]);
    if (out.rowCount == 0) {
      _snack(
        out.skipped.isEmpty
            ? 'The imported files contain no rows to combine.'
            : 'No imported file carries BIDS entities in its name.',
      );
      return;
    }

    // Neither name carries a `ses-` entity: the table spans sessions.
    final stem = out.subjects.length == 1
        ? '${out.subjects.single}_$aggregateStem'
        : 'study_$aggregateStem';

    await exportFile(
      context,
      filename: '$stem.tsv',
      anchor: _exportKey,
      failureLabel: 'Combined table export failed',
      build: () async => (bytes: utf8.encode(out.tsv), warning: null),
    );
    if (!mounted) return;
    // State the shape rather than just "done": a silently dropped visit would
    // be invisible in a table this size.
    _snack(
      '${out.rowCount} rows from ${out.fileCount} file'
      '${out.fileCount == 1 ? '' : 's'}, '
      '${out.subjects.length} subject${out.subjects.length == 1 ? '' : 's'}.',
    );
    if (out.skipped.isNotEmpty) {
      _snack(
        'Left out: '
        '${out.skipped.map((s) => '${s.filename}: ${s.reason}').join('; ')}',
      );
    }
  }

  Future<void> _exportReport({required bool docx}) async {
    if (_files.isEmpty) {
      _snack('Import at least one session first.');
      return;
    }
    final data = _reportData();
    if (data.isEmpty) {
      _snack('The imported files contain no visits to report.');
      return;
    }
    // A derivative that spans visits, so no `ses-`, and `longitudinal` is not
    // a task the app records, so no `task-`. `desc-` is the BIDS derivatives
    // entity for naming what a computed file is.
    final name =
        'sub-${BidsName.label(data.patientId)}'
        '_desc-longitudinal_report.${docx ? 'docx' : 'pdf'}';

    await exportFile(
      context,
      filename: name,
      anchor: _exportKey,
      failureLabel: 'Report export failed',
      build: () async {
        // Rasterised by the shared painter so screen and print cannot
        // disagree, and best-effort because the builders fall back to words.
        final clinical = await _chartPng(data.clinicalChart);
        final session = await _chartPng(data.sessionChart);
        if (docx) {
          return (
            bytes: buildLongitudinalDocx(
              data: data,
              clinicalChartPng: clinical,
              sessionChartPng: session,
              pageSize: DocxPageSize.a4,
            ),
            warning: null,
          );
        }
        final report = await buildLongitudinalPdf(
          data: data,
          clinicalChartPng: clinical,
          sessionChartPng: session,
        );
        return (
          bytes: report.bytes,
          warning: report.lostCharacters
              ? 'Some characters could not be rendered in the PDF and were '
                    'replaced with "?". Add the IBM Plex fonts to assets/fonts/ '
                    'for full Unicode, or export to Word instead.'
              : null,
        );
      },
    );
  }

  /// Rasterise one figure, degrading to null rather than failing the export.
  Future<Uint8List?> _chartPng(ScalesChartSpec spec) async {
    if (spec.isEmpty) return null;
    try {
      return await renderScalesChartPng(spec);
    } catch (e) {
      debugPrint('Longitudinal figure could not be rendered: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeline = _timeline;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Longitudinal review'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Import session TSVs',
            onPressed: _import,
          ),
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
                onPressed: () => _exportReport(docx: false),
                child: const Text('Report (PDF)'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.description_outlined),
                onPressed: () => _exportReport(docx: true),
                child: const Text('Report (Word)'),
              ),
              const Divider(height: 8),
              MenuItemButton(
                leadingIcon: const Icon(Icons.table_chart_outlined),
                onPressed: _exportAggregate,
                child: const Text('Combined table (TSV)'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.folder_zip_outlined),
                onPressed: _exportBids,
                child: const Text('BIDS dataset (zip)'),
              ),
            ],
          ),
          const TextSizeButtons(),
          const HelpButton(),
          const ThemeToggleButton(),
        ],
      ),
      body: _files.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No sessions imported yet.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _import,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Import session TSVs'),
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_idsMismatch) _MismatchBanner(),
                  _FileList(
                    files: _files,
                    onRemove: (i) => setState(() => _files.removeAt(i)),
                    onClear: () => setState(_files.clear),
                  ),
                  const Divider(height: 24),
                  Expanded(
                    child: timeline.isEmpty
                        ? const Center(
                            child: Text(
                              'No session scale values in the imported files.',
                            ),
                          )
                        : _timelineChart(context, timeline),
                  ),
                ],
              ),
            ),
    );
  }
}

class _MismatchBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'The selected files belong to different patients '
              '(mismatched sub- IDs).',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileList extends StatelessWidget {
  const _FileList({
    required this.files,
    required this.onRemove,
    required this.onClear,
  });

  final List<ImportedSessionFile> files;
  final void Function(int index) onRemove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Imported sessions (${files.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear'),
            ),
          ],
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: files.length,
            itemBuilder: (_, i) => ListTile(
              dense: true,
              leading: const Icon(Icons.description_outlined),
              title: Text(files[i].name, overflow: TextOverflow.ellipsis),
              subtitle: Text('${files[i].rows.length} rows'),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Remove',
                onPressed: () => onRemove(i),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The on-screen scales timeline, drawn by [ScalesChartPainter], the painter
/// the report embeds, so the screen and the PDF cannot disagree.
///
/// The x axis is the concatenated block index, not session dates, so it is
/// only comparable within a visit.
Widget _timelineChart(
  BuildContext context,
  Map<String, Map<int, double>> timeline,
) {
  final theme = Theme.of(context);
  return CustomPaint(
    painter: ScalesChartPainter(
      spec: buildScalesChartSpec(
        timeline: timeline,
        prefs: const [],
        title: '',
        xLabel: 'Block',
        yLabel: 'Scale value',
      ),
      background: theme.colorScheme.surface,
      ink: theme.colorScheme.onSurface,
    ),
    child: const SizedBox.expand(),
  );
}
