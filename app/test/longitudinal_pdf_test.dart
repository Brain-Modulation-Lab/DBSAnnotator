import 'package:dbs_annotator/report/longitudinal_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildLongitudinalPdf returns non-empty %PDF bytes', () async {
    final bytes = await buildLongitudinalPdf(
      filenames: const [
        'sub-01_ses-20260101_task-programming_run-01_events.tsv',
        'sub-01_ses-20260201_task-programming_run-01_events.tsv',
      ],
      timeline: const {
        'Mood': {0: 3, 1: 2.5, 3: 4},
        'Anxiety': {0: 5, 3: 1},
      },
      generatedAt: DateTime(2026, 7, 29),
    );

    expect(bytes, isNotEmpty);
    // PDF magic: "%PDF" = 0x25 0x50 0x44 0x46.
    expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
  });

  test('empty timeline still yields a valid PDF', () async {
    final bytes = await buildLongitudinalPdf(
      filenames: const ['unlabeled.tsv'],
      timeline: const {},
    );
    expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
  });
}
