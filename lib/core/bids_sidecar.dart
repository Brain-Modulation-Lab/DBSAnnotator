/// The `_beh.json` sidecar that documents a TSV's columns.
///
/// ## Why this is not optional in practice
///
/// Of the 22 columns in a programming-session file, only `notes` resembles
/// anything BIDS defines. The rest — `block_id`, `left_cathode`,
/// `left_amplitude` and the contact grammar they use — mean nothing to a reader
/// who did not write them, and the specification's answer to that is the
/// sidecar: "any additional columns in a TSV file SHOULD be documented in an
/// accompanying JSON sidecar file". Without one, `left_amplitude` = `3.3_2.2` is
/// an unexplained string; with one, it is a documented current split.
///
/// The descriptions come from `schema/tsv_schema.json`, which already feeds the
/// column tables in the documentation, so the sidecar cannot drift from either.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Loads the TSV contract from the bundled asset at runtime.
///
/// The repo-root `schema/*.json` files are mirrored into `assets/schema/`
/// (test/schema_parity_test.dart enforces byte identity), same as
/// `loadElectrodeCatalog` and `loadScalePresets`. Tests read the repo-root file
/// directly via `dart:io` instead.
Future<Map<String, dynamic>> loadTsvContract() async {
  final raw = await rootBundle.loadString('assets/schema/tsv_schema.json');
  return jsonDecode(raw) as Map<String, dynamic>;
}

/// A column's entry in the sidecar, as BIDS names the keys.
Map<String, String> _entry(Map<String, dynamic> column) {
  final description = (column['description'] as String? ?? '')
      // The descriptions carry reStructuredText inline literals because the
      // docs render them; JSON readers should see plain text.
      .replaceAll('``', '');
  final out = <String, String>{
    'LongName': _longName(column['name'] as String),
    'Description': description,
  };
  final units = column['units'] as String?;
  if (units != null) out['Units'] = units;
  return out;
}

/// `left_stim_freq` -> `Left stim freq`. A readable expansion beats leaving
/// LongName out, and beats hand-maintaining a second table of prose.
String _longName(String column) {
  final words = column.split('_');
  if (words.isEmpty) return column;
  final first = words.first;
  return [
    first.isEmpty ? first : first[0].toUpperCase() + first.substring(1),
    ...words.skip(1),
  ].join(' ');
}

/// Build the sidecar object for one of the two TSV kinds.
///
/// [contract] is the parsed `tsv_schema.json`; [kind] is `session_tsv` or
/// `annotation_tsv`.
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

/// The sidecar for the combined table, pretty-printed.
///
/// Composed from two contract sections rather than one: `aggregate_tsv` declares
/// only the four identity columns, because the other 19 are the session columns
/// carried through unchanged and describing them twice would let the two copies
/// drift. The key order matches the table's header.
///
/// [computedAcqTime] adds a note to `acq_time` recording that the value may be
/// *derived* rather than recorded — true for any row that came from a
/// pre-0.5.0 file, where `SessionRow.fromMap` composed it from `date` + `time` +
/// `timezone`. A reader of a derivative cannot otherwise know that, and for a
/// timestamp in a clinical dataset the difference matters.
String aggregateSidecarJson(
  Map<String, dynamic> contract, {
  required String appVersion,
  bool computedAcqTime = true,
}) {
  final keys = buildSidecar(contract, 'aggregate_tsv', appVersion: appVersion);
  final session = buildSidecar(contract, 'session_tsv', appVersion: appVersion);
  // `buildSidecar` puts the three document-level fields first; take them from
  // the keys map and then the two column sets in header order.
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

/// The columns [kind] declares, in order — the same list the Dart constants
/// hold, read back out of the contract so a caller can check they agree.
List<String> contractColumns(Map<String, dynamic> contract, String kind) =>
    ((contract[kind] as Map<String, dynamic>)['columns'] as List)
        .cast<Map<String, dynamic>>()
        .map((c) => c['name'] as String)
        .toList();
