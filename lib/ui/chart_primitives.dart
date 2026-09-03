/// Drawing primitives shared by the report chart and the on-screen entry
/// panels.
///
/// The two have genuinely different *layouts* — the report chart is a single
/// fixed-size figure with a title, a legend and a second axis; the panels are a
/// stack sharing one scrollable x axis — so they are separate painters. But the
/// parts that decide whether a series *looks right* (dash patterns, breaking a
/// line across a missing point, marker shape, tick formatting) belong in one
/// place. Duplicating them is how the two drift into disagreeing about the same
/// data.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'painter_font.dart';

/// matplotlib's `Dark2` qualitative colormap — the desktop's series palette, so
/// a scale keeps its colour between the app and the report.
const kDark2 = <Color>[
  Color(0xFF1B9E77),
  Color(0xFFD95F02),
  Color(0xFF7570B3),
  Color(0xFFE7298A),
  Color(0xFF66A61E),
  Color(0xFFE6AB02),
  Color(0xFFA6761D),
  Color(0xFF666666),
];

/// Dash patterns cycling independently of colour: solid, dashed, dotted,
/// dash-dot, dash-dot-dot. `null` means solid.
///
/// Colour alone is not enough — 8 colours × 5 patterns keeps 40 series
/// distinguishable, and the pattern survives greyscale printing and the common
/// forms of colour blindness.
const kDashes = <List<double>?>[
  null,
  [6, 3],
  [1.5, 3],
  [6, 3, 1.5, 3],
  [6, 3, 1.5, 3, 1.5, 3],
];

/// Colour for series [i], cycling.
Color seriesColor(int i) => kDark2[i % kDark2.length];

/// Dash pattern for series [i], cycling.
List<double>? seriesDash(int i) => kDashes[i % kDashes.length];

/// Flutter has no dashed stroke, so walk the path and emit the "on" segments.
Path dashPath(Path source, List<double> pattern) {
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

/// A diamond marker, used for the aggregate-index series.
Path diamondPath(Offset c, double r) => Path()
  ..moveTo(c.dx, c.dy - r)
  ..lineTo(c.dx + r, c.dy)
  ..lineTo(c.dx, c.dy + r)
  ..lineTo(c.dx - r, c.dy)
  ..close();

/// Split a series into runs of consecutive points that actually have a value.
///
/// A missing x must **break** the line rather than be interpolated across:
/// joining block 2 to block 5 would draw a trend through a scale that was not
/// assessed at 3 and 4.
List<List<Offset>> seriesRuns(
  Iterable<int> xs,
  Map<int, double> values,
  double Function(num) xPos,
  double Function(double) yPos,
) {
  final runs = <List<Offset>>[];
  var run = <Offset>[];
  for (final x in xs) {
    final v = values[x];
    if (v == null) {
      if (run.isNotEmpty) runs.add(run);
      run = <Offset>[];
      continue;
    }
    run.add(Offset(xPos(x), yPos(v)));
  }
  if (run.isNotEmpty) runs.add(run);
  return runs;
}

/// Stroke [runs] with [color]/[dash] and put a round marker on every point.
///
/// A single-point run gets its marker but no line, which is how an isolated
/// reading should read.
void drawSeriesRuns(
  Canvas canvas,
  List<List<Offset>> runs, {
  required Color color,
  List<double>? dash,
  double strokeWidth = 2,
  double markerRadius = 3,
}) {
  final stroke = Paint()
    ..color = color
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  for (final r in runs) {
    if (r.length < 2) continue;
    final path = Path()..moveTo(r.first.dx, r.first.dy);
    for (final p in r.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(dash == null ? path : dashPath(path, dash), stroke);
  }
  if (markerRadius <= 0) return;
  final fill = Paint()..color = color;
  for (final r in runs) {
    for (final p in r) {
      canvas.drawCircle(p, markerRadius, fill);
    }
  }
}

/// Trim a tick value the way matplotlib does: integers lose the ".0".
String tickLabel(double v) {
  if (v == v.roundToDouble() && v.abs() < 100000) return '${v.toInt()}';
  return v.toStringAsFixed(v.abs() < 10 ? 1 : 0);
}

/// A laid-out text run, ready to paint.
TextPainter chartTextPainter(String text,
        {required Color color, double size = 10, bool bold = false}) =>
    TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: debugPainterFontFamily,
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

/// Paint [text] at [at]. [align] is horizontal; [anchorY] is the fraction of the
/// text height above [at] (0 = top, 0.5 = vertically centred).
void drawChartText(
  Canvas canvas,
  String text,
  Offset at, {
  required Color color,
  TextAlign align = TextAlign.left,
  double anchorY = 0,
  double size = 10,
  bool bold = false,
}) {
  final p = chartTextPainter(text, color: color, size: size, bold: bold);
  final dx = switch (align) {
    TextAlign.center => at.dx - p.width / 2,
    TextAlign.right => at.dx - p.width,
    _ => at.dx,
  };
  p.paint(canvas, Offset(dx, at.dy - p.height * anchorY));
}

/// Paint [text] rotated a quarter turn, centred on [at] — for axis titles.
void drawRotatedChartText(
  Canvas canvas,
  String text,
  Offset at, {
  required Color color,
  double size = 12,
  bool bold = false,
  bool clockwise = false,

  /// Anchor the text's START at [at] instead of its centre, so a rotated tick
  /// label hangs down from its tick rather than straddling the axis.
  bool anchorTop = false,
}) {
  final p = chartTextPainter(text, color: color, size: size, bold: bold);
  canvas
    ..save()
    ..translate(at.dx, at.dy)
    ..rotate(clockwise ? math.pi / 2 : -math.pi / 2);
  p.paint(canvas, Offset(anchorTop ? 0 : -p.width / 2, -p.height / 2));
  canvas.restore();
}
