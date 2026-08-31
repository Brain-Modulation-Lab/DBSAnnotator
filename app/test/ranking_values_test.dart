/// Pins the aggregate index to exact NUMBERS over the committed example, not
/// just to which block wins.
///
/// The report shades rows and bands a figure on this index. Every existing test
/// asserts the ranking's *outcome* (best 7, second 6), so a regression that
/// shifted every value while preserving their order — a changed weight, a
/// changed clip, a changed default bound — would pass all of them silently.
library;

import 'dart:io';

import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'report_ranking_prefs.dart';

List<SessionRow> _example() => parseSessionTsv(
      File('../docs/_static/session_report_example/'
              'sub-01_ses-20260626_task-programming_run-01_events.tsv')
          .readAsStringSync(),
    );

void main() {
  late SessionReportData data;

  setUp(() => data = rankedReportData(_example(),
      generatedAt: DateTime(2026, 6, 26)));

  test('the aggregate index per block, to three decimals', () {
    // Five scales, all defaulted to mode `min` over 0..10, so each block scores
    // the mean of (1 - value/10) across its five ratings.
    const expected = {
      1: 0.430,
      2: 0.500,
      3: 0.490,
      4: 0.490,
      5: 0.335,
      6: 0.600,
      7: 0.675,
    };
    expect(data.chart.aggregateIndex.keys, expected.keys);
    for (final e in expected.entries) {
      expect(data.chart.aggregateIndex[e.key], closeTo(e.value, 5e-4),
          reason: 'block ${e.key}');
    }
  });

  test('the ranking margin is smaller than the session\'s own noise', () {
    // Blocks 6 and 7 are byte-identical in all ten stimulation columns and were
    // rated 9 s apart, so the gap between them is a measure of re-rating noise,
    // NOT of a stimulation effect. It is also the gap the report presents as
    // "optimal" vs "second-best". This test exists to keep that fact in front of
    // whoever next touches the ranking.
    final idx = data.chart.aggregateIndex;
    final replicateSpread = (idx[7]! - idx[6]!).abs();
    final betweenSettings = (idx[2]! - idx[3]!).abs();
    expect(replicateSpread, closeTo(0.075, 5e-4));
    expect(betweenSettings, closeTo(0.010, 5e-4));
    expect(replicateSpread, greaterThan(betweenSettings),
        reason: 'within-setting re-rating varies more than blocks 2 vs 3 do, '
            'so a rank order at this resolution is not defensible');
  });

  test('the worked example is 7 recording blocks over 6 distinct settings', () {
    // Blocks 6 and 7 are the identical pair; every other block differs.
    expect(data.numConfigs, 7);
    expect(data.numDistinctConfigs, 6);
    expect(configCountText(data), '7 (6 distinct settings)');
  });

  test('the session date and clock span come from the rows', () {
    expect(data.sessionDate, '2026-06-26');
    expect(data.generatedOn, '2026-06-26');
    expect(data.startTime, isNotEmpty);
    expect(data.sessionStamp, contains('2026-06-26'));
    // ASCII only: generated text must survive the PDF's Latin-1 fallback.
    expect(data.sessionStamp.runes.every((r) => r < 0x80), isTrue);
  });
}
