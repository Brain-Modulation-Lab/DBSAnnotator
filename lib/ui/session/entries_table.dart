/// Review table of every inserted TSV row, grouped by block.
///
/// Uses Flutter's `Table` rather than `DataTable` for one reason: `DataTable`
/// cannot draw a per-row border, and the point here is a **heavy rule where one
/// block ends and the next begins**. One row per scale means a single block can
/// span several rows, so without that rule the eye cannot tell where a
/// configuration starts. Each block also gets a faint alternating tint, which
/// does the same job at a glance.
///
/// Extracted from the session screen because the single-session report screen
/// shows exactly the same review.
library;

import 'package:flutter/material.dart';

import '../../core/session/session_row.dart';
import '../../report/report_data.dart' show coerceInt;

/// Thickness of the rule between blocks.
const double _blockRule = 2.4;

/// Distinct blocks in [rows] — what the user counts, rather than TSV rows
/// (one block writes one row per scale, so "rows" reads several times too high).
int blockCount(List<SessionRow> rows) =>
    rows.map((r) => coerceInt(r.blockId)).toSet().length;

class SessionEntriesTable extends StatelessWidget {
  const SessionEntriesTable({super.key, required this.rows});

  final List<SessionRow> rows;

  static const _headers = [
    'Blk',
    'Type',
    'Time',
    'Prog',
    'Scale',
    'Value',
    'L  Hz/mA/µs',
    'R  Hz/mA/µs',
    'Notes',
  ];

  /// Relative column widths; Notes takes the largest share.
  static const _flex = <double>[3, 5, 8, 4, 9, 5, 11, 11, 18];

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text('No entries inserted yet.')),
      );
    }
    final theme = Theme.of(context);
    final rule = theme.dividerColor;
    final tint =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5);

    String triple(String f, String a, String pw) =>
        [f, a, pw].map((s) => s.trim().isEmpty ? '–' : s.trim()).join(' / ');

    // The date belongs to the session, not to a configuration: the baseline row
    // carries it and each recording block shows only its clock time, so the
    // column stops repeating "2026-06-26" once per block. A file with no
    // baseline at all keeps date+time on its first block, so the day is never
    // lost from the table.
    final hasInitial = rows.any((r) => coerceInt(r.isInitial) == 1);
    String stamp(SessionRow r, bool initial, bool isFirstBlock) {
      if (initial) return r.date.trim();
      if (isFirstBlock && !hasInitial) return '${r.date} ${r.time}'.trim();
      return r.time.trim();
    }

    // Walk the rows, tracking where each block starts so the rule can be drawn
    // on the first row of every block after the first.
    final tableRows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border(bottom: BorderSide(color: rule, width: 1.2)),
        ),
        children: [
          for (final h in _headers)
            _cell(h, bold: true, style: theme.textTheme.labelSmall),
        ],
      ),
    ];

    int? previousBlock;
    var blockIndex = -1;
    for (final r in rows) {
      final block = coerceInt(r.blockId);
      final isNewBlock = block != previousBlock;
      if (isNewBlock) {
        previousBlock = block;
        blockIndex++;
      }
      // Everything except Scale and Value is a property of the BLOCK, so it is
      // printed once on the block's first row and left blank on the rest. A
      // 7-block x 5-scale session was otherwise repeating the same timestamp,
      // programme and both sides' parameters 35 times, which buries the two
      // cells that actually differ. Blanking rather than merging keeps every
      // column aligned, so the block's values still read straight down.
      final isInitial = coerceInt(r.isInitial) == 1;
      tableRows.add(TableRow(
        decoration: BoxDecoration(
          color: blockIndex.isOdd ? tint : null,
          border: isNewBlock && tableRows.length > 1
              ? Border(top: BorderSide(color: rule, width: _blockRule))
              : null,
        ),
        children: [
          _cell(isNewBlock ? r.blockId : '', bold: isNewBlock),
          _cell(isNewBlock ? (isInitial ? 'Initial' : 'Rec') : ''),
          _cell(isNewBlock ? stamp(r, isInitial, blockIndex == 0) : ''),
          _cell(isNewBlock ? r.programId : ''),
          _cell(r.scaleName),
          _cell(r.scaleValue),
          _cell(isNewBlock
              ? triple(r.leftStimFreq, r.leftAmplitude, r.leftPulseWidth)
              : ''),
          _cell(isNewBlock
              ? triple(r.rightStimFreq, r.rightAmplitude, r.rightPulseWidth)
              : ''),
          _cell(isNewBlock ? r.notes : '', maxLines: 3),
        ],
      ));
    }

    return Table(
      columnWidths: {
        for (var i = 0; i < _flex.length; i++) i: FlexColumnWidth(_flex[i]),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: tableRows,
    );
  }

  Widget _cell(String text,
      {bool bold = false, TextStyle? style, int maxLines = 2}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: (style ?? const TextStyle(fontSize: 12)).copyWith(
          fontWeight: bold ? FontWeight.w600 : null,
        ),
      ),
    );
  }
}
