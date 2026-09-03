import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/ui/session/entries_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two blocks, three scales each: the shape that made the old table unreadable.
const _rows = [
  SessionRow(
      blockId: '1',
      isInitial: '0',
      date: '2026-01-01',
      time: '09:00:00',
      programId: 'A',
      leftStimFreq: '130',
      leftAmplitude: '2.5',
      leftPulseWidth: '60',
      scaleName: 'Tremor',
      scaleValue: '4',
      notes: 'warm rush'),
  SessionRow(
      blockId: '1',
      isInitial: '0',
      date: '2026-01-01',
      time: '09:00:00',
      programId: 'A',
      leftStimFreq: '130',
      leftAmplitude: '2.5',
      leftPulseWidth: '60',
      scaleName: 'Rigidity',
      scaleValue: '2',
      notes: 'warm rush'),
  SessionRow(
      blockId: '2',
      isInitial: '0',
      date: '2026-01-01',
      time: '09:12:00',
      programId: 'A',
      leftStimFreq: '130',
      leftAmplitude: '3.5',
      leftPulseWidth: '60',
      scaleName: 'Tremor',
      scaleValue: '1'),
];

Future<void> _pump(WidgetTester tester, List<SessionRow> rows) =>
    tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SessionEntriesTable(rows: rows))));

void main() {
  test('blockCount counts blocks, not TSV rows', () {
    // The label says "blocks" because one block writes one row per scale, so a
    // row count reads several times too high.
    expect(blockCount(_rows), 2);
    expect(blockCount(const []), 0);
  });

  testWidgets('block-level columns are printed once per block', (tester) async {
    await _pump(tester, _rows);

    // Two blocks share the same programme, so the cell appears twice — not
    // three times, which is what one-row-per-scale used to produce.
    expect(find.text('A'), findsNWidgets(2));
    expect(find.text('2026-01-01 09:00:00'), findsOneWidget,
        reason: 'no baseline row here, so the first block keeps the date');
    expect(find.text('09:12:00'), findsOneWidget,
        reason: 'later blocks show the clock time only');
    expect(find.text('130 / 2.5 / 60'), findsOneWidget);
    expect(find.text('warm rush'), findsOneWidget);

    // Scale and value are the columns that actually differ, so every row keeps
    // its own pair.
    expect(find.text('Tremor'), findsNWidgets(2));
    expect(find.text('Rigidity'), findsOneWidget);
  });

  testWidgets('the date is carried by the baseline row, not by every block',
      (tester) async {
    await _pump(tester, [
      const SessionRow(
          blockId: '0',
          isInitial: '1',
          date: '2026-01-01',
          time: '08:55:00',
          scaleName: 'Y-BOCS',
          scaleValue: '30'),
      ..._rows,
    ]);
    // Baseline: the date, which is a property of the session.
    expect(find.text('2026-01-01'), findsOneWidget);
    // Recording blocks: the clock time only.
    expect(find.text('09:00:00'), findsOneWidget);
    expect(find.text('09:12:00'), findsOneWidget);
    expect(find.textContaining('2026-01-01 09:'), findsNothing);
  });

  testWidgets('empty rows show a message rather than a bare header',
      (tester) async {
    await _pump(tester, const []);
    expect(find.text('No entries inserted yet.'), findsOneWidget);
  });
}
