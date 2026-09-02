import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/schema_columns.dart';
import 'package:flutter_test/flutter_test.dart';

/// The TSV column contract, asserted two ways.
///
/// `schema/*.json` is this project's machine-readable contract. The docs render
/// their column tables from it (docs/_ext/generated_includes.py) and the app
/// bundles a copy under `assets/schema/`, because Flutter can only bundle
/// assets that live inside the project directory. Both copies are committed so
/// that a fresh clone builds with nothing generated first — which also means
/// nothing stops someone editing one and forgetting the other.
///
/// That is what the second test is for. Without it a changed column would ship
/// documentation describing a contract the app does not implement, with no
/// error anywhere.
///
/// Run `flutter test` from the repo root.
void main() {
  test('Dart column lists match the contract', () {
    final file = File('assets/schema/tsv_schema.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'assets/schema/*.json is a committed contract; restore it from git.',
    );
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    List<String> columnsOf(String key) => ((json[key]
            as Map<String, dynamic>)['columns'] as List)
        .map((c) => (c as Map<String, dynamic>)['name'] as String)
        .toList();

    expect(annotationColumns, columnsOf('annotation_tsv'));
    expect(sessionColumns, columnsOf('session_tsv'));
  });

  test('the bundled contract is identical to the canonical one', () {
    for (final name in const <String>[
      'tsv_schema',
      'electrode_models',
      'limits',
      'scale_presets',
    ]) {
      final root = File('schema/$name.json');
      final bundled = File('assets/schema/$name.json');
      expect(root.existsSync(), isTrue,
          reason: 'schema/$name.json is committed; restore it from git.');
      expect(bundled.existsSync(), isTrue,
          reason: 'assets/schema/$name.json is committed; restore it from git.');
      // Compared as a bool rather than as two strings so a failure reads as the
      // instruction below instead of a diff of several thousand JSON lines.
      expect(
        bundled.readAsStringSync() == root.readAsStringSync(),
        isTrue,
        reason: 'assets/schema/$name.json has drifted from schema/$name.json. '
            'The root copy is canonical: copy it over the bundled one.',
      );
    }
  });
}
