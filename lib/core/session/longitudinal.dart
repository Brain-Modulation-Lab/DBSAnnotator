/// Longitudinal-review aggregation over programming-session rows, mirroring
/// dbs_annotator/utils/longitudinal_exporter.py.
library;

import 'session_row.dart';

typedef ScalePair = ({String name, String value});

/// True if a scale_value cell means "not scored": blank, BIDS' `n/a`, `NaN` in
/// any case (the desktop's deactivated Step-3 scale) or pandas' `<NA>`.
bool isScaleValueOmitted(String value) {
  final s = value.trim();
  if (s.isEmpty) return true;
  final lowered = s.toLowerCase();
  return lowered == 'nan' || lowered == '<na>' || lowered == 'n/a';
}

/// Split a row's newline-separated scale cells into pairs: blank lines go from
/// both cells, then values are padded to the name count and zipped.
List<ScalePair> splitScalePairs(String scaleName, String scaleValue) {
  List<String> lines(String cell) =>
      cell.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  final names = lines(scaleName);
  final values = lines(scaleValue);
  while (values.length < names.length) {
    values.add('');
  }
  return [
    for (var i = 0; i < names.length; i++) (name: names[i], value: values[i]),
  ];
}

/// A TSV cell as `pd.to_numeric(errors="coerce").fillna(0)` reads it.
int _coerceInt(String raw) {
  final v = double.tryParse(raw.trim());
  if (v == null || !v.isFinite) return 0;
  return v.truncate();
}

/// Per-scale timeline: scale name -> {block_id -> numeric value}, over session
/// rows only (`is_initial` coerced != 1), skipping omitted and non-numeric
/// values; the last value wins when one block repeats a scale. There is no
/// laterality column to filter on, as the desktop's derived lateral table has.
Map<String, Map<int, double>> scaleTimeline(List<SessionRow> rows) {
  final timeline = <String, Map<int, double>>{};
  for (final row in rows) {
    if (_coerceInt(row.isInitial) == 1) continue;
    final blockId = _coerceInt(row.blockId);
    for (final pair in splitScalePairs(row.scaleName, row.scaleValue)) {
      if (isScaleValueOmitted(pair.value)) continue;
      final value = double.tryParse(pair.value.trim());
      if (value == null || value.isNaN) continue;
      (timeline[pair.name] ??= <int, double>{})[blockId] = value;
    }
  }
  return timeline;
}

/// The `sub-` label in a filename's basename, or '' when it carries none.
String extractPatientId(String filename) {
  final basename = filename.split(RegExp(r'[\\/]')).last;
  return RegExp(r'sub-([^_]+)').firstMatch(basename)?.group(1) ?? '';
}

/// True if every filename carrying a patient ID agrees on it; others ignored.
bool patientIdsMatch(List<String> filenames) {
  final ids = filenames
      .map(extractPatientId)
      .where((id) => id.isNotEmpty)
      .toSet();
  return ids.length <= 1;
}
