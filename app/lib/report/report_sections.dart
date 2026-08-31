/// Which sections a generated report contains — the tablet counterpart of the
/// desktop export dialog's section checkboxes (`export_dialog.py`).
///
/// A pure enum, with no Flutter import, so the builders can be gated in a
/// headless test and the two formats cannot end up honouring different
/// selections.
///
/// Deliberately a FLAT list. The desktop dialog spends ~110 lines keeping a
/// parent checkbox tri-state in sync with its children ("Session data" over
/// "graph" and "table"); a flat list with graph and table as siblings has
/// identical expressive power.
library;

enum ReportSection {
  baseline(
    'Baseline assessment',
    'Pre-session clinical scale scores and the notes taken before '
        'stimulation was changed.',
  ),
  chart(
    'Session scales figure',
    'Every rated scale plotted against configuration, with the aggregate '
        'index and the best / second-best bands.',
  ),
  table(
    'Session data table',
    'One row per configuration and side: contacts, parameters, scale '
        'ratings and notes.',
  ),
  electrodes(
    'Electrode configuration',
    'Rendered lead diagrams for the initial and last recorded settings, '
        'left and right.',
  ),
  summary(
    'Programming summary',
    'Configurations tested, the range of each parameter, and the span of '
        'the annotation.',
  );

  const ReportSection(this.label, this.description);

  /// Checkbox label.
  final String label;

  /// One line saying what the section actually includes, so the choice can be
  /// made without exporting twice to find out.
  final String description;
}

/// Everything on: what an export produces unless the user says otherwise, and
/// what a headless caller gets by default.
const Set<ReportSection> kAllReportSections = {
  ReportSection.baseline,
  ReportSection.chart,
  ReportSection.table,
  ReportSection.electrodes,
  ReportSection.summary,
};
