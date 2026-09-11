// Regenerate the synthetic example session used by the tests and the docs.
//
//   dart run tool/generate_fixtures.dart
//
// ## Why this file exists
//
// The example session is **synthetic**: every rating, every stimulation
// parameter and every timestamp below is invented. It replaced a real patient's
// recorded session, which the repository had been publishing as a `:download:`
// link on Read the Docs — a full date to the second, a UTC offset, the implanted
// lead model, an OCD-plus-depression scale set and clinical notes that still
// carried elisions where identifying detail had been removed.
//
// Generating rather than hand-editing buys three things. The file is written by
// the app's own `buildInsertRows` + `serializeSessionTsv`, so its header, column
// order, `n/a` sentinel, line endings and largest-remainder amplitude encoding
// are exactly what the app produces — a hand-written fixture drifts from the
// writer the moment either changes. The provenance is auditable: anyone can read
// this file and see that no recorded data went into it. And the numbers below are
// *designed*, which matters because several tests pin values derived from them.
//
// ## The structure the tests depend on — change with care
//
// `test/ranking_values_test.dart` and `test/report_graphics_test.dart` assert
// properties of this data, not just that code runs. Preserve all of these or
// re-derive the expected values:
//
//  * 1 baseline block (`is_initial=1`, clinical scales) + 7 recording blocks
//    × 5 session scales = 35 rated rows.
//  * **A replicate pair**: blocks 6 and 7 are byte-identical across all ten
//    stimulation columns and rated 9 seconds apart. They are the session's own
//    measure of re-rating noise.
//  * **An identical-ratings pair**: blocks 3 and 4 carry the same five ratings
//    under *different* stimulation, so the record cannot distinguish a
//    re-rating from values carried forward.
//  * **Replicate spread must exceed between-setting separation.** Here 0.070
//    (blocks 6→7) against 0.010 (blocks 2 vs 3). That inequality is asserted
//    directly, because it is what makes the report's own warning true: two
//    settings closer together than the noise are not distinguishable.
//  * 6 distinct stimulation settings across the 7 recording blocks.
//  * At least one current-split block, so the percentage rendering is covered
//    (block 4 splits three ways, which also exercises the 33/33/34
//    largest-remainder case).
//
// With every scale targeted `min` over 0–10, a block's aggregate index is the
// mean of `1 - value/10` over its five ratings. The designed indices are:
//
//   block 1  0.380   block 2  0.460   block 3  0.450   block 4  0.450
//   block 5  0.270   block 6  0.580   block 7  0.650
//
// ranked: 7, 6, 2, 3, 4, 1, 5 — so the best *setting* is blocks 6+7 (mean
// 0.615) and the second is block 2, while block 1 is rank 6.

import 'dart:io';

import 'package:dbs_annotator/core/schema_columns.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/core/timestamps.dart';
import 'package:dbs_annotator/core/tsv.dart';

/// A fictional instant, in UTC. UTC on purpose: the data is invented, and a
/// non-zero offset would invite a reader to infer a recording site that does
/// not exist, and it makes `acq_time` end in `+00:00`.
final DateTime _start = DateTime.utc(2026, 2, 3, 9);

const String _model = 'Medtronic SenSight B33005';
const String _program = 'B';
const String _freq = '130';
const String _pulseWidth = '60';

/// One recording block: when it was rated, its stimulation, and its ratings.
typedef _Block = ({
  int seconds, // offset from _start
  String leftCathode,
  String leftAmplitude,
  String rightCathode,
  String rightAmplitude,
  List<double> ratings, // Obsessions, Compulsions, Anxiety, Mood, Energy
  String notes,
});

const List<String> _sessionScales = [
  'Obsessions',
  'Compulsions',
  'Anxiety',
  'Mood',
  'Energy',
];

