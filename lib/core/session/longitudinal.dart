/// Longitudinal-review aggregation over programming-session rows.
///
/// Mirrors dbs_annotator/utils/longitudinal_exporter.py
/// (_collect_session_scale_data and the newline-splitting used by the
/// merged views) and the patient-ID checks in
/// views/longitudinal_report_view.py.
library;

import 'session_row.dart';

/// A (name, value) pair extracted from a row's scale cells.
typedef ScalePair = ({String name, String value});

/// True if a scale_value cell means "not scored" and must be skipped.
///
/// Accepts every spelling that has ever meant "not scored": blank, BIDS' `n/a`
/// (written from v0.5.0), the literal `NaN` any case (written by 0.4.x and the
/// Qt desktop app for a deactivated Step-3 scale), and pandas' `<NA>`.
bool isScaleValueOmitted(String value) {
  final s = value.trim();
  if (s.isEmpty) return true;
  final lowered = s.toLowerCase();
  return lowered == 'nan' || lowered == '<na>' || lowered == 'n/a';
}

/// Split a row's newline-separated scale_name/scale_value cells into pairs.
///
/// Mirrors the desktop's splitting (longitudinal_exporter.py, sessions
/// overview): blank lines are dropped from BOTH cells, then the value list
/// is padded with '' up to the name count and zipped name-by-name. Extra
/// value lines beyond the name count are ignored.
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

/// Coerce a TSV cell to a number the way `pd.to_numeric(errors="coerce")
/// .fillna(0)` does: unparsable/NaN cells become 0.
int _coerceInt(String raw) {
  final v = double.tryParse(raw.trim());
  if (v == null || !v.isFinite) return 0;
  return v.truncate();
}

/// Per-scale timeline: scale name -> {block_id -> numeric value}.
///
/// Mirrors _collect_session_scale_data over a single file: only session
/// rows (is_initial coerced != 1; blanks/junk coerce to 0 like pandas'
/// fillna(0)) are used, rows are grouped by coerced block_id, and
/// non-numeric/omitted values are skipped. When one block holds several
/// values for the same scale, the last one wins (Python: "keep last").
///
/// Session TSVs carry no laterality column — the L/R distinction in the
/// desktop exporter only exists in its derived lateral table, where every
/// entry is duplicated into an L and an R row sharing the same scales, so
/// its "L rows only" filter is equivalent to grouping the raw rows by
/// block_id as done here.
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

/// Extract the patient ID from a BIDS-like filename via `sub-([^_]+)`,
/// applied to the basename (mirrors _extract_patient_id; same regex as
/// BidsName.parse in ../bids.dart). Returns '' when absent.
String extractPatientId(String filename) {
  final basename = filename.split(RegExp(r'[\\/]')).last;
  return RegExp(r'sub-([^_]+)').firstMatch(basename)?.group(1) ?? '';
}

/// True if all filenames that carry a patient ID agree on it (mirrors
/// _validate_patient_ids: files without a sub- entity are ignored, and
/// fewer than two identified files always match).
bool patientIdsMatch(List<String> filenames) {
  final ids =
      filenames.map(extractPatientId).where((id) => id.isNotEmpty).toSet();
  return ids.length <= 1;
}
