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

/// matplotlib's `Dark2` qualitative colormap, the desktop's series palette.
const _dark2 = <Color>[
  Color(0xFF1B9E77),
  Color(0xFFD95F02),
  Color(0xFF7570B3),
  Color(0xFFE7298A),
  Color(0xFF66A61E),
  Color(0xFFE6AB02),
  Color(0xFFA6761D),
  Color(0xFF666666),
];

/// Dash patterns cycling independently of colour (matplotlib `_LINE_STYLES`):
/// solid, dashed, dotted, dash-dot, dash-dot-dot. `null` means solid.
const _dashes = <List<double>?>[
  null,
  [6, 3],
  [1.5, 3],
  [6, 3, 1.5, 3],
  [6, 3, 1.5, 3, 1.5, 3],
];

/// Layout constants, in logical px at the painter's nominal size.
const _padTop = 46.0; // legend strip
const _padBottom = 52.0; // x tick labels + axis label
const _padLeft = 62.0; // y tick labels + axis label
const _padRight = 74.0; // right axis for the aggregate index

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

    final plot = Rect.fromLTRB(
      _padLeft,
      _padTop,
      size.width - (_hasIndex ? _padRight : 20),
      size.height - _padBottom,
    );
    if (plot.width <= 10 || plot.height <= 10) return;

    // Half a step of margin at each end (the desktop's
    // `set_xlim(min-0.5, max+0.5)`): it keeps the first/last markers and the
    // +/-0.35 bands clear of the axes, and makes a single-x chart well defined
    // instead of dividing by zero.
    final xLo = spec.xs.first.toDouble() - 0.5;
    final xHi = spec.xs.last.toDouble() + 0.5;
    double xPos(num x) => plot.left +
        (xHi == xLo ? 0.5 : (x - xLo) / (xHi - xLo)) * plot.width;
    double yPos(double v) => plot.bottom -
        ((v - spec.yMin) / math.max(spec.yMax - spec.yMin, 1e-9)) * plot.height;
    double yIndex(double v) => plot.bottom - v.clamp(0.0, 1.0) * plot.height;

    _paintBands(canvas, plot, xPos);
    _paintGrid(canvas, plot, xPos);
    _paintSeries(canvas, plot, xPos, yPos);
    if (_hasIndex) _paintIndex(canvas, xPos, yIndex);
    _paintAxes(canvas, plot, size, xPos);
    _paintLegend(canvas, size);
  }

  /// Green vertical bands behind everything, marking the best and second-best
  /// block. `axvspan(x +/- 0.35)` in the desktop. Clipped to the plot, since a
  /// band on the first or last block would otherwise spill over the axis.
  void _paintBands(Canvas canvas, Rect plot, double Function(num) xPos) {
    canvas
      ..save()
      ..clipRect(plot);

    void band(int? x, int argb) {
      if (x == null) return;
      canvas.drawRect(
        Rect.fromLTRB(xPos(x - 0.35), plot.top, xPos(x + 0.35), plot.bottom),
        Paint()..color = Color(argb).withValues(alpha: 0.62),
      );
    }

    // Second first, so a shared edge lets the stronger best colour win.
    if (spec.secondX != spec.bestX) band(spec.secondX, kSecondFill);
    band(spec.bestX, kBestFill);
    canvas.restore();
  }

  void _paintGrid(Canvas canvas, Rect plot, double Function(num) xPos) {
    final grid = Paint()
      ..color = ink.withValues(alpha: 0.3)
      ..strokeWidth = 0.6;
    for (var i = 0; i <= 4; i++) {
      final y = plot.bottom - plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }
    for (final x in spec.xs) {
      final px = xPos(x);
      canvas.drawLine(Offset(px, plot.top), Offset(px, plot.bottom), grid);
    }
  }

  void _paintSeries(Canvas canvas, Rect plot, double Function(num) xPos,
      double Function(double) yPos) {
    var i = 0;
    for (final entry in spec.series.entries) {
      final color = _dark2[i % _dark2.length];
      final dash = _dashes[i % _dashes.length];
      i++;

      // Consecutive runs of present values; a gap breaks the line.
      final runs = <List<Offset>>[];
      var run = <Offset>[];
      for (final x in spec.xs) {
        final v = entry.value[x];
        if (v == null) {
          if (run.isNotEmpty) runs.add(run);
          run = <Offset>[];
          continue;
        }
        run.add(Offset(xPos(x), yPos(v)));
      }
      if (run.isNotEmpty) runs.add(run);

      final stroke = Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (final r in runs) {
        if (r.length < 2) continue;
        final path = Path()..moveTo(r.first.dx, r.first.dy);
        for (final p in r.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(dash == null ? path : _dashPath(path, dash), stroke);
      }
      // Circle markers, drawn over the line.
      final fill = Paint()..color = color;
      for (final r in runs) {
        for (final p in r) {
          canvas.drawCircle(p, 3, fill);
        }
      }
    }
  }

  /// The aggregate index: black, thicker, diamond markers, on the right axis.
  void _paintIndex(
      Canvas canvas, double Function(num) xPos, double Function(double) yIndex) {
    final pts = [
      for (final x in spec.xs)
        if (spec.aggregateIndex.containsKey(x))
          Offset(xPos(x), yIndex(spec.aggregateIndex[x]!)),
    ];
    if (pts.isEmpty) return;
    if (pts.length > 1) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = ink
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke,
      );
    }
    for (final p in pts) {
      canvas.drawPath(_diamond(p, 4.5), Paint()..color = ink);
    }
  }

  void _paintAxes(Canvas canvas, Rect plot, Size size,
      double Function(num) xPos) {
    final axis = Paint()
      ..color = ink
      ..strokeWidth = 1.2;
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axis);
    canvas.drawLine(plot.topLeft, plot.bottomLeft, axis);

    // Left ticks + labels.
    for (var i = 0; i <= 4; i++) {
      final v = spec.yMin + (spec.yMax - spec.yMin) * i / 4;
      final y = plot.bottom - plot.height * i / 4;
      canvas.drawLine(Offset(plot.left - 4, y), Offset(plot.left, y), axis);
      _text(canvas, _num(v), Offset(plot.left - 7, y),
          align: TextAlign.right, anchorY: 0.5, size: 10);
    }
    // X ticks + labels (integers only, like the desktop's MaxNLocator).
    for (final x in spec.xs) {
      final px = xPos(x);
      canvas.drawLine(
          Offset(px, plot.bottom), Offset(px, plot.bottom + 4), axis);
      _text(canvas, '$x', Offset(px, plot.bottom + 7),
          align: TextAlign.center, size: 10);
    }
    _text(canvas, spec.xLabel, Offset(plot.center.dx, size.height - 22),
        align: TextAlign.center, size: 12);
    _rotatedText(canvas, spec.yLabel, Offset(16, plot.center.dy), size: 12);
    if (spec.title.isNotEmpty) {
      _text(canvas, spec.title, Offset(plot.center.dx, 20),
          align: TextAlign.center, size: 15);
    }

    if (!_hasIndex) return;
    // Right axis for the index: fixed 0..1, bold label (desktop emphasises it).
    canvas.drawLine(plot.topRight, plot.bottomRight,
        Paint()..color = ink..strokeWidth = 2);
    for (var i = 0; i <= 5; i++) {
      final y = plot.bottom - plot.height * i / 5;
      canvas.drawLine(Offset(plot.right, y), Offset(plot.right + 4, y), axis);
      _text(canvas, (i / 5).toStringAsFixed(1), Offset(plot.right + 7, y),
          align: TextAlign.left, anchorY: 0.5, size: 10, bold: true);
    }
    _rotatedText(canvas, 'Aggregate Index Score (best = 1.0)',
        Offset(size.width - 12, plot.center.dy),
        size: 11, bold: true, clockwise: true);
  }

  /// Single-row legend centred above the plot, boxed — the desktop's
  /// `fig.legend(loc="upper center", ncol=len(handles), frameon=True)`.
  void _paintLegend(Canvas canvas, Size size) {
    final entries = <(String, Color, List<double>?, bool)>[
      for (final (i, name) in spec.series.keys.indexed)
        (name, _dark2[i % _dark2.length], _dashes[i % _dashes.length], false),
      if (_hasIndex) ('Aggregate Index', ink, null, true),
    ];
    if (entries.isEmpty) return;

    // Shrink to fit rather than overflow: a lead with many session scales would
    // otherwise push the legend off the canvas.
    const gapAfterSample = 5.0;
    var font = 9.0;
    var sample = 22.0;
    var gapBetween = 14.0;
    List<TextPainter> painters;
    double total;
    while (true) {
      painters = [for (final e in entries) _layout(e.$1, font, false)];
      total = painters.fold<double>(
              0, (sum, p) => sum + sample + gapAfterSample + p.width) +
          gapBetween * (entries.length - 1);
      if (total <= size.width - 20 || font <= 6) break;
      font -= 0.5;
      sample = math.max(12, sample - 1);
      gapBetween = math.max(6, gapBetween - 1);
    }

    final box = Rect.fromLTWH(
      math.max(2, (size.width - total) / 2 - 8),
      30,
      math.min(total + 16, size.width - 4),
      20,
    );
    canvas
      ..drawRect(box, Paint()..color = background)
      ..drawRect(
        box,
        Paint()
          ..color = ink.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );

    var x = box.left + 8;
    final y = box.center.dy;
    for (var i = 0; i < entries.length; i++) {
      final (_, color, dash, isIndex) = entries[i];
      final line = Path()
        ..moveTo(x, y)
        ..lineTo(x + sample, y);
      canvas.drawPath(
        dash == null ? line : _dashPath(line, dash),
        Paint()
          ..color = color
          ..strokeWidth = isIndex ? 3 : 2
          ..style = PaintingStyle.stroke,
      );
      if (isIndex) {
        canvas.drawPath(
            _diamond(Offset(x + sample / 2, y), 4), Paint()..color = color);
      } else {
        canvas.drawCircle(
            Offset(x + sample / 2, y), 2.6, Paint()..color = color);
      }
      x += sample + gapAfterSample;
      painters[i].paint(canvas, Offset(x, y - painters[i].height / 2));
      x += painters[i].width + gapBetween;
    }
  }

  // --- primitives ----------------------------------------------------------

  static Path _diamond(Offset c, double r) => Path()
    ..moveTo(c.dx, c.dy - r)
    ..lineTo(c.dx + r, c.dy)
    ..lineTo(c.dx, c.dy + r)
    ..lineTo(c.dx - r, c.dy)
    ..close();

  /// Flutter has no dashed stroke, so walk the path and emit segments.
  static Path _dashPath(Path source, List<double> pattern) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var i = 0;
      var draw = true;
      while (distance < metric.length) {
        final len = pattern[i % pattern.length];
        final next = math.min(distance + len, metric.length);
        if (draw) out.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next;
        draw = !draw;
        i++;
      }
    }
    return out;
  }

  /// Trim a tick value the way matplotlib does: integers lose the ".0".
  static String _num(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

  TextPainter _layout(String text, double size, bool bold) => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: ink,
            fontSize: size,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  void _text(Canvas canvas, String text, Offset at,
      {TextAlign align = TextAlign.left,
      double anchorY = 0,
      double size = 10,
      bool bold = false}) {
    final p = _layout(text, size, bold);
    final dx = switch (align) {
      TextAlign.center => at.dx - p.width / 2,
      TextAlign.right => at.dx - p.width,
      _ => at.dx,
    };
    p.paint(canvas, Offset(dx, at.dy - p.height * anchorY));
  }

  void _rotatedText(Canvas canvas, String text, Offset at,
      {double size = 12, bool bold = false, bool clockwise = false}) {
    final p = _layout(text, size, bold);
    canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..rotate(clockwise ? math.pi / 2 : -math.pi / 2);
    p.paint(canvas, Offset(-p.width / 2, -p.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(ScalesChartPainter old) =>
      old.spec != spec || old.background != background || old.ink != ink;
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