// Left lead: a two-segment split for most of the visit, narrowed to one segment
// for the last setting. Right lead: a ring titrated up, then two split-current
// settings, then back to the ring at a lower amplitude.
const List<_Block> _blocks = [
  // Deliberately unremarkable intervals of one to three minutes between
  // settings - long enough to set a parameter and take five ratings...
  (
    seconds: 200,
    leftCathode: 'E1b_E1c',
    leftAmplitude: '3.0_2.0',
    rightCathode: 'E3',
    rightAmplitude: '4.0',
    ratings: [8.00, 7.50, 5.00, 6.50, 4.00],
    notes: 'starting configuration carried over from the last visit',
  ),
  (
    seconds: 305,
    leftCathode: 'E1b_E1c',
    leftAmplitude: '3.0_2.0',
    rightCathode: 'E3',
    rightAmplitude: '5.0',
    ratings: [6.50, 6.00, 4.50, 6.00, 4.00],
    notes: '',
  ),
  (
    seconds: 460,
    leftCathode: 'E1b_E1c',
    leftAmplitude: '3.0_2.0',
    rightCathode: 'E3',
    rightAmplitude: '6.0',
    ratings: [6.25, 6.25, 4.75, 5.75, 4.50],
    notes: '',
  ),
  // Same five ratings as block 3 under different stimulation: the record cannot
  // tell a genuine re-rating from values carried forward, and the report says so.
  (
    seconds: 555,
    leftCathode: 'E1b_E1c',
    leftAmplitude: '3.0_2.0',
    rightCathode: 'E2a_E2b_E2c',
    rightAmplitude: '2.0_2.0_2.0',
    ratings: [6.25, 6.25, 4.75, 5.75, 4.50],
    notes: 'transient warmth on the right, settled within a minute',
  ),
  (
    seconds: 710,
    leftCathode: 'E1b_E1c',
    leftAmplitude: '3.0_2.0',
    rightCathode: 'E2a_E2b_E2c',
    rightAmplitude: '2.5_2.5_2.5',
    ratings: [7.00, 7.25, 8.00, 6.75, 7.50],
    notes: 'reported feeling anxious and low; amplitude reduced',
  ),
  (
    seconds: 870,
    leftCathode: 'E1c',
    leftAmplitude: '4.0',
    rightCathode: 'E3',
    rightAmplitude: '5.0',
    ratings: [4.00, 3.75, 4.25, 5.50, 3.50],
    notes: 'settled, obsessions much reduced',
  ),
  // ...and then one interval of NINE SECONDS on identical stimulation. Nine
  // seconds is not a plausible re-administration of five 0-10 ratings, which is
  // exactly the point: this pair is the session's noise floor, and the report
  // flags it rather than ranking the two against each other.
  (
    seconds: 879,
    leftCathode: 'E1c',
    leftAmplitude: '4.0',
    rightCathode: 'E3',
    rightAmplitude: '5.0',
    ratings: [2.75, 3.00, 4.00, 4.75, 3.00],
    notes: 're-rated on the same setting',
  ),
];

/// The baseline assessment: clinical instruments, before any change.
/// `Y-BOCS` is the sum of its obsession and compulsion subscales, as the
/// instrument defines it.
const List<ScaleEntry> _clinicalScales = [
  (name: 'Y-BOCS', value: '28'),
  (name: 'Y-BOCS-o', value: '15'),
  (name: 'Y-BOCS-c', value: '13'),
  (name: 'MADRS', value: '24'),
];

String _fmt(double v) => v.toStringAsFixed(2);

