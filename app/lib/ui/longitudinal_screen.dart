import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../app_info.dart';
import '../core/bids.dart';
import '../core/session/longitudinal.dart';
import '../core/session/session_file.dart';
import '../core/session/session_row.dart';
import '../report/longitudinal_pdf.dart';
import 'share_util.dart';
import 'theme.dart';

/// One imported programming-session TSV.
class ImportedSessionFile {
  const ImportedSessionFile({required this.name, required this.rows});

  final String name;
  final List<SessionRow> rows;
}

/// Merge per-file [scaleTimeline]s onto one x-axis. Each file's block
/// indices are offset by the running block count of the files before it, so
/// sessions render sequentially left-to-right instead of overwriting each
/// other at block 0 (files are taken in import order).
Map<String, Map<int, double>> combinedScaleTimeline(
    Iterable<List<SessionRow>> perFileRows) {
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

// Categorical series palette (validated 8-slot order, light/dark steps).
// Fixed assignment order, never cycled: past 8 scales the chart shows the
// first 8 and the PDF table carries the rest.
const _seriesLight = [
  Color(0xFF2A78D6),
  Color(0xFF008300),
  Color(0xFFE87BA4),
  Color(0xFFEDA100),
  Color(0xFF1BAF7A),
  Color(0xFFEB6834),
  Color(0xFF4A3AA7),
  Color(0xFFE34948),
];
const _seriesDark = [
  Color(0xFF3987E5),
  Color(0xFF008300),
  Color(0xFFD55181),
  Color(0xFFC98500),
  Color(0xFF199E70),
  Color(0xFFD95926),
  Color(0xFF9085E9),
  Color(0xFFE66767),
];

/// Longitudinal review: import several programming-session TSVs, chart the
/// session scales across blocks, and export a PDF report — the tablet
/// counterpart of the desktop's longitudinal report view.
class LongitudinalScreen extends StatefulWidget {
  const LongitudinalScreen({super.key});

  @override
  State<LongitudinalScreen> createState() => _LongitudinalScreenState();
}

class _LongitudinalScreenState extends State<LongitudinalScreen> {
  final _files = <ImportedSessionFile>[];

  /// Anchors the iPadOS share popover to the export button. See
  /// [shareOriginFrom].
  final _exportKey = GlobalKey();

  Map<String, Map<int, double>> get _timeline =>
      combinedScaleTimeline(_files.map((f) => f.rows));

  bool get _idsMismatch =>
      !patientIdsMatch(_files.map((f) => f.name).toList());

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: true,
    );
    if (result == null) return;
    final added = <ImportedSessionFile>[];
    final failed = <String>[];
    for (final picked in result.files) {
      try {
        final content = picked.bytes != null
            ? utf8.decode(picked.bytes!)
            : await File(picked.path!).readAsString();
        added.add(ImportedSessionFile(
          name: picked.name,
          rows: parseSessionTsv(content),
        ));
      } catch (_) {
        failed.add(picked.name);
      }
    }
    if (!mounted) return;
    setState(() => _files.addAll(added));
    if (failed.isNotEmpty) _snack('Could not read: ${failed.join(', ')}');
  }

  Future<void> _exportPdf() async {
    final timeline = _timeline;
    if (timeline.isEmpty) {
      _snack('Import at least one session with scale values first.');
      return;
    }
    // Resolve context-derived values before the first await.
    final messenger = ScaffoldMessenger.of(context);
    final screen = MediaQuery.sizeOf(context);
    final origin = shareOriginFrom(_exportKey.currentContext);
    final filenames = _files.map((f) => f.name).toList();
    final id = filenames
        .map(extractPatientId)
        .firstWhere((s) => s.isNotEmpty, orElse: () => 'unknown');
    final name =
        'sub-${id}_longitudinal-report_${BidsName.sessionStamp(DateTime.now())}.pdf';
    try {
      final bytes = await buildLongitudinalPdf(
        filenames: filenames,
        timeline: timeline,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes);
      await shareOrSaveFile(messenger, file, name,
          origin: origin, screen: screen);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Report export failed: $e')),
      );
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
          IconButton(
            key: _exportKey,
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Export PDF',
            onPressed: _exportPdf,
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
                        : _TimelineChart(timeline: timeline),
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
            Text('Imported sessions (${files.length})',
                style: Theme.of(context).textTheme.titleMedium),
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

class _TimelineChart extends StatelessWidget {
  const _TimelineChart({required this.timeline});

  final Map<String, Map<int, double>> timeline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? _seriesDark
        : _seriesLight;
    final scales = timeline.keys.toList()..sort();
    final shown = scales.take(palette.length).toList();
    final labelStyle = theme.textTheme.bodySmall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LineChart(
            LineChartData(
              lineBarsData: [
                for (var i = 0; i < shown.length; i++)
                  LineChartBarData(
                    spots: (timeline[shown[i]]!.entries.toList()
                          ..sort((a, b) => a.key.compareTo(b.key)))
                        .map((e) => FlSpot(e.key.toDouble(), e.value))
                        .toList(),
                    color: palette[i],
                    barWidth: 2,
                    isCurved: false,
                    dotData: const FlDotData(show: true),
                  ),
              ],
              gridData: const FlGridData(drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (v, meta) =>
                        Text(meta.formattedValue, style: labelStyle),
                  ),
                ),
                bottomTitles: AxisTitles(
                  axisNameWidget: Text('Block', style: labelStyle),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (v, meta) => v == v.roundToDouble()
                        ? Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('${v.toInt()}', style: labelStyle),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            for (var i = 0; i < shown.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: palette[i],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(shown[i], style: labelStyle),
                ],
              ),
            if (scales.length > shown.length)
              Text(
                'Showing first ${shown.length} of ${scales.length} scales '
                '(all are in the PDF).',
                style: labelStyle,
              ),
          ],
        ),
      ],
    );
  }
}
