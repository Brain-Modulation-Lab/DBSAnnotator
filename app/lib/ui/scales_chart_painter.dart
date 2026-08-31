/// The scales-timeline chart, drawn once and embedded in BOTH reports.
///
/// Port of the desktop's matplotlib chart
/// (`src/dbs_annotator/utils/report_chart_utils.py::build_scales_chart`), which
/// the Qt app renders to a PNG and inserts into its DOCX (and therefore into its
/// PDF, which is that DOCX converted). Doing the same here — one painter,
/// rasterised once, embedded in both formats — is why the PDF and Word reports
/// cannot drift apart, and it is the only way to draw the two features
/// `pw.Chart` fundamentally cannot: a second y-axis and shaded vertical bands.
///
/// Matched to the desktop deliberately:
/// - the **Dark2** 8-colour cycle, and a 5-way **dash cycle** on top of it, so
///   series stay distinguishable in greyscale and for colour-blind readers;
/// - a missing x value **breaks** the line rather than interpolating across it;
/// - the left axis is clamped to the union of declared scale ranges when the
///   optimisation prefs supply one;
/// - the black **aggregate-index** line with diamond markers on its own right
///   axis fixed to 0..1;
/// - **green best / second-best bands** spanning +/- 0.35 of an x step.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../report/report_data.dart';
import 'chart_primitives.dart';

/// Layout constants, in logical px at the painter's nominal size.
///
/// There is deliberately NO `_padTop` constant. The top band holds a title and
/// a legend of unknown height, and hard-coding it is exactly what put the
/// legend's opaque box over the bottom third of every title glyph: the title
/// occupied y 20..38 and the legend box y 30..50. The band is measured in
/// [ChartTopBand] instead, so title, legend and plot each reserve their own space.
const _padBottom = 52.0; // x tick labels + axis label
const _padLeft = 62.0; // y tick labels + axis label

/// Title font size; the band reserves its measured height.
const _titleSize = 15.0;

/// Space between a legend entry's sample line and its label.
const _legendGapAfterSample = 5.0;

/// Vertical gap between stacked panels, in logical px.
const _panelGap = 14.0;

/// One stacked panel of the figure.
class _PanelSpec {
  const _PanelSpec({
    required this.weight,
    required this.yMin,
    required this.yMax,
    required this.label,
    required this.series,
    required this.ticks,
    this.mono = false,
  });

  /// Share of the available height, relative to the other panels.
  final double weight;
  final double yMin, yMax;
  final String label;
  final Map<String, Map<int, double>> series;

  /// Horizontal guides and y ticks to draw (0 and max inclusive).
  final int ticks;

  /// Draw as one heavy black line with diamond markers (the aggregate index).
  final bool mono;
}

class ScalesChartPainter extends CustomPainter {
  const ScalesChartPainter({
    required this.spec,
    this.background = const Color(0xFFFFFFFF),
    this.ink = const Color(0xFF000000),
  });

  final ScalesChartSpec spec;
  final Color background;
  final Color ink;

  bool get _hasIndex => spec.aggregateIndex.isNotEmpty;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    if (spec.isEmpty) return;

    final band = ChartTopBand.measure(this, size);
    final area = Rect.fromLTRB(
      _padLeft,
      band.padTop,
      size.width - 20,
      size.height - _padBottom,
    );
    if (area.width <= 10 || area.height <= 40) return;

    // Half a step of margin at each end (the desktop's
    // `set_xlim(min-0.5, max+0.5)`): it keeps the first/last markers and the
    // +/-0.35 bands clear of the axes, and makes a single-x chart well defined
    // instead of dividing by zero.
    final xLo = spec.xs.first.toDouble() - 0.5;
    final xHi = spec.xs.last.toDouble() + 0.5;
    double xPos(num x) => area.left +
        (xHi == xLo ? 0.5 : (x - xLo) / (xHi - xLo)) * area.width;

