import 'package:dbs_annotator/core/session/longitudinal.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scaleTimeline', () {
    test('newline-separated scales map to {name: {block: value}}', () {
      const rows = [
        // Merged-style row: two scales in one cell.
        SessionRow(
          blockId: '0',
          isInitial: '0',
          scaleName: 'Mood\nAnxiety',
          scaleValue: '3\n5',
        ),
        // Plain one-scale-per-row entries, float block id string.
        SessionRow(
          blockId: '1.0',
          isInitial: '0',
          scaleName: 'Mood',
          scaleValue: '2',
        ),
        // Omitted value ("NaN" sentinel) -> skipped.
        SessionRow(
          blockId: '1',
          isInitial: '0',
          scaleName: 'Tremor',
          scaleValue: 'NaN',
        ),
        // Non-numeric value -> skipped.
        SessionRow(
          blockId: '1',
          isInitial: '0',
          scaleName: 'Anxiety',
          scaleValue: 'high',
        ),
        // Clinical (is_initial=1) row -> excluded from the session timeline.
        SessionRow(
          blockId: '2',
          isInitial: '1',
          scaleName: 'YBOCS',
          scaleValue: '20',
        ),
      ];

      expect(scaleTimeline(rows), {
        'Mood': {0: 3.0, 1: 2.0},
        'Anxiety': {0: 5.0},
      });
    });

    test('last value wins within a block; blank is_initial counts as 0', () {
      const rows = [
        SessionRow(blockId: '0', scaleName: 'Mood', scaleValue: '3'),
        SessionRow(blockId: '0', scaleName: 'Mood', scaleValue: '4'),
      ];
      expect(scaleTimeline(rows), {
        'Mood': {0: 4.0},
      });
    });
  });

  group('splitScalePairs', () {
    test('pads missing values and drops blank lines', () {
      expect(splitScalePairs('Mood\n\nAnxiety', '3'), [
        (name: 'Mood', value: '3'),
        (name: 'Anxiety', value: ''),
      ]);
    });
  });

  group('patient IDs', () {
    test('extractPatientId uses sub-([^_]+) on the basename', () {
      expect(
        extractPatientId('sub-01_ses-20260724_task-programming_run-01'
            '_events.tsv'),
        '01',
      );
      expect(
        extractPatientId(
            r'C:\data\sub-P07x_ses-20260101_task-programming_events.tsv'),
        'P07x',
      );
      expect(extractPatientId('session_notes.tsv'), '');
      // A "sub-" in a parent folder must not leak into the ID.
      expect(extractPatientId('/data/sub-99/plain_notes.tsv'), '');
    });

    test('patientIdsMatch ignores files without an ID', () {
      expect(
        patientIdsMatch(const [
          'sub-01_ses-20260101_events.tsv',
          'sub-01_ses-20260201_events.tsv',
          'unlabeled.tsv',
        ]),
        isTrue,
      );
      expect(
        patientIdsMatch(const [
          'sub-01_ses-20260101_events.tsv',
          'sub-02_ses-20260101_events.tsv',
        ]),
        isFalse,
      );
      expect(patientIdsMatch(const []), isTrue);
    });
  });
}
