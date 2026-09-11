/// The timestamp model: one stored column, two ways of reading it.
///
/// Two things matter here: the backfill that keeps pre-0.5.0 files readable,
/// and the wall-clock/instant split that keeps a clinical report honest.
library;

import 'package:dbs_annotator/core/timestamps.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('offsetFromTimezoneCell', () {
    // Both forms the app and the Qt desktop ever wrote. The Windows one is why
    // this is a regex and not a substring: `timeZoneName` returns a display
    // name, and the offset is glued to the end of it.
    test('reads the ISO form written by this app', () {
      expect(offsetFromTimezoneCell('UTC +00:00'), '+00:00');
      expect(offsetFromTimezoneCell('CEST +02:00'), '+02:00');
    });

    test('reads the compact Windows form', () {
      expect(
        offsetFromTimezoneCell('W. Europe Daylight Time +0200'),
        '+02:00',
        reason: 'no colon in the source, but the output is normalised',
      );
      expect(offsetFromTimezoneCell('Eastern Standard Time -0500'), '-05:00');
    });

    test('a zone name with no offset yields nothing, not a guess', () {
      // The pre-0.5.0 annotations writer emitted exactly this: a bare name.
      // Guessing an offset here would silently relocate the clinic.
      expect(offsetFromTimezoneCell('CEST'), '');
      expect(offsetFromTimezoneCell(''), '');
    });
  });

  group('backfillAcqTime', () {
    test('composes an instant from the retired cells, offset included', () {
      expect(
        backfillAcqTime(
          date: '2026-02-03',
          time: '09:00:00',
          timezone: 'UTC +00:00',
        ),
        '2026-02-03T09:00:00+00:00',
      );
    });

    test('handles the Windows zone form', () {
      expect(
        backfillAcqTime(
          date: '2026-06-26',
          time: '16:46:14',
          timezone: 'W. Europe Daylight Time +0200',
        ),
        '2026-06-26T16:46:14+02:00',
      );
    });

    // The important negative case. A zone-less result says "this clock
    // reading, offset unknown", which is true. Stamping it with the READING
    // machine's offset would assert a clinic location that could be hours
    // wrong, and would do it invisibly.
    test(
      'an unparsable zone yields a zone-less instant, never a local one',
      () {
        final out = backfillAcqTime(
          date: '2026-02-03',
          time: '09:00:00',
          timezone: 'CEST',
        );
        expect(out, '2026-02-03T09:00:00');
        expect(out, isNot(contains('+')));
        expect(out, isNot(contains('Z')));
      },
    );

    test('a missing time defaults to midnight rather than failing', () {
      expect(
        backfillAcqTime(date: '2026-02-03', time: '', timezone: ''),
        '2026-02-03T00:00:00',
      );
    });

    test('no date at all yields empty, which the writer renders as n/a', () {
      expect(backfillAcqTime(date: '', time: '09:00:00', timezone: ''), '');
      expect(
        backfillAcqTime(date: 'not-a-date', time: '09:00:00', timezone: ''),
        '',
      );
    });
  });

  group('recordedDate / recordedTime: the wall clock, never converted', () {
    // The defect these exist to prevent: reading `acq_time` as a DateTime and
    // formatting it renders the instant in the READER's zone, so a block
    // recorded at 09:00 in Geneva prints as 03:00 in Chicago. A clinical
    // record must show the time it happened where it happened.
    test('an offset timestamp reads back as the recorded wall clock', () {
      const iso = '2026-02-03T09:00:00+00:00';
      expect(recordedDate(iso), '2026-02-03');
      expect(
        recordedTime(iso),
        '09:00:00',
        reason: 'the clinic clock, whatever zone this machine is in',
      );
    });

    test('a large offset does not shift the displayed clock', () {
      // Same wall clock, wildly different instants: display must not care.
      expect(recordedTime('2026-02-03T09:00:00+13:00'), '09:00:00');
      expect(recordedTime('2026-02-03T09:00:00-11:00'), '09:00:00');
      expect(recordedDate('2026-02-03T09:00:00-11:00'), '2026-02-03');
    });

    test('accepts the space separator an external tool may write', () {
      expect(recordedTime('2026-02-03 09:00:00+00:00'), '09:00:00');
    });

    test('a zone-less instant still displays', () {
      expect(recordedDate('2026-02-03T09:00:00'), '2026-02-03');
      expect(recordedTime('2026-02-03T09:00:00'), '09:00:00');
    });

    test('junk yields empty rather than throwing into a report', () {
      for (final bad in ['', 'n/a', 'yesterday', '2026-02-03']) {
        expect(recordedDate(bad), '', reason: bad);
        expect(recordedTime(bad), '', reason: bad);
      }
    });
  });

  group('acqTimeCell', () {
    test('round-trips through the wall-clock readers', () {
      final dt = DateTime.utc(2026, 2, 3, 9, 30, 5);
      final cell = acqTimeCell(dt);
      expect(cell, '2026-02-03T09:30:05+00:00');
      expect(recordedDate(cell), '2026-02-03');
      expect(recordedTime(cell), '09:30:05');
      expect(DateTime.parse(cell), dt);
    });
  });
}