    // Panels, top to bottom, sharing that x mapping. The scales panel keeps the
    // lion's share; the index and dose strips only need enough height to show a
    // shape. Each has its OWN y axis, which is the point: the index used to sit
    // on a second axis inside the scales plot, so 0.43 was drawn at the height
    // of 4.3 on a 0-10 rating scale.
    final panels = <_PanelSpec>[
      _PanelSpec(
        weight: 3.0,
        yMin: spec.yMin,
        yMax: spec.yMax,
        label: spec.yLabel,
        series: spec.series,
        ticks: 4,
      ),
      if (_hasIndex)
        _PanelSpec(
          weight: 1.0,
          yMin: 0,
          yMax: 1,
          label: 'Aggregate index',
          series: {'Aggregate Index': spec.aggregateIndex},
          ticks: 2,
          mono: true,
        ),
      if (spec.amplitude.values.any((m) => m.isNotEmpty))
        _PanelSpec(
          weight: 1.0,
          // Dose is a magnitude: a non-zero-based axis makes 5.5 -> 4.5 mA look
          // like a collapse.
          yMin: 0,
          yMax: _niceMax(spec.amplitude),
          label: 'Amplitude (mA)',
          series: spec.amplitude,
          ticks: 2,
        ),
    ];

    final totalWeight = panels.fold<double>(0, (a, p) => a + p.weight);
    final gaps = _panelGap * (panels.length - 1);
    final usable = area.height - gaps;
    var top = area.top;
    final rects = <Rect>[];
    for (final p in panels) {
      final h = usable * p.weight / totalWeight;
      rects.add(Rect.fromLTRB(area.left, top, area.right, top + h));
      top += h + _panelGap;
    }

    // Title and legend first: their fills are opaque, and painting them last is
    // how the legend used to erase the title. They now occupy reserved space, so
    // the order is belt and braces.
    if (band.titleHeight > 0) {
      drawChartText(canvas, spec.title, Offset(area.center.dx, band.titleTop),
          align: TextAlign.center, size: _titleSize, color: ink);
    }
    _paintLegend(canvas, size, band);

    // One band spanning every panel: the reader compares a scale dip against
    // the dose that caused it, so the marker has to cross both.
    _paintBands(canvas, Rect.fromLTRB(area.left, rects.first.top, area.right,
        rects.last.bottom), xPos);

