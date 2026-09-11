/// Combine several session TSVs into one long table, for pooled analysis.
///
/// The table prepends `participant_id` (`sub-01`), `session_id`
/// (`ses-20260203`), `run_id` and `source_file` to the session columns, which
/// are carried through unchanged. `participant_id` uses the BIDS spelling and
/// value shape so the table joins onto `participants.tsv` untransformed.
///
/// It belongs under `derivatives/`, not in the raw tree: BIDS raw layout is one
/// file per (subject, session, task, run), which a table spanning sessions
/// contradicts. See `aggregateDerivativeDir` in `lib/core/bids_dataset.dart`.
///
/// A block is unique on `(participant_id, session_id, run_id, block_id)`.
/// `source_file` is a key column rather than a convenience because `run`
/// defaults to `01` and does not auto-increment, so two visits on the same day
/// can share all three entities.
library;

import '../bids.dart';
import '../schema_columns.dart';
import '../tsv.dart';
import 'session_file.dart';
import 'session_row.dart';

/// One file to fold in: its name, and its already-parsed rows.
typedef AggregateSource = ({String filename, List<SessionRow> rows});

/// A file left out, and why.
typedef AggregateSkip = ({String filename, String reason});

/// The combined table and what it is made of.
typedef AggregateResult = ({
  /// The TSV document, or '' when nothing was includable.
  String tsv,

  /// Files that were not folded in, each with a reason.
  List<AggregateSkip> skipped,

  /// Data rows in [tsv] (excluding the header).
  int rowCount,

  /// Distinct `participant_id` values, sorted.
  List<String> subjects,

  /// Files actually folded in.
  int fileCount,
});

/// The identity columns prepended to every row, in order.
const List<String> aggregateKeyColumns = <String>[
  'participant_id',
  'session_id',
  'run_id',
  'source_file',
];

/// The full header: the four keys, then the session columns unchanged.
List<String> aggregateColumns() => <String>[
  ...aggregateKeyColumns,
  ...sessionColumns,
];

/// Fold [sources] into one table.
///
/// Two kinds of file are skipped and named in [AggregateResult.skipped]: one
/// whose name carries no `sub-` or `ses-` entity, since guessing entities would
/// put a wrong subject label on clinical data; and a repeated filename, since
/// duplicate rows double every count derived from the table with nothing on the
/// face of it to show why.
AggregateResult buildAggregate(List<AggregateSource> sources) {
  final skipped = <AggregateSkip>[];
  final seen = <String>{};
  final subjects = <String>{};
  // Index-tagged because Dart's List.sort is not stable, and rows within a
  // block must keep their written order for the output to be reproducible.
  final keyed = <({List<String> key, int seq, Map<String, String> record})>[];
  var fileCount = 0;

  for (final source in sources) {
    if (!seen.add(source.filename)) {
      skipped.add((
        filename: source.filename,
        reason: 'a file with this name is already included',
      ));
      continue;
    }
    final name = BidsName.parse(source.filename);
    if (name == null || BidsName.label(name.session).isEmpty) {
      skipped.add((
        filename: source.filename,
        reason: 'no sub- or ses- entity in the filename',
      ));
      continue;
    }

    final participant = 'sub-${BidsName.label(name.subject)}';
    final session = 'ses-${BidsName.label(name.session)}';
    final run = BidsName.index(name.run);
    subjects.add(participant);
    fileCount++;

    for (final row in source.rows) {
      keyed.add((
        key: [participant, session, run],
        seq: keyed.length,
        record: <String, String>{
          'participant_id': participant,
          'session_id': session,
          'run_id': run,
          'source_file': source.filename,
          ...row.toMap(),
        },
      ));
    }
  }

  // Subject, session, run, block, then written order: the same inputs in any
  // order must give byte-identical output, or the table cannot be diffed.
  keyed.sort((a, b) {
    for (var i = 0; i < a.key.length; i++) {
      final c = a.key[i].compareTo(b.key[i]);
      if (c != 0) return c;
    }
    final byFile = a.record['source_file']!.compareTo(b.record['source_file']!);
    if (byFile != 0) return byFile;
    final byBlock = _asInt(
      a.record['block_id'] ?? '',
    ).compareTo(_asInt(b.record['block_id'] ?? ''));
    if (byBlock != 0) return byBlock;
    return a.seq.compareTo(b.seq);
  });

  final records = [for (final k in keyed) k.record];
  return (
    tsv: records.isEmpty ? '' : writeTsvRecords(aggregateColumns(), records),
    skipped: skipped,
    rowCount: records.length,
    subjects: subjects.toList()..sort(),
    fileCount: fileCount,
  );
}

/// `block_id` as an int for ordering; unparsable cells sort first.
///
/// Tolerant like [nextBlockId], because older files write block indices as `3`
/// or `3.0`.
int _asInt(String raw) {
  final v = double.tryParse(raw.trim());
  return (v == null || !v.isFinite) ? -1 : v.truncate();
}
