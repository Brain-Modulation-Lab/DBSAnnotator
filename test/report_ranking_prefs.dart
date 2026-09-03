/// The scale targets the report builder used to invent.
///
/// `buildSessionReportData` no longer falls back to `defaultScalePrefsFor` when
/// no targets are supplied: for a TSV opened from elsewhere nobody chose a
/// target, and inventing `min` over 0..10 for every scale produced an index,
/// two green bands and a printed "Scale targets" line that all asserted a
/// clinical intent no one expressed.
///
/// So a test that exercises the ranking has to declare what it ranks against.
/// This is exactly the old implicit fallback, made explicit — every session
/// scale, mode `min`, the declared bounds or 0..10 — so every expected number
/// stays the same while the dependency becomes visible.
library;

import 'package:dbs_annotator/core/session/scale_scoring.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/report_data.dart';

/// [buildSessionReportData] with the default targets applied.
SessionReportData rankedReportData(
  List<SessionRow> rows, {
  DateTime? generatedAt,
}) =>
    buildSessionReportData(
      rows: rows,
      generatedAt: generatedAt,
      // Recording rows only, matching what the old fallback did: the baseline
      // block's clinical scales are not session scales and listing them as
      // targets put them in the legend.
      scalePrefs:
          defaultScalePrefsFor(rows.where((r) => coerceInt(r.isInitial) != 1)),
    );
