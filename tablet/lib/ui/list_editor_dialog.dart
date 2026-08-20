import 'package:flutter/material.dart';

/// Generic add / remove / edit dialog for a list of short strings — program
/// names, stim preset values (numeric), or scale names. Returns the edited
/// list (blanks dropped) on Save, or null on Cancel.
class ListEditorDialog extends StatefulWidget {
  const ListEditorDialog({
    super.key,
    required this.title,
    required this.items,
    this.hint,
    this.numeric = false,
  });

  final String title;
  final List<String> items;
  final String? hint;
  final bool numeric;

  @override
  State<ListEditorDialog> createState() => _ListEditorDialogState();
}

class _ListEditorDialogState extends State<ListEditorDialog> {
  late final List<TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = [for (final s in widget.items) TextEditingController(text: s)];
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _ctrls.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrls[i],
                          keyboardType: widget.numeric
                              ? const TextInputType.numberWithOptions(
                                  decimal: true)
                              : null,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: widget.hint,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        tooltip: 'Remove',
                        onPressed: () =>
                            setState(() => _ctrls.removeAt(i).dispose()),
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
                    setState(() => _ctrls.add(TextEditingController())),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final out = [
              for (final c in _ctrls)
                if (c.text.trim().isNotEmpty) c.text.trim(),
            ];
            Navigator.pop(context, out);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
