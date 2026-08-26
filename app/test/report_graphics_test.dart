import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/session/scale_scoring.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:dbs_annotator/report/session_docx.dart' show pngSize;
import 'package:dbs_annotator/ui/report_images.dart';
import 'package:dbs_annotator/ui/scales_chart_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The committed export the desktop docs are built from — real clinical shape
/// (7 blocks, 5 session scales, clinical baseline), so the scoring is checked
/// against data we can compare with the reference figure in
/// docs/_static/session_report_session_scales_figure.png.
List<SessionRow> _exampleRows() => parseSessionTsv(
      File('../docs/_static/session_report_example/'
              'sub-01_ses-20260626_task-programming_run-01_events.tsv')
          .readAsStringSync(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('chart spec (scoring wired into the reports)', () {
    late SessionReportData data;

    setUp(() {
      data = buildSessionReportData(
          rows: _exampleRows(), generatedAt: DateTime(2026, 6, 26));
    });

    test('plots the session scales over the recording blocks', () {
      expect(data.chart.series.keys,
          ['Obsessions', 'Compulsions', 'Anxiety', 'Mood', 'Energy']);
      expect(data.chart.xs, [1, 2, 3, 4, 5, 6, 7]);
      expect(data.chart.isEmpty, isFalse);
    });

    test('clamps the y-axis to the declared scale range', () {
      // Every scale declares 0..10, so the axis is pinned there rather than
      // hugging the data (the desktop `get_declared_scale_range`).
      expect(data.chart.yMin, 0);
      expect(data.chart.yMax, 10);
    });

    test('computes the aggregate index and ranks blocks 7 then 6', () {
      // Matches the reference figure: the dark green band sits on block 7 and
      // the light one on block 6.
      expect(data.chart.aggregateIndex, hasLength(7));
      expect(data.chart.bestX, 7);
      expect(data.chart.secondX, 6);
      for (final v in data.chart.aggregateIndex.values) {
        expect(v, inInclusiveRange(0.0, 1.0));
      }
    });

    test('table shading uses the separate raw-sum ranking', () {
      // Deliberately a different algorithm from the chart's index — the desktop
      // does the same and they may disagree. See scale_scoring.dart.
      expect(data.bestBlocks, isNotEmpty);
      expect(data.bestBlocks, isNot(equals(data.secondBlocks)));
    });

    test('lists only the SESSION scales as targets, not clinical baselines', () {
      expect(data.targetsText, contains('Obsessions: min'));
      expect(data.targetsText, isNot(contains('Y-BOCS')),
          reason: 'clinical baseline scales are not session targets');
    });

    test('resolves the electrode rows the text describes', () {
      expect(data.initialRow, isNotNull);
      expect(data.finalRow, isNotNull);
      expect(coerceInt(data.initialRow!.isInitial), 1);
      expect(coerceInt(data.finalRow!.isInitial), isNot(1));
    });

    test('respects explicit scale prefs (max flips the ranking)', () {
      final maxPrefs = [
        for (final name in ['Obsessions', 'Compulsions', 'Anxiety', 'Mood',
          'Energy'])
          (name: name, min: 0.0, max: 10.0, mode: ScaleMode.max,
              custom: null),
      ];
      final flipped = buildSessionReportData(
          rows: _exampleRows(), scalePrefs: maxPrefs);
      // Maximising instead of minimising must not pick the same best block.
      expect(flipped.chart.bestX, isNot(7));
    });

    test('a single scale suppresses the index, as the desktop does', () {
      const rows = [
        SessionRow(blockId: '1', isInitial: '0', scaleName: 'Tremor',
            scaleValue: '3'),
        SessionRow(blockId: '2', isInitial: '0', scaleName: 'Tremor',
            scaleValue: '1'),
      ];
      final one = buildSessionReportData(rows: rows);
      expect(one.chart.series, hasLength(1));
      expect(one.chart.aggregateIndex, isEmpty);
      expect(one.chart.bestX, isNull);
    });

    test('no session scales -> an empty chart the builders can skip', () {
      final none = buildSessionReportData(rows: const [
        SessionRow(blockId: '0', isInitial: '1', scaleName: 'UPDRS',
            scaleValue: '30'),
      ]);
      expect(none.chart.isEmpty, isTrue);
    });
  });

  group('rasterisers', () {
    test('renderScalesChartPng produces a PNG at the requested size', () async {
      final data = buildSessionReportData(rows: _exampleRows());
      final png = await renderScalesChartPng(data.chart,
          size: const Size(400, 200), pixelRatio: 2);
      expect(png, isNotNull);
      expect(pngSize(png!), (800, 400));
    });

    test('renderScalesChartPng returns null when there is nothing to plot',
        () async {
      final empty = buildSessionReportData(rows: const []);
      expect(await renderScalesChartPng(empty.chart), isNull);
    });

    test('renderElectrodePng produces a PNG at the requested size', () async {
      final catalog = ElectrodeCatalog.fromJson(
        jsonDecode(File('../schema/electrode_models.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      final png = await renderElectrodePng(
        catalog.models['Medtronic SenSight B33005']!,
        'case',
        'E2b_E2c',
        size: const Size(150, 320),
        pixelRatio: 2,
      );
      expect(pngSize(png), (300, 640));
    });
  });
}
