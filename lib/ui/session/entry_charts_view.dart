/// The four stacked panels reviewing what has been inserted: session scales,
/// amplitude, pulse width and frequency, sharing one horizontally scrollable
/// x axis.
///
/// ## Why there is no Scrollable here
///
/// The panels must stay in x-alignment: reading a dip in a scale against the
/// amplitude that caused it is the entire point. Four `SingleChildScrollView`s
/// with synchronised `ScrollController`s can drift (each runs its own physics
/// simulation, and one `jumpTo` per frame per panel fights them), so instead a
/// single [_offset] in state feeds every panel's painter. Alignment then holds
/// by construction rather than by keeping four controllers in step.
///
/// Panning is handled explicitly: a horizontal drag on the plot area, plus mouse
/// wheel and trackpad via `PointerSignalEvent`. Reordering uses **explicit drag
/// handles**, so a horizontal pan and a vertical reorder can never contend for
/// the same gesture.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';

import '../../report/entry_charts.dart';
import '../chart_primitives.dart';

/// Width of the fixed left gutter. It holds only the y tick labels: the title
/// and the series key live in a full-width header above each panel, because a
/// narrow scrolling gutter silently hid every series past the third — which
/// read as "the legend does not update when I add more scales".
const double _gutterWidth = 52;

/// Height of one panel's plot area.
const double _panelHeight = 116;

/// Height of the shared x-axis strip under the last panel.
const double _axisHeight = 30;

/// Vertical inset inside a plot, so markers do not touch the frame.
const double _plotPadY = 8;

/// How many configurations fill the viewport by default, and the zoom bounds.
const int kDefaultVisibleConfigs = 10;
const int _minVisible = 3;
const int _maxVisible = 60;

class EntryChartsView extends StatefulWidget {
  const EntryChartsView({
    super.key,
    required this.data,
    this.order,
    this.onOrderChanged,
    this.visibleConfigs = kDefaultVisibleConfigs,
    this.onVisibleConfigsChanged,
    this.bestX,
    this.secondX,
  });

  final EntryChartData data;

  /// Persisted panel order by id; null uses the default order.
  final List<String>? order;
  final ValueChanged<List<String>>? onOrderChanged;

  /// How many configurations fill the viewport (the zoom level), persisted.
  final int visibleConfigs;
  final ValueChanged<int>? onVisibleConfigsChanged;

  /// Blocks to mark with a green band, from the report's ranking.
  final int? bestX;
  final int? secondX;

  @override
  State<EntryChartsView> createState() => _EntryChartsViewState();
}

class _EntryChartsViewState extends State<EntryChartsView> {
  /// Horizontal pan, in pixels from the left edge of the content.
  ///
  /// Starts at infinity, which the first layout clamps to the right-hand end:
  /// the default view is the LAST configurations, which is both what the user
  /// asked for and where the newest data — and the best/second-best bands — are.
  /// Starting at 0 opened a long session on its oldest blocks.
  double _offset = double.infinity;

  /// While true, new configurations keep the view on the most recent ones —
  /// which is what you want during a session. Panning left releases it.
  bool _followLatest = true;

  int _lastXCount = 0;

  @override
  void didUpdateWidget(EntryChartsView old) {
    super.didUpdateWidget(old);
    if (widget.data.xs.length != _lastXCount) {
      _lastXCount = widget.data.xs.length;
      if (_followLatest) _offset = double.infinity; // clamped on next layout
    }
  }

  /// Pixels per configuration.
  ///
  /// Divides by the *smaller* of the zoom window and the number of
  /// configurations actually recorded, so early in a session — when there are
  /// fewer blocks than the window — the panels fill the width instead of
  /// stopping short and looking broken. Once there are more blocks than the
  /// window, this is the zoom level and the figure scrolls.
  double _pxPerStep(double viewport) {
    final window = widget.visibleConfigs.clamp(_minVisible, _maxVisible);
    final steps = math.max(1, math.min(window, widget.data.xs.length));
    return viewport / steps;
  }

  double _contentWidth(double viewport) =>
      math.max(viewport, widget.data.xs.length * _pxPerStep(viewport));

  double _maxOffset(double viewport) =>
      math.max(0, _contentWidth(viewport) - viewport);

