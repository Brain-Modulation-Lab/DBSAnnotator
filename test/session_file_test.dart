import 'dart:io';

import 'package:dbs_annotator/core/schema_columns.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final stamp = DateTime(2026, 7, 27, 10, 30, 5);

  group('buildInsertRows', () {
    test('one row per valid scale, sharing insert-level fields', () {
      final rows = buildInsertRows(
        blockId: 3,
        sessionId: 2,
        scales: const [
          (name: 'Mood', value: '7'),
          (name: 'Anxiety', value: ''), // blank value -> dropped
          (name: 'Tremor', value: '2.5'),
        ],
        programId: 'B',
        electrodeModel: 'SenSight B33005',
        notes: 'felt better',
        leftStimFreq: '130',
        leftAnode: 'C',
        leftCathode: '2',
        leftAmplitude: '1.5_1',
        leftPulseWidth: '60',
        rightStimFreq: '130',
        at: stamp,
      );

      expect(rows.length, 2);
      expect(rows.map((r) => r.scaleName), ['Mood', 'Tremor']);
      expect(rows.map((r) => r.scaleValue), ['7', '2.5']);
      for (final row in rows) {
        expect(row.blockId, '3');
        expect(row.sessionId, '2');
        expect(row.isInitial, '0');
        expect(row.date, '2026-07-27');
        expect(row.time, '10:30:05');
        expect(row.timezone, isNotEmpty);
        expect(row.programId, 'B');
        expect(row.electrodeModel, 'SenSight B33005');
        expect(row.notes, 'felt better');
        expect(row.leftStimFreq, '130');
        expect(row.leftAmplitude, '1.5_1');
        expect(row.rightStimFreq, '130');
        expect(row.rightAmplitude, '');
      }
    });

    test('no valid scales -> a single row with empty scale fields', () {
      final rows = buildInsertRows(
        blockId: 0,
        sessionId: 1,
        scales: const [(name: 'Mood', value: '   ')],
        notes: 'stim only',
        at: stamp,
      );

      expect(rows.length, 1);
      expect(rows.single.scaleName, '');
      expect(rows.single.scaleValue, '');
      expect(rows.single.isInitial, '0');
      expect(rows.single.notes, 'stim only');
    });
  });

  group('nextBlockId / nextSessionId', () {
    test('continue numbering from the max, like open_file_append', () {
      const existing = [
        SessionRow(blockId: '0', sessionId: '1'),
        SessionRow(blockId: '2.0', sessionId: '1'), // float-style cell
        SessionRow(blockId: 'junk', sessionId: ''), // malformed -> skipped
        SessionRow(blockId: '1', sessionId: '3'),
      ];
      expect(nextBlockId(existing), 3);
      expect(nextSessionId(existing), 4);
    });

    test('empty file -> block 0, session 1', () {
      expect(nextBlockId(const []), 0);
      expect(nextSessionId(const []), 1);
    });
  });

  group('session TSV round trip', () {
    test('parse -> serialize -> parse preserves every cell', () {
      final original = buildInsertRows(
        blockId: 5,
        sessionId: 2,
        scales: const [(name: 'Mood', value: '4')],
        programId: 'A',
        electrodeModel: 'Cartesia X',
        notes: 'multi\nline note with a\ttab',
        leftStimFreq: '125.5',
        leftAnode: 'C',
        leftCathode: '1_2',
        leftAmplitude: '1.5_1', // split amplitude must survive verbatim
        leftPulseWidth: '60',
        rightStimFreq: '130',
        rightAnode: 'C',
        rightCathode: '9',
        rightAmplitude: '2.0',
        rightPulseWidth: '90',
        at: stamp,
      );

      final reparsed = parseSessionTsv(serializeSessionTsv(original));
      expect(reparsed.length, original.length);
      for (var i = 0; i < original.length; i++) {
        expect(reparsed[i].toMap(), original[i].toMap());
      }
      expect(reparsed.single.leftAmplitude, '1.5_1');
      expect(reparsed.single.notes, 'multi\nline note with a\ttab');
    });

    test('header is the canonical column order, in full', () {
      // Spelled out rather than spot-checked: this line IS the published
      // contract, so a column silently renamed or reordered should fail here
      // and not first in someone's analysis script.
      expect(
        serializeSessionTsv(const []).trimRight(),
        'date\ttime\ttimezone\tacq_time\tblock_id\tsession_id\tis_initial\t'
        'scale_name\tscale_value\telectrode_model\tprogram_id\t'
        'left_stim_freq\tleft_anode\tleft_cathode\tleft_amplitude\t'
        'left_pulse_width\tright_stim_freq\tright_anode\tright_cathode\t'
        'right_amplitude\tright_pulse_width\tnotes',
      );
    });

    test('column names are BIDS-style snake_case', () {
      // BIDS: "It is RECOMMENDED that the column names ... are written in
      // snake_case with the first letter in lower case." The `block_ID` /
      // `session_ID` / `program_ID` spellings this replaced were not.
      for (final column in sessionColumns) {
        expect(column, matches(RegExp(r'^[a-z][a-z0-9_]*$')),
            reason: '$column is not snake_case');
      }
    });

    test('a pre-0.5.0 file with block_ID / NaN still reads', () {
      final legacy = File('test/fixtures/legacy_0.4_sub-01_ses-20260626_'
              'task-programming_run-01_events.tsv')
          .readAsStringSync();
      final rows = parseSessionTsv(legacy);

      expect(rows, isNotEmpty);
      // The pre-rename spellings resolve through `readColumn`.
      expect(rows.first.blockId, '0');
      expect(rows.first.sessionId, '1');
      expect(rows.first.programId, 'B');
      expect(rows.first.electrodeModel, 'Medtronic SenSight B33005');
      // No acq_time column existed then; it stays empty rather than inventing
      // an instant, and `timestamp` falls back to date + time.
      expect(rows.first.acqTime, '');
      expect(rows.first.timestamp, DateTime(2026, 6, 26, 16, 46, 14));
    });
  });
}
