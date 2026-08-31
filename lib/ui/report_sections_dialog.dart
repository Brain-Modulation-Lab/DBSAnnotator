/// Pick which sections the exported report contains.
///
/// The desktop equivalent offers bare checkbox labels; each row here carries a
/// line describing what the section includes, so the choice can be made without
/// exporting twice to find out.
library;

import 'package:flutter/material.dart';

import '../report/report_sections.dart';

/// Choose sections for an export. Returns the selection, or null if cancelled.
///
/// [onEditTargets], when given, adds a "Scale targets…" action: the desktop
/// keeps the scale-optimisation table inside its export dialog, and the targets
/// are what the ranking in two of these sections is measured against, so this is
/// the moment the user wants to check them.
Future<Set<ReportSection>?> showReportSectionsDialog(
  BuildContext context,
  Set<ReportSection> selected, {
  Future<void> Function()? onEditTargets,
}) =>
    showDialog<Set<ReportSection>>(
      context: context,
      builder: (_) => _ReportSectionsDialog(
          selected: selected, onEditTargets: onEditTargets),
    );

class _ReportSectionsDialog extends StatefulWidget {
  const _ReportSectionsDialog({required this.selected, this.onEditTargets});

  final Set<ReportSection> selected;
  final Future<void> Function()? onEditTargets;

  @override
  State<_ReportSectionsDialog> createState() => _ReportSectionsDialogState();
}

class _ReportSectionsDialogState extends State<_ReportSectionsDialog> {
  late final Set<ReportSection> _on = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Report sections'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in ReportSection.values)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  value: _on.contains(s),
                  title: Text(s.label),
                  subtitle: Text(s.description,
                      style: theme.textTheme.bodySmall),
                  onChanged: (v) => setState(
                      () => v == true ? _on.add(s) : _on.remove(s)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.onEditTargets != null)
          TextButton.icon(
            onPressed: widget.onEditTargets,
            icon: const Icon(Icons.adjust, size: 18),
            label: const Text('Scale targets…'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        // Nothing selected would produce a title page and nothing else, which
        // is never what anyone means.
        FilledButton(
          onPressed: _on.isEmpty ? null : () => Navigator.pop(context, _on),
          child: const Text('Export'),
        ),
      ],
    );
  }
}
