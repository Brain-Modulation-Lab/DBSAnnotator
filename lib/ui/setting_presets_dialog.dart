import 'package:flutter/material.dart';

import 'stim_params_form.dart' show LimitRange, StimLimits, presetLabel;
import 'theme.dart' show DbsColors;

/// The three stimulation quick-pick lists returned by
/// [showSettingPresetsDialog].
typedef StimPresetLists = ({
  List<num> frequencies,
  List<num> amplitudes,
  List<num> pulseWidths,
});

/// The desktop "Edit Setting Presets" dialog: three tabs — Frequency /
/// Amplitude / Pulse width — each an editable numeric list (add / edit inline /
/// remove). On Save each list is validated against the contract range,
/// de-duplicated and sorted ascending (≥1 required), mirroring
/// `SettingPresetsManager.save_presets`. Returns the edited lists, or null on
/// Cancel.
Future<StimPresetLists?> showSettingPresetsDialog(
  BuildContext context, {
  required StimLimits limits,
  required List<num> frequencies,
  required List<num> amplitudes,
  required List<num> pulseWidths,
}) {
  return showDialog<StimPresetLists>(
    context: context,
    builder: (_) => _SettingPresetsDialog(
      limits: limits,
      frequencies: frequencies,
      amplitudes: amplitudes,
      pulseWidths: pulseWidths,
    ),
  );
}

class _SettingPresetsDialog extends StatefulWidget {
  const _SettingPresetsDialog({
    required this.limits,
    required this.frequencies,
    required this.amplitudes,
    required this.pulseWidths,
  });

  final StimLimits limits;
  final List<num> frequencies;
  final List<num> amplitudes;
  final List<num> pulseWidths;

  @override
  State<_SettingPresetsDialog> createState() => _SettingPresetsDialogState();
}

class _SettingPresetsDialogState extends State<_SettingPresetsDialog> {
  late final List<TextEditingController> _freq = _seed(widget.frequencies);
  late final List<TextEditingController> _amp = _seed(widget.amplitudes);
  late final List<TextEditingController> _pw = _seed(widget.pulseWidths);
  String? _error;

  List<TextEditingController> _seed(List<num> values) =>
      [for (final v in values) TextEditingController(text: presetLabel(v))];

  @override
  void dispose() {
    for (final c in [..._freq, ..._amp, ..._pw]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Parse one tab's fields into a sorted, de-duplicated list; throws a
  /// user-facing message on the first bad / out-of-range value, or when empty.
  List<num> _collect(
      List<TextEditingController> ctrls, LimitRange range, String label) {
    final out = <num>[];
    for (final c in ctrls) {
      final t = c.text.trim();
      if (t.isEmpty) continue;
      final v = num.tryParse(t);
      if (v == null) throw '$label: "$t" is not a number.';
      if (v < range.min || v > range.max) {
        throw '$label: $t is out of range '
            '(${presetLabel(range.min)}–${presetLabel(range.max)}).';
      }
      if (!out.contains(v)) out.add(v);
    }
    if (out.isEmpty) throw 'At least one $label preset is required.';
    out.sort();
    return out;
  }

  void _save() {
    try {
      Navigator.pop(context, (
        frequencies: _collect(_freq, widget.limits.frequency, 'Frequency'),
        amplitudes: _collect(_amp, widget.limits.amplitude, 'Amplitude'),
        pulseWidths: _collect(_pw, widget.limits.pulseWidth, 'Pulse width'),
      ));
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: AlertDialog(
        title: const Text('Edit parameter presets'),
        content: SizedBox(
          width: 420,
          height: 440,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Frequency'),
                  Tab(text: 'Amplitude'),
                  Tab(text: 'Pulse width'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _NumberListEditor(ctrls: _freq, unit: 'Hz'),
                    _NumberListEditor(ctrls: _amp, unit: 'mA'),
                    _NumberListEditor(ctrls: _pw, unit: 'µs'),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: const TextStyle(color: DbsColors.invalid)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}

/// One tab: inline-editable numeric rows + an Add button. Mutates the passed
/// [ctrls] list (owned/disposed by the parent dialog).
class _NumberListEditor extends StatefulWidget {
  const _NumberListEditor({required this.ctrls, required this.unit});

  final List<TextEditingController> ctrls;
  final String unit;

  @override
  State<_NumberListEditor> createState() => _NumberListEditorState();
}

class _NumberListEditorState extends State<_NumberListEditor> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: widget.ctrls.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: widget.ctrls[i],
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        isDense: true,
                        suffixText: widget.unit,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Remove',
                    onPressed: () =>
                        setState(() => widget.ctrls.removeAt(i).dispose()),
                  ),
                ],
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                setState(() => widget.ctrls.add(TextEditingController())),
            icon: const Icon(Icons.add),
            label: Text('Add ${widget.unit}'),
          ),
        ),
      ],
    );
  }
}