  void _pan(double dx, double viewport) {
    setState(() {
      // Clamp BEFORE applying the delta: _offset can be the infinity sentinel
      // for "the end", and infinity - dx is still infinity, which would make
      // the first drag do nothing.
      final max = _maxOffset(viewport);
      _offset = (_offset.clamp(0.0, max) - dx).clamp(0.0, max);
      // Panning back to the right edge re-arms follow-the-latest.
      _followLatest = _offset >= max - 0.5;
    });
  }

  void _zoom(int delta) {
    final next =
        (widget.visibleConfigs + delta).clamp(_minVisible, _maxVisible);
    if (next == widget.visibleConfigs) return;
    widget.onVisibleConfigsChanged?.call(next);
  }

  void _reorderItem(int oldIndex, int newIndex, List<ParamPanel> panels) {
    final ids = panels.map((p) => p.id).toList();
    ids.insert(newIndex, ids.removeAt(oldIndex));
    widget.onOrderChanged?.call(ids);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final panels = orderPanels(widget.data.panels, widget.order);
    final xs = widget.data.xs;

    if (xs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('No configurations inserted yet.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.disabledColor)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = math.max(80.0, constraints.maxWidth - _gutterWidth);
        final pxPerStep = _pxPerStep(viewport);
        // Clamp here rather than in setState: the viewport is only known now,
        // and `didUpdateWidget` parks the offset at infinity to mean "the end".
        final offset = _offset.clamp(0.0, _maxOffset(viewport));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(theme, xs.length, viewport, pxPerStep, offset),
            // Wheel and trackpad pan the whole figure.
            Listener(
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) {
                  final d = e.scrollDelta;
                  _pan(-(d.dx.abs() > d.dy.abs() ? d.dx : d.dy), viewport);
                }
              },
              child: ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                // onReorderItem gives an index already adjusted for the
                // removal, so no manual -1 fixup.
                onReorderItem: (o, n) => _reorderItem(o, n, panels),
                children: [
                  for (var i = 0; i < panels.length; i++)
                    _panelRow(
                        theme, panels[i], i, xs, pxPerStep, offset, viewport),
                ],
              ),
            ),
            // The shared x axis, drawn once under the last panel.
            Row(children: [
              const SizedBox(width: _gutterWidth),
              Expanded(
                child: SizedBox(
                  height: _axisHeight,
                  child: CustomPaint(
                    painter: _XAxisPainter(
                      xs: xs,
                      labels: widget.data.xLabels,
                      pxPerStep: pxPerStep,
                      offset: offset,
                      ink: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ]),
            _scrollbar(theme, viewport, offset),
          ],
        );
      },
    );
  }

  /// A real, draggable scrollbar under the shared axis.
  ///
  /// The figure pans by drag and wheel, but with nothing on screen saying so a
  /// long session just looks truncated. This is the affordance; it also shows at
  /// a glance how much of the session is off-screen. Absent (as a thin spacer)
  /// when everything already fits, so it never implies hidden data.
  Widget _scrollbar(ThemeData theme, double viewport, double offset) {
    final maxOff = _maxOffset(viewport);
    if (maxOff <= 0.5) return const SizedBox(height: 6);
    final thumbWidth =
        (viewport * viewport / _contentWidth(viewport)).clamp(32.0, viewport);
    final travel = math.max(1.0, viewport - thumbWidth);
    return Padding(
      padding: const EdgeInsets.only(left: _gutterWidth, top: 6, bottom: 2),
      child: GestureDetector(
        // Thumb pixels -> content pixels, so the thumb tracks the finger.
        onHorizontalDragUpdate: (d) =>
            _pan(-d.delta.dx * maxOff / travel, viewport),
        child: SizedBox(
          height: 10,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 3,
                height: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Positioned(
                left: (offset / maxOff) * travel,
                top: 0,
                width: thumbWidth,
                height: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, int total, double viewport, double pxPerStep,
      double offset) {
    final first = (offset / pxPerStep).floor() + 1;
    final last = math.min(total, (offset + viewport) / pxPerStep).ceil();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              total <= widget.visibleConfigs
                  ? 'All $total configurations'
                  : 'Configurations $first–$last of $total',
              style: theme.textTheme.bodySmall,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Show fewer configurations (zoom in)',
            onPressed:
                widget.visibleConfigs > _minVisible ? () => _zoom(-2) : null,
            icon: const Icon(Icons.zoom_in),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Show more configurations (zoom out)',
            onPressed:
                widget.visibleConfigs < _maxVisible ? () => _zoom(2) : null,
            icon: const Icon(Icons.zoom_out),
          ),
        ],
      ),
    );
  }

  Widget _panelRow(ThemeData theme, ParamPanel panel, int index, List<int> xs,
      double pxPerStep, double offset, double viewport) {
    final names = panel.series.keys.toList();
    return Container(
      key: ValueKey(panel.id),
      // A clear boundary between panels: without it four stacked plots read as
      // one confusing figure.
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor, width: 1.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: handle, title, and the series key at FULL width so it can
          // never be clipped, however many scales are recorded.
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Tooltip(
                    message: 'Drag to reorder',
                    child: Icon(Icons.drag_indicator,
                        size: 16, color: theme.disabledColor),
                  ),
                ),
                const SizedBox(width: 2),
                Text(panel.title,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    children: [
                      for (var i = 0; i < names.length; i++)
                        _SeriesKey(
                          // "Left (= Right)" when the two are numerically
                          // identical: one line hides under the other, and the
                          // reader otherwise cannot tell whether both sides are
                          // plotted or one is missing.
                          name: panel.coincident.contains(names[i])
                              ? '${names[i]} (identical)'
                              : names[i],
                          color: seriesColor(i),
                          dash: seriesDash(i),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (panel.constantLabel != null)
            // An unchanged parameter gets a sentence, not a third of the
            // figure. Plotted, it was a flat line dead-centre of a padded axis
            // (89-91 for a constant 90), which reads as a measured mid-range
            // value, and with both sides identical the Left series was hidden
            // exactly under the Right with nothing saying so.
            Padding(
              padding: const EdgeInsets.only(left: _gutterWidth, bottom: 8),
              child: Text(panel.constantLabel!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            )
          else
            Row(
              children: [
                SizedBox(
                  width: _gutterWidth,
                  height: _panelHeight,
                  child: _YGutter(panel: panel, theme: theme),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) => _pan(d.delta.dx, viewport),
                    child: SizedBox(
                      height: _panelHeight,
                      child: CustomPaint(
                        painter: _PanelPainter(
                          panel: panel,
                          xs: xs,
                          pxPerStep: pxPerStep,
                          offset: offset,
                          bestX: widget.bestX,
                          secondX: widget.secondX,
                          ink: theme.colorScheme.onSurfaceVariant,
                          grid: theme.dividerColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// One legend entry: a short line in the series colour and dash, plus its name.
class _SeriesKey extends StatelessWidget {
  const _SeriesKey({required this.name, required this.color, this.dash});

  final String name;
  final Color color;
  final List<double>? dash;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 8,
            child: CustomPaint(
              painter: _KeyLinePainter(color: color, dash: dash),
            ),
          ),
          const SizedBox(width: 4),
          Text(name, style: const TextStyle(fontSize: 11)),
        ],
      );
}

class _KeyLinePainter extends CustomPainter {
  const _KeyLinePainter({required this.color, this.dash});

  final Color color;
  final List<double>? dash;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final line = Path()
      ..moveTo(0, y)
      ..lineTo(size.width, y);
    canvas
      ..drawPath(
        dash == null ? line : dashPath(line, dash!),
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      )
      ..drawCircle(Offset(size.width / 2, y), 2.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_KeyLinePainter old) =>
      old.color != color || old.dash != dash;
}

/// Fixed left cell: the y range, aligned with the plot's own vertical padding.
class _YGutter extends StatelessWidget {
  const _YGutter({required this.panel, required this.theme});

  final ParamPanel panel;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final mid = (panel.yMin + panel.yMax) / 2;
    return Padding(
      padding: const EdgeInsets.only(
          right: 5, top: _plotPadY - 5, bottom: _plotPadY - 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(tickLabel(panel.yMax), style: theme.textTheme.labelSmall),
          Text(tickLabel(mid), style: theme.textTheme.labelSmall),
          Text(tickLabel(panel.yMin), style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// One panel's plot: bands, grid and series, clipped to the viewport and
/// translated by the shared pan offset.
class _PanelPainter extends CustomPainter {
  const _PanelPainter({
    required this.panel,
    required this.xs,
    required this.pxPerStep,
    required this.offset,
    required this.ink,
    required this.grid,
    this.bestX,
    this.secondX,
  });

  final ParamPanel panel;
  final List<int> xs;
  final double pxPerStep;
  final double offset;
  final Color ink;
  final Color grid;
  final int? bestX;
  final int? secondX;

  @override
  void paint(Canvas canvas, Size size) {
    if (xs.isEmpty || size.width <= 0) return;
    canvas
      ..save()
      ..clipRect(Offset.zero & size);

    double xPos(num i) => (i.toDouble() + 0.5) * pxPerStep - offset;
    final span = math.max(panel.yMax - panel.yMin, 1e-9);
    double yPos(double v) =>
        size.height -
        _plotPadY -
        ((v - panel.yMin) / span) * (size.height - 2 * _plotPadY);

    // Green ranking bands, behind everything.
    void band(int? block, int argb) {
      if (block == null) return;
      final i = xs.indexOf(block);
      if (i < 0) return;
      canvas.drawRect(
        Rect.fromLTRB(xPos(i - 0.42), 0, xPos(i + 0.42), size.height),
        Paint()..color = Color(argb).withValues(alpha: 0.45),
      );
    }

    if (secondX != bestX) band(secondX, 0xFFC8EBCD);
    band(bestX, 0xFF96D2A0);

    // Horizontal guides (top / middle / bottom) and one vertical per config.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.6;
    for (var k = 0; k <= 2; k++) {
      final y = _plotPadY + (size.height - 2 * _plotPadY) * k / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (var i = 0; i < xs.length; i++) {
      final x = xPos(i);
      if (x < -pxPerStep || x > size.width + pxPerStep) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height),
          gridPaint..color = grid.withValues(alpha: 0.5));
    }

    // Series, keyed by index so colour and dash match the gutter key.
    final indexOf = {for (var i = 0; i < xs.length; i++) xs[i]: i};
    var s = 0;
    for (final entry in panel.series.entries) {
      final byIndex = <int, double>{
        for (final e in entry.value.entries)
          if (indexOf[e.key] != null) indexOf[e.key]!: e.value,
      };
      drawSeriesRuns(
        canvas,
        seriesRuns(List.generate(xs.length, (i) => i), byIndex, xPos, yPos),
        color: seriesColor(s),
        dash: seriesDash(s),
        markerRadius: pxPerStep > 26 ? 2.6 : 1.8,
      );
      s++;
    }

    // The two MAIN axes, drawn last and heavier than the guides so the eye can
    // tell the frame of one panel from the guides of the next.
    final axis = Paint()
      ..color = ink
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    // Inset by half the stroke: a line ON the clip edge draws at half width.
    final baseline = size.height - _plotPadY;
    canvas
      ..drawLine(const Offset(1, _plotPadY), Offset(1, baseline), axis)
      ..drawLine(Offset(1, baseline), Offset(size.width, baseline), axis)
      ..restore();
  }

  @override
  bool shouldRepaint(_PanelPainter old) =>
      old.panel != panel ||
      old.xs != xs ||
      old.pxPerStep != pxPerStep ||
      old.offset != offset ||
      old.bestX != bestX ||
      old.secondX != secondX ||
      old.ink != ink ||
      old.grid != grid;
}

/// The shared x axis: a tick per configuration, labelled with its clock time.
class _XAxisPainter extends CustomPainter {
  const _XAxisPainter({
    required this.xs,
    required this.labels,
    required this.pxPerStep,
    required this.offset,
    required this.ink,
  });

  final List<int> xs;
  final Map<int, String> labels;
  final double pxPerStep;
  final double offset;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    if (xs.isEmpty) return;
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    final axis = Paint()
      ..color = ink
      ..strokeWidth = 1.6;
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), axis);

    // Thin out labels when zoomed out so they cannot overlap.
    final every = math.max(1, (46 / pxPerStep).ceil());
    for (var i = 0; i < xs.length; i++) {
      final x = (i + 0.5) * pxPerStep - offset;
      if (x < -20 || x > size.width + 20) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, 3), axis);
      if (i % every != 0) continue;
      final label = labels[xs[i]] ?? '${xs[i]}';
      drawChartText(canvas, label, Offset(x, 5),
          color: ink, align: TextAlign.center, size: 9);
      drawChartText(canvas, '#${xs[i]}', Offset(x, 16),
          color: ink.withValues(alpha: 0.7), align: TextAlign.center, size: 8);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_XAxisPainter old) =>
      old.xs != xs ||
      old.labels != labels ||
      old.pxPerStep != pxPerStep ||
      old.offset != offset ||
      old.ink != ink;
}
