/// Lay a set of recorded TSVs out as a BIDS dataset directory.
///
/// A single file with BIDS entities in its name is not a BIDS dataset. The
/// specification wants a tree — `sub-<label>/ses-<label>/beh/` — with a
/// `dataset_description.json` at its root, a `README`, and a `participants.tsv`
/// naming the subjects. The app records one file at a time, wherever the
/// platform's picker puts it, which is the right behaviour at a bedside; this
/// module is what turns a folder of those into something `bids-validator`
/// accepts.
///
/// Derived documents — the PDF and Word reports — go under `derivatives/`,
/// which is where BIDS puts anything computed from raw data. That is also what
/// retires the invented `task-longitudinal_..._report.pdf` name: a report is
/// not raw data and was never going to have a legal raw-data filename.
library;

import 'dart:convert';

import 'bids.dart';
import 'schema_columns.dart';
import 'tsv.dart';

/// The BIDS version this layout targets.
const String bidsVersion = '1.10.0';

/// One recorded file to place in the dataset.
typedef DatasetEntry = ({
  /// Parsed entities; determines the path and the filename.
  BidsName name,

  /// The TSV document, already serialised.
  String tsv,

  /// Its `_beh.json` sidecar.
  String sidecar,

  /// The instant of the first recorded row, for `scans.tsv`. Empty when the
  /// file has no dated rows.
  String acqTime,
});

/// One file of the dataset: a path relative to the dataset root, and content.
typedef DatasetFile = ({String path, String content});

/// Build every file of a BIDS dataset for [entries].
///
/// Returns paths relative to the dataset root, in a stable order, so a caller
/// can write them to a directory or stream them into a zip without knowing the
/// layout rules.
List<DatasetFile> buildBidsDataset(
  List<DatasetEntry> entries, {
  required String appName,
  required String appVersion,
  required String repoUrl,
  DateTime? generatedAt,
}) {
  final files = <DatasetFile>[
    (
      path: 'dataset_description.json',
      content: _json(<String, dynamic>{
        'Name': 'DBS programming sessions',
        'BIDSVersion': bidsVersion,
        'DatasetType': 'raw',
        'GeneratedBy': [
          {'Name': appName, 'Version': appVersion, 'CodeURL': repoUrl},
        ],
      }),
    ),
    (path: 'README', content: _readme(appName, appVersion, repoUrl)),
  ];

  final subjects = <String>{
    for (final e in entries) BidsName.label(e.name.subject),
  }.toList()
    ..sort();

  files.add((
    path: 'participants.tsv',
    content: writeTsvRecords(
      const ['participant_id'],
      [
        for (final s in subjects) {'participant_id': 'sub-$s'}
      ],
    ),
  ));
  files.add((
    path: 'participants.json',
    content: _json(<String, dynamic>{
      'participant_id': {
        'Description': 'Pseudonymous subject label typed at the bedside. '
            'The dataset holds no other participant-level variables: the app '
            'records no demographics.',
      },
    }),
  ));

  // scans.tsv is per subject+session, so group before emitting.
  final scans = <String, List<DatasetEntry>>{};
  for (final entry in entries) {
    final dir = entry.name.relativeDir;
    files.add((path: '$dir/${entry.name.filename}', content: entry.tsv));
    files.add((
      path: '$dir/${entry.name.sidecarFilename}',
      content: entry.sidecar,
    ));
    final sessionDir = dir.substring(0, dir.lastIndexOf('/'));
    (scans[sessionDir] ??= []).add(entry);
  }

  for (final sessionDir in scans.keys.toList()..sort()) {
    final group = scans[sessionDir]!;
    final first = group.first.name;
    files.add((
      path: '$sessionDir/sub-${BidsName.label(first.subject)}'
          '_ses-${BidsName.label(first.session)}_scans.tsv',
      content: writeTsvRecords(
        const ['filename', 'acq_time'],
        [
          for (final e in group)
            {
              // scans.tsv paths are relative to the subject/session directory.
              'filename': '${BidsName.datatype}/${e.name.filename}',
              'acq_time': e.acqTime,
            },
        ],
      ),
    ));
  }

  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// The `dataset_description.json` for the reports derivative, which needs its
/// own — "derivatives datasets MUST include a dataset_description.json file at
/// the root level".
DatasetFile reportsDerivativeDescription({
  required String appName,
  required String appVersion,
  required String repoUrl,
}) =>
    (
      path: '$reportsDerivativeDir/dataset_description.json',
      content: _json(<String, dynamic>{
        'Name': '$appName reports',
        'BIDSVersion': bidsVersion,
        'DatasetType': 'derivative',
        'GeneratedBy': [
          {'Name': appName, 'Version': appVersion, 'CodeURL': repoUrl},
        ],
      }),
    );

/// Where clinician-readable reports live inside a dataset.
const String reportsDerivativeDir = 'derivatives/dbs-annotator-reports';

String _json(Object? value) =>
    '${const JsonEncoder.withIndent('  ').convert(value)}\n';

String _readme(String appName, String appVersion, String repoUrl) => '''
# DBS programming sessions

Recorded with $appName $appVersion ($repoUrl).

Each file under `sub-*/ses-*/${BidsName.datatype}/` is one deep brain
stimulation programming session, in long form: one row per (block, scale),
where a block is one stimulation configuration that was tried and rated. The
accompanying `.json` sidecar documents every column, including the contact
grammar used by the anode/cathode cells and the current-split notation used by
the amplitude cells.

`_beh.tsv` rather than `_events.tsv` because these files carry no `onset` or
`duration` column and accompany no recording, which is the case the
specification points at `_beh.tsv` for.

Reports generated from this data are under `$reportsDerivativeDir/`.

## Columns

Programming sessions (`task-programming`): ${sessionColumns.join(', ')}.

Annotations (`task-notes`): ${annotationColumns.join(', ')}.

## Provenance

No demographics, identifiers or free-text beyond the clinical notes typed
during the session are recorded. Subject labels are whatever was typed at the
bedside; check them before sharing.
''';
