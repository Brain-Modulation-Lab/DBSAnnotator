import 'package:dbs_annotator_tablet/core/session/session_row.dart';
import 'package:dbs_annotator_tablet/ui/longitudinal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('combinedScaleTimeline', () {
    test('offsets each file onto a sequential block axis', () {
      const fileA = [
        SessionRow(blockId: '0', scaleName: 'Mood', scaleValue: '3'),
        SessionRow(blockId: '1', scaleName: 'Mood', scaleValue: '4'),
      ];
      const fileB = [
        SessionRow(blockId: '0', scaleName: 'Mood', scaleValue: '2'),
        SessionRow(blockId: '0', scaleName: 'Anxiety', scaleValue: '5'),
      ];
      expect(combinedScaleTimeline(const [fileA, fileB]), {
        'Mood': {0: 3.0, 1: 4.0, 2: 2.0},
        'Anxiety': {2: 5.0},
      });
    });

    test('single file is identical to its own timeline; empty input is {}',
        () {
      const rows = [
        SessionRow(blockId: '0', scaleName: 'Mood', scaleValue: '3'),
      ];
      expect(combinedScaleTimeline(const [rows]), {
        'Mood': {0: 3.0},
      });
      expect(combinedScaleTimeline(const []), isEmpty);
    });
  });

  testWidgets('LongitudinalScreen shows the empty-state import prompt',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LongitudinalScreen()),
    );
    expect(find.text('No sessions imported yet.'), findsOneWidget);
    expect(find.text('Import session TSVs'), findsOneWidget);
  });
}
