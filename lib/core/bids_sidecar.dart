/// The `_beh.json` sidecar that documents a TSV's columns.
///
/// Of a programming-session file's 22 columns only `notes` resembles anything
/// BIDS defines, and the spec's answer is the sidecar: "any additional columns
/// in a TSV file SHOULD be documented in an accompanying JSON sidecar file".
/// Descriptions come from `schema/tsv_schema.json`, which also feeds the docs.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Loads the TSV contract from the bundled `assets/schema/` mirror of the
/// repo-root `schema/*.json`; tests read the repo root via `dart:io`.
Future<Map<String, dynamic>> loadTsvContract() async {
  final raw = await rootBundle.loadString('assets/schema/tsv_schema.json');
  return jsonDecode(raw) as Map<String, dynamic>;
}

Map<String, String> _entry(Map<String, dynamic> column) {
  final description = (column['description'] as String? ?? '')
      // Strip the reStructuredText inline literals the docs render.
      .replaceAll('``', '');
  final out = <String, String>{
    'LongName': _longName(column['name'] as String),
    'Description': description,
  };
  final units = column['units'] as String?;
  if (units != null) out['Units'] = units;
  return out;
}

/// `left_stim_freq` -> `Left stim freq`, so `LongName` needs no second table.
String _longName(String column) {
  final words = column.split('_');
  if (words.isEmpty) return column;
  final first = words.first;
  return [
    first.isEmpty ? first : first[0].toUpperCase() + first.substring(1),
    ...words.skip(1),
  ].join(' ');
}

/// Build the sidecar for one [kind] of TSV: `session_tsv` or `annotation_tsv`.
Map<String, dynamic> buildSidecar(
  Map<String, dynamic> contract,
  String kind, {
  required String appVersion,
}) {
  final columns = ((contract[kind] as Map<String, dynamic>)['columns'] as List)
      .cast<Map<String, dynamic>>();
  final bids = contract['bids'] as Map<String, dynamic>? ?? const {};
  return <String, dynamic>{
    'GeneratedBy': [
      {'Name': 'DBS Annotator', 'Version': appVersion},
    ],
    'SchemaVersion': contract['schema_version'],
    if (bids['na'] != null) 'MissingValueCode': bids['na'],
    for (final column in columns) column['name'] as String: _entry(column),
  };
}

/// The sidecar for a programming-session file, pretty-printed.
String sessionSidecarJson(
  Map<String, dynamic> contract, {
  required String appVersion,
}) => _encode(buildSidecar(contract, 'session_tsv', appVersion: appVersion));

/// The sidecar for an annotations file, pretty-printed.
String annotationSidecarJson(
  Map<String, dynamic> contract, {
  required String appVersion,
}) => _encode(buildSidecar(contract, 'annotation_tsv', appVersion: appVersion));

/// The sidecar for the combined table, pretty-printed, in header key order.
///
/// Composed from two contract sections because `aggregate_tsv` declares only
/// the four identity columns; the other 19 are session columns carried through
/// unchanged. [computedAcqTime] notes on `acq_time` that a row from a legacy
/// file had its timestamp derived rather than recorded.
String aggregateSidecarJson(
  Map<String, dynamic> contract, {
  required String appVersion,
  bool computedAcqTime = true,
}) {
  final keys = buildSidecar(contract, 'aggregate_tsv', appVersion: appVersion);
  final session = buildSidecar(contract, 'session_tsv', appVersion: appVersion);
  // Document-level fields first, then the two column sets in header order.
  const documentLevel = {'GeneratedBy', 'SchemaVersion', 'MissingValueCode'};
  final merged = <String, dynamic>{
    for (final field in documentLevel)
      if (keys.containsKey(field)) field: keys[field],
    for (final entry in keys.entries)
      if (!documentLevel.contains(entry.key)) entry.key: entry.value,
    for (final entry in session.entries)
      if (!documentLevel.contains(entry.key)) entry.key: entry.value,
  };
  if (computedAcqTime && merged['acq_time'] is Map) {
    final acq = Map<String, dynamic>.from(merged['acq_time'] as Map);
    acq['Description'] =
        '${acq['Description']} In this combined table the value may be '
        'COMPUTED rather than recorded: a row from a file written before '
        'v0.5.0 had no acq_time column, and it was composed from that file\'s '
        'date, time and timezone cells when the file was read.';
    merged['acq_time'] = acq;
  }
  return _encode(merged);
}

String _encode(Object? value) =>
    '${const JsonEncoder.withIndent('  ').convert(value)}\n';

/// The columns [kind] declares, in order, as the contract states them.
List<String> contractColumns(Map<String, dynamic> contract, String kind) =>
    ((contract[kind] as Map<String, dynamic>)['columns'] as List)
        .cast<Map<String, dynamic>>()
        .map((c) => c['name'] as String)
        .toList();