    for (var i = 0; i < panels.length; i++) {
      _paintPanel(canvas, rects[i], panels[i], xPos);
    }
    // The x axis belongs to the bottom panel only.
    _paintXAxis(canvas, rects.last, size, xPos);
  }

  /// A round number at or above the largest value, so the dose axis has a
  /// legible top tick instead of "7.43".
  static double _niceMax(Map<String, Map<int, double>> series) {
    var hi = 0.0;
    for (final m in series.values) {
      for (final v in m.values) {
        if (v > hi) hi = v;
      }
    }
    if (hi <= 0) return 1;
    for (final step in [0.5, 1.0, 2.0, 2.5, 5.0]) {
      final top = (hi / step).ceil() * step;
      if (top / step <= 8) return top;
    }
    return (hi / 5).ceil() * 5;
  }

  /// One panel: grid, its own y axis with ticks and label, then its series.
  void _paintPanel(Canvas canvas, Rect plot, _PanelSpec panel,
      double Function(num) xPos) {
    if (plot.height <= 6) return;
    final span = math.max(panel.yMax - panel.yMin, 1e-9);
    double yPos(double v) =>
        plot.bottom - ((v - panel.yMin) / span) * plot.height;

    final grid = Paint()
      ..color = ink.withValues(alpha: 0.3)
      ..strokeWidth = 0.6;
    for (var i = 0; i <= panel.ticks; i++) {
      final y = plot.bottom - plot.height * i / panel.ticks;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }
    for (final x in spec.xs) {
      final px = xPos(x);
      canvas.drawLine(Offset(px, plot.top), Offset(px, plot.bottom), grid);
    }

    _paintPanelSeries(canvas, plot, panel, xPos, yPos);

    // Frame: left and bottom, heavier than the grid.
    final axis = Paint()
      ..color = ink
      ..strokeWidth = 1.2;
    canvas
      ..drawLine(plot.bottomLeft, plot.bottomRight, axis)
      ..drawLine(plot.topLeft, plot.bottomLeft, axis);
    for (var i = 0; i <= panel.ticks; i++) {
      final v = panel.yMin + span * i / panel.ticks;
      final y = plot.bottom - plot.height * i / panel.ticks;
      canvas.drawLine(Offset(plot.left - 4, y), Offset(plot.left, y), axis);
      drawChartText(canvas, tickLabel(v), Offset(plot.left - 7, y),
          align: TextAlign.right, anchorY: 0.5, size: 10, color: ink);
    }
    drawRotatedChartText(canvas, panel.label, Offset(16, plot.center.dy),
        size: 11, color: ink);
  }

  /// A panel's series. [_PanelSpec.mono] draws one heavy black line with
  /// diamond markers (the index); otherwise the Dark2 colour + dash cycle.
  void _paintPanelSeries(Canvas canvas, Rect plot, _PanelSpec panel,
      double Function(num) xPos, double Function(double) yPos) {
    var i = 0;
    for (final entry in panel.series.entries) {
      final color = panel.mono ? ink : seriesColor(i);
      final dash = panel.mono ? null : seriesDash(i);
      i++;
      drawSeriesRuns(
        canvas,
        seriesRuns(spec.xs, entry.value, xPos, yPos),
        color: color,
        dash: dash,
        strokeWidth: panel.mono ? 3 : 2,
        markerRadius: panel.mono ? 0 : 3,
      );
      if (!panel.mono) continue;
      for (final x in spec.xs) {
        final v = entry.value[x];
        if (v == null) continue;
        canvas.drawPath(
            diamondPath(Offset(xPos(x), yPos(v)), 4.5), Paint()..color = color);
      }
    }
  }

  /// The shared x axis, under the bottom panel.
  void _paintXAxis(
      Canvas canvas, Rect plot, Size size, double Function(num) xPos) {
    final axis = Paint()
      ..color = ink
      ..strokeWidth = 1.2;
    // Long labels (the longitudinal figures' `20260626_01`) are drawn rotated,
    // because horizontally they would overlap after three visits.
    final labelled = spec.xTickLabels.isNotEmpty;
    final rotate = labelled &&
        spec.xTickLabels.values.any((l) => l.length > 4);
    for (final x in spec.xs) {
      final px = xPos(x);
      canvas.drawLine(
          Offset(px, plot.bottom), Offset(px, plot.bottom + 4), axis);
      final label = spec.xTickLabels[x] ?? '$x';
      if (rotate) {
        drawRotatedChartText(canvas, label, Offset(px, plot.bottom + 8),
            size: 8, color: ink, clockwise: true, anchorTop: true);
      } else {
        drawChartText(canvas, label, Offset(px, plot.bottom + 7),
            align: TextAlign.center, size: 10, color: ink);
      }
    }
    drawChartText(canvas, spec.xLabel, Offset(plot.center.dx, size.height - 22),
        align: TextAlign.center, size: 12, color: ink);
  }

  /// Green vertical bands behind everything, marking the best and second-best
  /// block. `axvspan(x +/- 0.35)` in the desktop. Clipped to the plot, since a
  /// band on the first or last block would otherwise spill over the axis.
  void _paintBands(Canvas canvas, Rect plot, double Function(num) xPos) {
    canvas
      ..save()
      ..clipRect(plot);

    // Contiguous blocks of one setting are drawn as ONE band, not one per
    // block: the unit being marked is the configuration, and two rectangles
    // with a white gap between them says "two things" when the whole point is
    // that they are the same thing rated twice.
    void bands(List<int> xs, int argb) {
      if (xs.isEmpty) return;
      final paint = Paint()..color = Color(argb).withValues(alpha: 0.62);
      final hatch = Paint()
        ..color = ink.withValues(alpha: 0.16)
        ..strokeWidth = 0.9;
      // Denser for rank 1, so the order reads without colour at all.
      final step = argb == kBestFill ? 7.0 : 14.0;
      final sorted = xs.toList()..sort();
      var from = sorted.first;
      var to = sorted.first;
      void flush() {
        final r = Rect.fromLTRB(
            xPos(from - 0.35), plot.top, xPos(to + 0.35), plot.bottom);
        canvas
          ..drawRect(r, paint)
          ..save()
          ..clipRect(r);
        for (var hx = r.left - r.height; hx < r.right + r.height; hx += step) {
          canvas.drawLine(
              Offset(hx, r.bottom), Offset(hx + r.height, r.top), hatch);
        }
        canvas.restore();
      }
      for (final x in sorted.skip(1)) {
        if (x == to + 1) {
          to = x;
          continue;
        }
        flush();
        from = x;
        to = x;
      }
      flush();
    }

    // Second first, so a shared edge lets the stronger best colour win.
    bands(spec.secondXs, kSecondFill);
    bands(spec.bestXs, kBestFill);
    canvas.restore();
  }

  /// Single-row legend, boxed and centred in the space [band] reserved for it —
  /// the desktop's `fig.legend(loc="upper center", ncol=len(handles),
  /// frameon=True)`.
  void _paintLegend(Canvas canvas, Size size, ChartTopBand band) {
    final legend = band.legend;
    if (legend == null) return;

    final box = Rect.fromLTWH(
      math.max(2, (size.width - legend.total) / 2 - 8),
      band.legendTop,
      math.min(legend.total + 16, size.width - 4),
      legend.height,
    );
    canvas
      ..drawRect(box, Paint()..color = background)
      ..drawRect(
        box,
        Paint()
          ..color = ink.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      )
      // Clip the contents: shrink-to-fit stops at a 6 pt floor, so a session
      // with very many scales can still exceed the box, and a sample line
      // spilling out of the frame looks like a rendering fault.
      ..save()
      ..clipRect(box);

    var x = box.left + 8;
    final y = box.center.dy;
    for (var i = 0; i < legend.entries.length; i++) {
      final (_, color, dash, kind) = legend.entries[i];
      if (kind == ChartLegendKind.band) {
        // A swatch, hatched: the two greens differ in lightness only, so in
        // greyscale or on a mono printer the hatch is what tells them apart.
        final swatch =
            Rect.fromLTWH(x, y - 5, legend.sample, 10);
        canvas
          ..drawRect(swatch, Paint()..color = color)
          ..drawRect(
              swatch,
              Paint()
                ..color = ink.withValues(alpha: 0.55)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 0.8)
          ..save()
          ..clipRect(swatch);
        final hatch = Paint()
          ..color = ink.withValues(alpha: 0.45)
          ..strokeWidth = 0.8;
        // Rank 1 gets a denser hatch than rank 2, so the ORDER survives too.
        final step = color.toARGB32() == kBestFill ? 4.0 : 8.0;
        for (var hx = swatch.left - 10; hx < swatch.right + 10; hx += step) {
          canvas.drawLine(
              Offset(hx, swatch.bottom), Offset(hx + 10, swatch.top), hatch);
        }
        canvas.restore();
      } else {
        final line = Path()
          ..moveTo(x, y)
          ..lineTo(x + legend.sample, y);
        canvas.drawPath(
          dash == null ? line : dashPath(line, dash),
          Paint()
            ..color = color
            ..strokeWidth = kind == ChartLegendKind.aggregate ? 3 : 2
            ..style = PaintingStyle.stroke,
        );
        final markerX = x + legend.sample / 2;
        if (kind == ChartLegendKind.aggregate) {
          canvas.drawPath(
              diamondPath(Offset(markerX, y), 4), Paint()..color = color);
        } else {
          canvas.drawCircle(Offset(markerX, y), 2.6, Paint()..color = color);
        }
      }
      x += legend.sample + _legendGapAfterSample;
      final p = legend.painters[i];
      p.paint(canvas, Offset(x, y - p.height / 2));
      x += p.width + legend.gapBetween;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ScalesChartPainter old) =>
      old.spec != spec || old.background != background || old.ink != ink;
}

