import 'package:flutter/material.dart';

/// Per-cathode amplitude split — tablet port of `ui/amplitude_split_widget.py`.
///
/// Shown only when >= 2 cathodes are active. Each cathode gets an editable
/// percentage; the LAST row is the auto-computed remainder so the values always
/// sum to 100 (mirrors the desktop's rebalance). The current percentages
/// (aligned to [cathodes]) are reported via [onChanged]; the parent serializes
/// them with `encodeAmplitude(total, percentages)` at insert.
class AmplitudeSplit extends StatefulWidget {
  const AmplitudeSplit({
    super.key,
    required this.cathodes,
    required this.total,
    required this.decimals,
    required this.onChanged,
  });

  final List<String> cathodes;
  final double total;
  final int decimals;
  final ValueChanged<List<double>> onChanged;

  @override
  State<AmplitudeSplit> createState() => _AmplitudeSplitState();
}

class _AmplitudeSplitState extends State<AmplitudeSplit> {
  late List<double> _pct;
  late List<TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    _reset();
    _notifyLater();
  }

  @override
  void didUpdateWidget(AmplitudeSplit old) {
    super.didUpdateWidget(old);
    if (!_sameCathodes(old.cathodes, widget.cathodes)) {
      for (final c in _ctrls) {
        c.dispose();
      }
      _reset();
      _notifyLater();
    } else if (old.total != widget.total) {
      setState(() {}); // recompute the mA labels
    }
  }

  bool _sameCathodes(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _reset() {
    final n = widget.cathodes.length;
    _pct = List<double>.filled(n, n == 0 ? 0 : 100 / n);
    _ctrls = [
      for (var i = 0; i < n; i++) TextEditingController(text: _fmtPct(_pct[i])),
    ];
  }

  /// Report the current split after the frame (avoids setState-in-build when
  /// this fires from initState/didUpdateWidget).
  void _notifyLater() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChanged(List<double>.of(_pct));
      });

  String _fmtPct(double v) {
    var s = v.toStringAsFixed(1);
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    return s;
  }

  /// Row [i] edited to [text]: clamp 0..100; if the earlier rows would exceed
  /// 100, scale the non-edited ones down; the last row takes the remainder.
  void _edit(int i, String text) {
    final n = _pct.length;
    _pct[i] = (double.tryParse(text.trim()) ?? 0).clamp(0.0, 100.0).toDouble();
    if (i != n - 1) {
      var head = 0.0;
      for (var k = 0; k < n - 1; k++) {
        head += _pct[k];
      }
      if (head > 100) {
        final slack = head - _pct[i];
        final target = (100 - _pct[i]).clamp(0.0, 100.0);
        final scale = slack == 0 ? 0.0 : target / slack;
        for (var k = 0; k < n - 1; k++) {
          if (k != i) _pct[k] = _pct[k] * scale;
        }
      }
      var sumHead = 0.0;
      for (var k = 0; k < n - 1; k++) {
        sumHead += _pct[k];
      }
      _pct[n - 1] = (100 - sumHead).clamp(0.0, 100.0).toDouble();
    }
    for (var k = 0; k < n; k++) {
      if (k != i) _ctrls[k].text = _fmtPct(_pct[k]);
    }
    setState(() {});
    widget.onChanged(List<double>.of(_pct));
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
    if (widget.cathodes.length < 2) return const SizedBox.shrink();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final last = widget.cathodes.length - 1;
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Amplitude split',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: muted)),
          for (var i = 0; i < widget.cathodes.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(widget.cathodes[i],
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _ctrls[i],
                      // The last row is the read-only remainder.
                      enabled: i != last,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.right,
                      decoration:
                          const InputDecoration(isDense: true, suffixText: '%'),
                      onChanged: (t) => _edit(i, t),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '→ ${(widget.total * _pct[i] / 100).toStringAsFixed(widget.decimals)} mA',
                    style: TextStyle(color: muted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
