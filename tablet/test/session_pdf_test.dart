import 'package:dbs_annotator_tablet/core/session/session_row.dart';
import 'package:dbs_annotator_tablet/report/session_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Needed for the (attempted) rootBundle font load; the Roboto TTFs are
  // not bundled in tests, so buildSessionPdf falls back to Helvetica.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildSessionPdf returns non-empty %PDF bytes', () async {
    final rows = [
      // Baseline (is_initial = 1) with clinical scales + initial notes.
      const SessionRow(
        date: '2026-07-29',
        time: '09:00:00',
        blockId: '0',
        sessionId: '1',
        isInitial: '1',
        scaleName: 'UPDRS-III',
        scaleValue: '32',
        electrodeModel: 'SenSight B33005',
        leftAnode: 'C',
        leftCathode: '1',
        rightAnode: 'C',
        rightCathode: '9',
        notes: 'Baseline assessment before titration',
      ),
      // Recording block with a split amplitude ("1.5_1" sums to 2.5 in the
      // programming summary), a unit-bearing pulse width (µs), and a note.
      const SessionRow(
        date: '2026-07-29',
        time: '09:30:00',
        blockId: '1',
        sessionId: '1',
        isInitial: '0',
        scaleName: 'Tremor',
        scaleValue: '2',
        electrodeModel: 'SenSight B33005',
        programId: 'A',
        leftStimFreq: '130',
        leftAnode: 'C',
        leftCathode: '1_2',
        leftAmplitude: '1.5_1',
        leftPulseWidth: '60 µs',
        rightStimFreq: '130',
        rightAnode: 'C',
        rightCathode: '9',
        rightAmplitude: '2',
        rightPulseWidth: '60',
        notes: 'Paresthesia at 2.5 mA, resolved after 30 s',
      ),
      // Second recording block; omitted scale value ("NaN") must be skipped.
      const SessionRow(
        date: '2026-07-29',
        time: '10:15:00',
        blockId: '2',
        sessionId: '1',
        isInitial: '0',
        scaleName: 'Tremor',
        scaleValue: 'NaN',
        electrodeModel: 'SenSight B33005',
        programId: 'B',
        leftStimFreq: '180',
        leftAnode: 'C',
        leftCathode: '2',
        leftAmplitude: '3',
        leftPulseWidth: '90',
        rightStimFreq: '180',
        rightAnode: 'C',
        rightCathode: '10',
        rightAmplitude: '3',
        rightPulseWidth: '90',
      ),
    ];

    final bytes = await buildSessionPdf(
      rows: rows,
      subjectId: '01',
      generatedAt: DateTime(2026, 7, 29),
    );

    expect(bytes, isNotEmpty);
    // PDF magic: "%PDF" = 0x25 0x50 0x44 0x46.
    expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
  });

  test('empty rows still yield a valid PDF', () async {
    final bytes = await buildSessionPdf(
      rows: const [],
      subjectId: 'unknown',
      generatedAt: DateTime(2026, 7, 29),
    );
    expect(bytes, isNotEmpty);
    expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
  });
}
