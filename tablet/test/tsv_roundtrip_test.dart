import 'package:dbs_annotator_tablet/core/annotation.dart';
import 'package:dbs_annotator_tablet/core/bids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('annotations TSV', () {
    test('round-trips, preserving embedded newlines in notes', () {
      final items = <Annotation>[
        const Annotation(
          date: '2026-07-24',
          time: '10:00:00',
          timezone: 'CEST',
          notes: 'first note',
        ),
        const Annotation(
          date: '2026-07-24',
          time: '10:05:00',
          timezone: 'CEST',
          notes: 'multi\nline note with a\ttab',
        ),
      ];

      final tsv = writeAnnotations(items);
      final parsed = parseAnnotations(tsv);

      expect(parsed.length, 2);
      expect(parsed[0].date, '2026-07-24');
      expect(parsed[1].notes, 'multi\nline note with a\ttab');
    });

    test('header is the canonical column order', () {
      final tsv = writeAnnotations(const []);
      expect(tsv.trimRight(), 'date\ttime\ttimezone\tnotes');
    });
  });

  group('BIDS', () {
    test('builds and parses the events filename', () {
      const name = BidsName(
        subject: '01',
        session: '20260724',
        task: 'notes',
        run: '01',
      );
      expect(name.filename,
          'sub-01_ses-20260724_task-notes_run-01_events.tsv');

      final parsed = BidsName.parse(name.filename)!;
      expect(parsed.subject, '01');
      expect(parsed.task, 'notes');
      expect(parsed.run, '01');
    });
  });
}