/// What kind of sample a legend entry draws.
enum ChartLegendKind {
  /// A dashed/solid line with a round marker: one session scale.
  series,

  /// A heavy line with a diamond: the aggregate index. Not named `index` —
  /// every Dart enum already has an `index` property.
  aggregate,

  /// A filled, hatched swatch: a green ranking band.
  band,
}

/// The legend's shrink-to-fit result: what to draw and how wide it came out.
typedef ChartLegend = ({
  List<(String, Color, List<double>?, ChartLegendKind)> entries,
  List<TextPainter> painters,
  double sample,
  double gapBetween,
  double total,
  double height,
});

/// The measured top band — title, then legend, then the plot.
///
/// Replaces three hard-coded y values (title 20, legend box 30..50, `_padTop`
/// 46) that overlapped each other by 5 px and overran the plot by 4 px. Each
/// element now reserves its own height, so a two-line title or a legend that
/// shrank to fit cannot collide with anything.
///
/// Public only so `scales_chart_layout_test.dart` can assert those
/// non-overlap invariants directly, rather than by inspecting pixels.
class ChartTopBand {
  const ChartTopBand({
    required this.titleTop,
    required this.titleHeight,
    required this.legendTop,
    required this.padTop,
    required this.legend,
  });

  final double titleTop;
  final double titleHeight;
  final double legendTop;

