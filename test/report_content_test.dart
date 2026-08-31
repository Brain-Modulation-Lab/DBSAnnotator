/// The content the two expert reviews asked for, pinned where it is cheap: in
/// `report_data`, which both builders render from.
library;

import 'dart:io';

import 'package:dbs_annotator/core/session/scale_scoring.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'report_ranking_prefs.dart';

List<SessionRow> _example() => parseSessionTsv(
      File('test/fixtures/sub-01_ses-20260626_task-programming_run-01_events.tsv')
          .readAsStringSync(),
    );

void main() {
  group('over the committed example', () {
    late SessionReportData data;
    setUp(() => data = rankedReportData(_example()));

    test('the table carries a time and an index per block', () {
      final time = sessionTableHeaders.indexOf('Time');
      final index = sessionTableHeaders.indexOf('Index');
      expect(time, greaterThanOrEqualTo(0));
      expect(index, greaterThanOrEqualTo(0));

      // tableData is two rows per block, L then R; the block-level cells sit on
      // the L row.
      final first = data.tableData.first;
      expect(first[time], matches(RegExp(r'^\d{2}:\d{2}:\d{2}$')));
      expect(first[index], contains('0.430'));
      expect(first[index], contains('rank 6'),
          reason: 'block 1 is the 6th best of 7');
      // The R row leaves them blank rather than repeating them.
      expect(data.tableData[1][time], isEmpty);
      expect(data.tableData[1][index], isEmpty);
    });

    test('one weight per column, summing to 100', () {
      expect(sessionTableColumnWeights, hasLength(sessionTableHeaders.length));
      expect(sessionTableColumnWeights.fold<double>(0, (a, b) => a + b), 100);
    });

    test('a note becomes a line in Recorded observations', () {
      // The notes column is the only adverse-event data the format captures.
      expect(data.observations, isNotEmpty);
      final warm =
          data.observations.firstWhere((o) => o.contains('warm rush'));
      expect(warm, startsWith('Block 4'));
      expect(warm, contains('16:47:11'), reason: 'when it happened');
      expect(warm, contains('%'), reason: 'and under what stimulation');
    });

    test('response reports first -> last per scale', () {
      final byName = {for (final r in data.response) r.name: r};
      expect(byName.keys,
          containsAll(['Obsessions', 'Compulsions', 'Anxiety', 'Mood']));
      expect(byName['Obsessions']!.first, 7.25);
      expect(byName['Obsessions']!.last, 2.25);
    });

    test('n scales rated per block, so the index is interpretable', () {
      // Every block in the example rates all five.
      expect(data.scalesRated.values.toSet(), {5});
    });

    test('the Time cell carries the gap from the previous block', () {
      final time = sessionTableHeaders.indexOf('Time');
      // Block 1 is the first, so no gap; block 2 follows it by 8 s. The gap is
      // what makes the 9 s between blocks 6 and 7 - identical stimulation,
      // ranked 1 and 2 - visible without doing arithmetic.
      expect(data.tableData[0][time], '16:46:37');
      final second = data.tableData[2][time];
      expect(second, startsWith('16:46:45'));
      expect(second, contains('(+8 s)'));
      expect(data.tableData[data.tableData.length - 2][time],
          contains('(+9 s)'));
    });

    test('parameters list their distinct values and the blocks that used them',
        () {
      // "5.0 - 7.0 mA" hid that the right side went 5.0 -> 6.0 -> 7.0 -> 5.0 ->
      // 7.0 -> 6.0, and implied a titration that never happened.
      expect(data.ampL, '5.5 mA (blocks 1-5), 4.5 mA (blocks 6-7)');
      expect(data.ampR, contains('7.0 mA (blocks 3, 5)'));
    });

    test('an unchanged parameter says so instead of a degenerate range', () {
      expect(data.freqL, '125 Hz (unchanged)');
      expect(data.pwR, '90 µs (unchanged)');
    });

    test('the figure caption names the subject, the n and the green', () {
      expect(data.figureCaption, contains('7 blocks x 5 scales'));
      expect(data.figureCaption, contains('35 of 35 rated'));
      expect(data.figureCaption, contains('Green bands'));
    });

    test('with no targets the caption says why there is no green', () {
      final bare = buildSessionReportData(rows: _example());
      expect(bare.figureCaption, contains('No scale targets were set'));
      expect(bare.figureCaption, isNot(contains('Green bands')));
    });

    test('the index method is stated, not just the modes', () {
      expect(data.indexMethod, contains('unweighted mean'));
      expect(data.indexMethod, contains('half weight'));
    });
  });

  group('contact rendering', () {
    test('a split is shown as percentages that sum to 100', () {
      // Three equal contacts rounded independently print 33/33/33 = 99 %, which
      // reads as a missing share.
      expect(contactsWithCurrent('E2a_E2b_E2c', '1.67_1.67_1.67'),
          '2a(34%) 2b(33%) 2c(33%)');
      expect(contactsWithCurrent('E2b_E2c', '3.3_2.2'), '2b(60%) 2c(40%)');
    });

    test('a single contact gets no parenthetical', () {
      expect(contactsWithCurrent('E2c', '4.5'), '2c');
      expect(contactsWithCurrent('case', ''), 'case');
    });

    test('the E prefix and the underscore never reach the page', () {
      final out = contactsWithCurrent('E2b_E2c', '3.3_2.2');
      expect(out, isNot(contains('E')));
      expect(out, isNot(contains('_')));
    });

    test('a count mismatch prints the contacts alone rather than guessing', () {
      expect(contactsWithCurrent('E2b_E2c', '5.5'), '2b 2c');
    });
  });

  group('no targets means no ranking', () {
    test('nothing is invented for an externally-authored TSV', () {
      // Fabricating `min` over 0..10 produced an index, two green bands and a
      // printed "Scale targets" line asserting an intent nobody expressed — in
      // this example, that falling Mood and Energy were improvements.
      final bare = buildSessionReportData(rows: _example());
      expect(bare.hasTargets, isFalse);
      expect(bare.chart.aggregateIndex, isEmpty);
      expect(bare.chart.bestX, isNull);
      expect(bare.bestBlocks, isEmpty);
      expect(bare.secondBlocks, isEmpty);
      expect(bare.targetsText, kNoTargetsText);
    });

    test('an all-ignore pref set counts as no targets', () {
      final ignored = buildSessionReportData(
        rows: _example(),
        scalePrefs: const [
          (name: 'Obsessions', min: 0, max: 10, mode: ScaleMode.ignore,
              custom: null),
        ],
      );
      expect(ignored.hasTargets, isFalse);
      expect(ignored.chart.bestX, isNull);
    });
  });

  group('provenance and honesty', () {
    test('the session stamp carries the UTC offset', () {
      // The `timezone` column holds a Windows display name plus an offset
      // ("W. Europe Daylight Time +0200"); only the offset half is portable,
      // and a clinical timestamp with no zone is ambiguous across DST.
      final data = rankedReportData(_example());
      expect(data.utcOffset, '+02:00');
      expect(data.sessionStamp, contains('(UTC+02:00)'));
      // Still ASCII, so the PDF's Latin-1 fallback can draw it.
      expect(data.sessionStamp.runes.every((r) => r < 0x80), isTrue);
    });

    test('rows with no timezone yield no offset rather than a wrong one', () {
      final data = buildSessionReportData(rows: const [
        SessionRow(
            blockId: '1', isInitial: '0', date: '2026-01-01', time: '09:00:00'),
      ]);
      expect(data.utcOffset, isEmpty);
      expect(data.sessionStamp, isNot(contains('UTC')));
    });

    test('the source file and row count are carried through', () {
      final rows = _example();
      final data = buildSessionReportData(rows: rows, sourceFile: 'a_file.tsv');
      expect(data.sourceFile, 'a_file.tsv');
      expect(data.rowCount, rows.length);
    });

    test('targets print the bounds the index normalised into', () {
      // Without them a reader cannot reproduce a score, and the ranking turns
      // on the third decimal.
      expect(rankedReportData(_example()).targetsText,
          contains('Obsessions: min of 0-10'));
    });

    test('the instrument note says what the record cannot support', () {
      final note = rankedReportData(_example()).instrumentNote;
      expect(note, contains('anchors'));
      expect(note, contains('rater'));
    });
  });

  test('the disclaimer names what the ranking ignores', () {
    expect(kRankingDisclaimer, contains('side effects'));
    expect(kRankingDisclaimer, contains('tolerability'));
    expect(kRankingDisclaimer, contains('Notes'));
  });
}
