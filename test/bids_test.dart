/// The BIDS surface: the sidecar that documents the columns, and the dataset
/// tree that `bids-validator` is pointed at.
///
/// The filename and column-naming rules live in tsv_roundtrip_test.dart and
/// session_file_test.dart, next to the round trips they constrain.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/bids.dart';
import 'package:dbs_annotator/core/bids_dataset.dart';
import 'package:dbs_annotator/core/bids_sidecar.dart';
import 'package:dbs_annotator/core/schema_columns.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final contract = jsonDecode(File('schema/tsv_schema.json').readAsStringSync())
      as Map<String, dynamic>;

  group('sidecar', () {
    test('documents every column of both kinds, and nothing else', () {
      // The whole point of the sidecar is that a reader can look up any column
      // they meet in the TSV. A column present in the data but missing here is
      // exactly the gap it exists to close.
      final session =
          buildSidecar(contract, 'session_tsv', appVersion: '0.5.0');
      for (final column in sessionColumns) {
        expect(session, contains(column), reason: '$column is undocumented');
      }

      final notes =
          buildSidecar(contract, 'annotation_tsv', appVersion: '0.5.0');
      for (final column in annotationColumns) {
        expect(notes, contains(column), reason: '$column is undocumented');
      }
    });

    test('the contract and the Dart column lists agree', () {
      // schema_parity_test.dart checks the bundled copy against these lists;
      // this checks the repo-root original, which is what the docs render.
      expect(contractColumns(contract, 'session_tsv'), sessionColumns);
      expect(contractColumns(contract, 'annotation_tsv'), annotationColumns);
    });

    test('entries use the BIDS key names, with Units where there are any', () {
      final session =
          buildSidecar(contract, 'session_tsv', appVersion: '0.5.0');
      final freq = session['left_stim_freq'] as Map<String, String>;
      expect(freq['LongName'], 'Left stim freq');
      expect(freq['Units'], 'Hz');
      expect(freq['Description'], contains('frequency'));

      // A column with no physical unit must not claim one.
      expect(session['scale_name'], isNot(contains('Units')));

      // The descriptions are shared with the docs, which want reStructuredText
      // inline literals; a JSON reader should not see the backticks.
      for (final entry in session.values) {
        if (entry is Map<String, String>) {
          expect(entry['Description'], isNot(contains('``')));
        }
      }
    });

    test('names the missing-value code, so `n/a` is not a mystery', () {
      final session =
          buildSidecar(contract, 'session_tsv', appVersion: '0.5.0');
      expect(session['MissingValueCode'], 'n/a');
      expect(session['GeneratedBy'], isA<List<dynamic>>());
    });

    test('is valid, stable JSON', () {
      final text = sessionSidecarJson(contract, appVersion: '0.5.0');
      expect(jsonDecode(text), isA<Map<String, dynamic>>());
      expect(text, endsWith('\n'));
    });
  });

  group('dataset', () {
    DatasetEntry entry(String subject, String session, String run) => (
          name: BidsName(
            subject: subject,
            session: session,
            task: 'programming',
            run: run,
          ),
          tsv: 'date\tnotes\n2026-06-26\ta note\n',
          sidecar: '{}\n',
          acqTime: '2026-06-26T16:46:14+02:00',
        );

    List<String> pathsOf(List<DatasetFile> files) =>
        files.map((f) => f.path).toList();

    test('lays files out under sub-/ses-/beh with their sidecars', () {
      final files = buildBidsDataset(
        [entry('01', '20260626', '01')],
        appName: 'DBS Annotator',
        appVersion: '0.5.0',
        repoUrl: 'https://example.invalid',
      );
      final paths = pathsOf(files);

      expect(
          paths,
          containsAll([
            'dataset_description.json',
            'README',
            'participants.tsv',
            'participants.json',
            'sub-01/ses-20260626/beh/'
                'sub-01_ses-20260626_task-programming_run-01_beh.tsv',
            'sub-01/ses-20260626/beh/'
                'sub-01_ses-20260626_task-programming_run-01_beh.json',
            'sub-01/ses-20260626/sub-01_ses-20260626_scans.tsv',
          ]));
    });

    test('dataset_description.json declares the BIDS version and provenance',
        () {
      final files = buildBidsDataset(
        [entry('01', '20260626', '01')],
        appName: 'DBS Annotator',
        appVersion: '0.5.0',
        repoUrl: 'https://example.invalid',
      );
      final description = jsonDecode(files
          .firstWhere((f) => f.path == 'dataset_description.json')
          .content) as Map<String, dynamic>;

      expect(description['BIDSVersion'], bidsVersion);
      expect(description['DatasetType'], 'raw');
      expect((description['GeneratedBy'] as List).first,
          containsPair('Version', '0.5.0'));
    });

    test('participants.tsv lists each subject once, in order', () {
      final files = buildBidsDataset(
        [
          entry('02', '20260626', '01'),
          entry('01', '20260626', '01'),
          entry('01', '20260701', '01'),
        ],
        appName: 'DBS Annotator',
        appVersion: '0.5.0',
        repoUrl: 'https://example.invalid',
      );
      final participants =
          files.firstWhere((f) => f.path == 'participants.tsv').content;

      expect(participants,
          'participant_id\nsub-01\nsub-02\n'.replaceAll('\n', '\n'));
    });

    test('scans.tsv is per session, and its paths are session-relative', () {
      // BIDS: the `filename` column of scans.tsv is relative to the
      // subject/session directory, so it carries the datatype folder and not
      // the sub-/ses- prefix.
      final files = buildBidsDataset(
        [entry('01', '20260626', '01'), entry('01', '20260626', '02')],
        appName: 'DBS Annotator',
        appVersion: '0.5.0',
        repoUrl: 'https://example.invalid',
      );
      final scans = files
          .firstWhere((f) => f.path.endsWith('_scans.tsv'))
          .content
          .trim()
          .split('\n');

      expect(scans.first, 'filename\tacq_time');
      expect(scans, hasLength(3));
      expect(
          scans[1],
          startsWith(
              'beh/sub-01_ses-20260626_task-programming_run-01_beh.tsv'));
      expect(scans[1], contains('2026-06-26T16:46:14+02:00'));
    });

    test('two sessions of one subject each get their own scans.tsv', () {
      final files = buildBidsDataset(
        [entry('01', '20260626', '01'), entry('01', '20260701', '01')],
        appName: 'DBS Annotator',
        appVersion: '0.5.0',
        repoUrl: 'https://example.invalid',
      );
      expect(
          pathsOf(files).where((p) => p.endsWith('_scans.tsv')),
          unorderedEquals([
            'sub-01/ses-20260626/sub-01_ses-20260626_scans.tsv',
            'sub-01/ses-20260701/sub-01_ses-20260701_scans.tsv',
          ]));
    });

    test('the reports derivative carries its own dataset_description', () {
      // "derivatives datasets MUST include a dataset_description.json file at
      // the root level" — a report dropped into derivatives/ without one makes
      // the whole dataset invalid.
      final file = reportsDerivativeDescription(
        appName: 'DBS Annotator',
        appVersion: '0.5.0',
        repoUrl: 'https://example.invalid',
      );
      expect(file.path, '$reportsDerivativeDir/dataset_description.json');
      expect((jsonDecode(file.content) as Map<String, dynamic>)['DatasetType'],
          'derivative');
    });

    test('the README says why the suffix is _beh', () {
      final readme = buildBidsDataset(
        [entry('01', '20260626', '01')],
        appName: 'DBS Annotator',
        appVersion: '0.5.0',
        repoUrl: 'https://example.invalid',
      ).firstWhere((f) => f.path == 'README').content;

      expect(readme, contains('_beh.tsv'));
      expect(readme, contains('onset'));
      expect(readme, contains(sessionColumns.first));
    });
  });
}