  /// Where the plot may start.
  final double padTop;

  /// Null when there is nothing to put in a legend.
  final ChartLegend? legend;

  static const _outerPad = 6.0;
  static const _gap = 6.0;

  static ChartTopBand measure(ScalesChartPainter p, Size size) {
    final titleHeight = p.spec.title.isEmpty
        ? 0.0
        : chartTextPainter(p.spec.title, color: p.ink, size: _titleSize).height;
    final legend = _measureLegend(p, size);
    final legendTop =
        _outerPad + (titleHeight > 0 ? titleHeight + _gap : 0.0);
    return ChartTopBand(
      titleTop: _outerPad,
      titleHeight: titleHeight,
      legendTop: legendTop,
      padTop: legendTop +
          (legend == null ? _gap : legend.height + _gap + 2),
      legend: legend,
    );
  }

  /// Shrink to fit rather than overflow: a session with many scales would
  /// otherwise push the legend off the canvas.
  static ChartLegend? _measureLegend(ScalesChartPainter p, Size size) {
    final entries = <(String, Color, List<double>?, ChartLegendKind)>[
      for (final (i, name) in p.spec.series.keys.indexed)
        (name, seriesColor(i), seriesDash(i), ChartLegendKind.series),
      if (p.spec.aggregateIndex.isNotEmpty)
        ('Aggregate Index', p.ink, null, ChartLegendKind.aggregate),
      // The bands are part of the figure, so they belong in its key.
      if (p.spec.bestXs.isNotEmpty)
        ('Rank 1', const Color(kBestFill), null, ChartLegendKind.band),
      if (p.spec.secondXs.isNotEmpty)
        ('Rank 2', const Color(kSecondFill), null, ChartLegendKind.band),
    ];
    if (entries.isEmpty) return null;

    var font = 9.0;
    var sample = 22.0;
    var gapBetween = 14.0;
    List<TextPainter> painters;
    double total;
    while (true) {
      painters = [
        for (final e in entries) chartTextPainter(e.$1, color: p.ink, size: font),
      ];
      total = painters.fold<double>(
              0, (sum, t) => sum + sample + _legendGapAfterSample + t.width) +
          gapBetween * (entries.length - 1);
      if (total <= size.width - 20 || font <= 6) break;
      font -= 0.5;
      sample = math.max(12, sample - 1);
      gapBetween = math.max(6, gapBetween - 1);
    }
    // Box height from the tallest label, so a larger font is never clipped.
    final textHeight =
        painters.fold<double>(0, (m, t) => math.max(m, t.height));
    return (
      entries: entries,
      painters: painters,
      sample: sample,
      gapBetween: gapBetween,
      total: total,
      height: math.max(18.0, textHeight + 8),
    );
  }
}

/// Rasterise the scales chart to PNG bytes for embedding in a report.
///
/// [size] is the logical chart size; [pixelRatio] multiplies it, so the default
/// yields 2400x1130 — well above the ~1089x518 the desktop's matplotlib chart
/// produces, so print quality is a clear improvement over the reference.
/// Returns null when there is nothing to plot, matching `build_scales_chart`'s
/// `None` so callers can fall back to a text line.
Future<Uint8List?> renderScalesChartPng(
  ScalesChartSpec spec, {
  Size size = const Size(800, 376),
  double pixelRatio = 3.0,
}) async {
  if (spec.isEmpty) return null;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(pixelRatio);
  ScalesChartPainter(spec: spec).paint(canvas, size);
  final image = await recorder.endRecording().toImage(
        (size.width * pixelRatio).round(),
        (size.height * pixelRatio).round(),
      );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data?.buffer.asUint8List();
}
