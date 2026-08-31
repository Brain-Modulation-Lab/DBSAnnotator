/// Screen-side rasterisers that turn the electrode painter into PNG bytes for
/// the PDF / Word reports. Uses `dart:ui` (the Flutter engine), so it must run
/// in the app (not in the pure, headless report builders) — the builders take
/// the resulting PNG bytes as optional parameters.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/session/session_row.dart';
import '../report/report_data.dart' show SessionReportData;
import '../report/report_sections.dart';
import '../report/session_pdf.dart' show ElectrodeReportImages;
import 'scales_chart_painter.dart';

import '../core/electrode/electrode_model.dart';
import '../core/electrode/geometry.dart';
import '../core/electrode/tokens.dart';
import 'electrode_painter.dart';
import 'theme.dart';

/// Render one electrode configuration (from anode/cathode token strings) to a
/// white-background PNG, mirroring the desktop's `render_electrode_png`.
Future<Uint8List?> renderElectrodePng(
  ElectrodeModel model,
  String anode,
  String cathode, {
  Size size = const Size(300, 640),
  Color labelColor = const Color(0xFF222222),
  // Reports are embedded at ~170 pt tall, so render well above screen density
  // to stay crisp in print (the desktop exporter likewise renders its PNG far
  // larger than the on-screen canvas).
  double pixelRatio = 3.0,
}) async {
  final decoded = decodeTokens(anode, cathode, model);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pixelRatio);
  // Opaque white background (reports embed on white pages).
  canvas.drawRect(
    Offset.zero & size,
    Paint()..color = const Color(0xFFFFFFFF),
  );
  ElectrodePainter(
    layout: computeLayout(model, size),
    states: decoded.states,
    caseState: decoded.caseState,
    labelColor: labelColor,
    // Reports print on white paper, so force the light lead palette
    // regardless of the app's current theme.
    palette: ElectrodePalette.light,
  ).paint(canvas, size);
  final image = await recorder.endRecording().toImage(
        (size.width * pixelRatio).round(),
        (size.height * pixelRatio).round(),
      );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  // Null rather than `data!`: an export must never be lost because one lead
  // failed to rasterise. Both report builders already fall back to anode/cathode
  // token text when an image is absent — that path was unreachable while this
  // threw.
  return data?.buffer.asUint8List();
}

/// The graphics both report formats embed, rasterised once so the PDF and the
/// Word document are guaranteed to show identical images.
///
/// Shared by the authoring screen and the from-a-file report screen. The second
/// one had its own copy for about ten minutes, which is how long it took to
/// notice it was a worse copy: no section gating, four sequential awaits instead
/// of concurrent, and its own idea of which rows to draw.
///
/// Only what [sections] will actually embed is rendered: PNG encoding costs
/// a few hundred ms on the UI isolate, so rasterising four leads for a report
/// that omits the electrode section is pure latency.
Future<({ElectrodeReportImages? electrodes, Uint8List? chart})>
    renderReportGraphics(SessionReportData data, ElectrodeModel? model,
        Set<ReportSection> sections) async {
  // Every rasterisation is best-effort. Both builders already degrade to
  // anode/cathode token text when an image is missing, but that fallback was
  // unreachable: a single failure here aborted the whole export and the user
  // got no report at all. A report without a picture beats no report.
  Uint8List? chart;
  if (sections.contains(ReportSection.chart)) {
    try {
      chart = await renderScalesChartPng(data.chart);
    } catch (e, st) {
      debugPrint('Scales chart could not be rendered: $e\n$st');
    }
  }
  if (model == null || !sections.contains(ReportSection.electrodes)) {
    return (electrodes: null, chart: chart);
  }

  // Take the rows report_data itself resolved (highest session, then highest
  // block, numerically coerced). Re-deriving them here with a simpler rule
  // used to let the images show one configuration while the text beside them
  // described another — e.g. for a TSV writing `is_initial` as "1.0".
  Future<Uint8List?> png(SessionRow? row, bool left) async {
    if (row == null) return null;
    try {
      return await renderElectrodePng(
        model,
        left ? row.leftAnode : row.rightAnode,
        left ? row.leftCathode : row.rightCathode,
      );
    } catch (e) {
      debugPrint('Electrode image could not be rendered: $e');
      return null;
    }
  }

  // Rasterise the four leads concurrently rather than one after another.
  final leads = await Future.wait([
    png(data.initialRow, true),
    png(data.initialRow, false),
    png(data.finalRow, true),
    png(data.finalRow, false),
  ]);

  return (
    electrodes: (
      initLeft: leads[0],
      initRight: leads[1],
      finalLeft: leads[2],
      finalRight: leads[3],
    ),
    chart: chart,
  );
}