List<SessionRow> _rows() => [
  ...buildInsertRows(
    blockId: 0,
    appendId: 1,
    isInitial: true,
    scales: _clinicalScales,
    programId: _program,
    electrodeModel: _model,
    notes: 'baseline assessment before any change this visit',
    leftStimFreq: _freq,
    leftAnode: 'case',
    leftCathode: _blocks.first.leftCathode,
    leftAmplitude: _blocks.first.leftAmplitude,
    leftPulseWidth: _pulseWidth,
    rightStimFreq: _freq,
    rightAnode: 'case',
    rightCathode: _blocks.first.rightCathode,
    rightAmplitude: _blocks.first.rightAmplitude,
    rightPulseWidth: _pulseWidth,
    at: _start,
  ),
  for (var i = 0; i < _blocks.length; i++)
    ...buildInsertRows(
      blockId: i + 1,
      appendId: 1,
      scales: [
        for (var s = 0; s < _sessionScales.length; s++)
          (name: _sessionScales[s], value: _fmt(_blocks[i].ratings[s])),
      ],
      programId: _program,
      electrodeModel: _model,
      notes: _blocks[i].notes,
      leftStimFreq: _freq,
      leftAnode: 'case',
      leftCathode: _blocks[i].leftCathode,
      leftAmplitude: _blocks[i].leftAmplitude,
      leftPulseWidth: _pulseWidth,
      rightStimFreq: _freq,
      rightAnode: 'case',
      rightCathode: _blocks[i].rightCathode,
      rightAmplitude: _blocks[i].rightAmplitude,
      rightPulseWidth: _pulseWidth,
      at: _start.add(Duration(seconds: _blocks[i].seconds)),
    ),
];

/// The pre-0.5.0 spelling of the same data, so the `legacyColumnAliases` read
/// path keeps a real file to exercise. 21 columns, `block_ID`/`session_ID`/
/// `program_ID`, no `acq_time`, and `NaN` where 0.5.0 writes `n/a`.
String _legacyDocument(List<SessionRow> rows) {
  const legacyColumns = [
    'date',
    'time',
    'timezone',
    'block_ID',
    'session_ID',
    'is_initial',
    'scale_name',
    'scale_value',
    'electrode_model',
    'program_ID',
    'left_stim_freq',
    'left_anode',
    'left_cathode',
    'left_amplitude',
    'left_pulse_width',
    'right_stim_freq',
    'right_anode',
    'right_cathode',
    'right_amplitude',
    'right_pulse_width',
    'notes',
  ];
  const rename = {
    'block_id': 'block_ID',
    'append_id': 'session_ID',
    'program_id': 'program_ID',
  };
  // A 0.4.x file has NO `acq_time` — it stored the instant as `date` + `time`
  // plus a free-text `timezone`. So the instant is decomposed back into those
  // three cells here, which is what makes this fixture a real regression test
  // for `backfillAcqTime`: reading it back must reconstruct the same instant,
  // offset included, from nothing but these.
  //
  // The fixture is generated at a UTC instant, so the zone cell says so. The
  // harder Windows form (`W. Europe Daylight Time +0200`) is covered by unit
  // tests instead — a fixture should not try to be every input format at once.
  final records = <Map<String, String>>[];
  for (final row in rows) {
    final at = DateTime.parse(row.acqTime);
    final mapped = <String, String>{
      'date': dateCell(at),
      'time': timeCell(at),
      'timezone': 'UTC ${offsetString(at)}',
    };
    for (final entry in row.toMap().entries) {
      if (entry.key == 'acq_time') continue;
      mapped[rename[entry.key] ?? entry.key] = entry.value;
    }
    records.add(mapped);
  }
  return writeTsvRecords(legacyColumns, records);
}

void main() {
  final rows = _rows();
  const dir = 'test/fixtures';
  const stem = 'sub-01_ses-20260203_task-programming_run-01';

  File('$dir/${stem}_beh.tsv').writeAsStringSync(serializeSessionTsv(rows));
  File(
    '$dir/legacy_0.4_${stem}_events.tsv',
  ).writeAsStringSync(_legacyDocument(rows).replaceAll('\tn/a', '\tNaN'));

  // Print the arithmetic the tests pin, so a change here shows its consequences
  // immediately rather than as a test failure with no context.
  stdout.writeln('${rows.length} rows, ${sessionColumns.length} columns');
  final byBlock = <String, List<double>>{};
  for (final r in rows.where((r) => r.isInitial.trim() != '1')) {
    (byBlock[r.blockId] ??= []).add(double.parse(r.scaleValue));
  }
  for (final block in byBlock.keys) {
    final v = byBlock[block]!;
    final index = 1 - (v.reduce((a, b) => a + b) / v.length) / 10;
    stdout.writeln('  block $block  index ${index.toStringAsFixed(3)}');
  }
}
