import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/schema_columns.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards against Python<->Dart drift: the Dart column lists MUST equal the
/// generated contract in schema/tsv_schema.json (the desktop app is the source
/// of truth). Run from the `app/` dir with `flutter test`.
void main() {
  test('Dart column lists match schema/tsv_schema.json', () {
    final file = File('../schema/tsv_schema.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Run `uv run python scripts/generate_schema_json.py` at repo root.',
    );
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    List<String> columnsOf(String key) => ((json[key]
            as Map<String, dynamic>)['columns'] as List)
        .map((c) => (c as Map<String, dynamic>)['name'] as String)
        .toList();

    expect(annotationColumns, columnsOf('annotation_tsv'));
    expect(sessionColumns, columnsOf('session_tsv'));
  });
}
