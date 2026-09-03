/// The chart's top band: title, then legend, then plot — none overlapping.
///
/// The defect this pins was reported from a generated report: the title sat at
/// y 20..38, the legend's OPAQUE box at y 30..50, and the legend was painted
/// after the axes, so its fill erased the bottom third of every title glyph.
/// `_padTop` was 46, four pixels above the legend's bottom, so the legend also
/// overran the plot.
library;

import 'package:dbs_annotator/report/report_data.dart';
import 'package:dbs_annotator/ui/scales_chart_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ScalesChartSpec _spec({
  String title = 'Session scales',
  int scales = 5,
  bool withIndex = true,
}) =>
    ScalesChartSpec(
      xs: const [1, 2, 3],
      series: {
        for (var i = 0; i < scales; i++)
          'Scale number $i': const {1: 3.0, 2: 4.0, 3: 5.0},
      },
      aggregateIndex: withIndex ? const {1: 0.4, 2: 0.5, 3: 0.6} : const {},
      amplitude: const {
        'Left': {1: 2.0, 2: 3.0, 3: 3.5},
      },
      bestXs: withIndex ? const [3] : const [],
      secondXs: withIndex ? const [2] : const [],
      yMin: 0,
      yMax: 10,
      title: title,
      xLabel: 'Block',
      yLabel: 'Score',
    );

void main() {
  ChartTopBand band(ScalesChartSpec spec, [Size size = const Size(800, 376)]) =>
      ChartTopBand.measure(ScalesChartPainter(spec: spec), size);

  test('the legend starts below the title, and the plot below the legend', () {
    final b = band(_spec());
    expect(b.titleHeight, greaterThan(0));
    expect(b.legendTop, greaterThanOrEqualTo(b.titleTop + b.titleHeight),
        reason: 'the legend box would paint over the title');
    expect(
        b.padTop, greaterThanOrEqualTo(b.legendTop + (b.legend?.height ?? 0)),
        reason: 'the legend would overrun the plot');
  });

  test('a title-less chart reserves no title space', () {
    final b = band(_spec(title: ''));
    expect(b.titleHeight, 0);
    expect(b.legendTop, b.titleTop, reason: 'the legend moves up to fill it');
    expect(b.padTop, lessThan(band(_spec()).padTop));
  });

  test('the invariants hold however many scales there are', () {
    // Shrink-to-fit stops at a 6 pt floor, so a long legend can still be wider
    // than the canvas; it must never grow taller into the plot.
    for (final n in [1, 5, 12, 30]) {
      final b = band(_spec(scales: n));
      expect(b.legendTop, greaterThanOrEqualTo(b.titleTop + b.titleHeight),
          reason: '$n scales');
      expect(
          b.padTop, greaterThanOrEqualTo(b.legendTop + (b.legend?.height ?? 0)),
          reason: '$n scales');
      expect(b.padTop, lessThan(120),
          reason: '$n scales must not eat the plot');
    }
  });

  test('no legend at all still leaves the plot a sane top', () {
    final b = band(_spec(title: '', scales: 0, withIndex: false));
    expect(b.legend, isNull);
    expect(b.padTop, greaterThan(0));
  });
}
