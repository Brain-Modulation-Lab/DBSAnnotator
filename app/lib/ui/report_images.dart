/// Screen-side rasterisers that turn the electrode painter into PNG bytes for
/// the PDF / Word reports. Uses `dart:ui` (the Flutter engine), so it must run
/// in the app (not in the pure, headless report builders) — the builders take
/// the resulting PNG bytes as optional parameters.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/electrode/electrode_model.dart';
import '../core/electrode/geometry.dart';
import '../core/electrode/tokens.dart';
import 'electrode_painter.dart';
import 'theme.dart';

/// Render one electrode configuration (from anode/cathode token strings) to a
/// white-background PNG, mirroring the desktop's `render_electrode_png`.
Future<Uint8List> renderElectrodePng(
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
  return data!.buffer.asUint8List();
}
