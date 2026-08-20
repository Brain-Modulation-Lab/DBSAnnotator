/// The electrode painter, split out of `electrode_view.dart` so the report
/// layer can rasterise a lead offscreen without importing a widget.
///
/// Mirrors the desktop `ElectrodeCanvas.paintEvent`
/// (`src/dbs_annotator/models/electrode_viewer.py`): cylinder + CASE gradients,
/// metallic radial-gradient contacts with drop shadows and specular highlights.
library;

import 'package:flutter/material.dart';

import '../core/electrode/contact_state.dart';
import '../core/electrode/geometry.dart';
import '../core/electrode/stimulation_rule.dart';
import 'theme.dart';

/// Painter mirroring the desktop paintEvent: cylinder + CASE gradients, metallic
/// radial-gradient contacts with drop shadows and specular highlights.
class ElectrodePainter extends CustomPainter {
  ElectrodePainter({
    required this.layout,
    required this.states,
    required this.caseState,
    required this.labelColor,
  });

  final ElectrodeLayout layout;
  final Map<ContactKey, ContactState> states;
  final ContactState caseState;

  /// Theme text colour for the E{idx} labels beside the lead.
  final Color labelColor;

  // Lead cylinder base (Qt palette Midlight ~ #BDBDBD).
  static const _leadBase = Color(0xFFBDBDBD);
  static const _segmentLabels = ['a', 'b', 'c'];

  // State base/border reuse the shared desktop tokens (theme.dart).
  static Color _base(ContactState s) => switch (s) {
        ContactState.anodic => DbsColors.anodicBase,
        ContactState.cathodic => DbsColors.cathodicBase,
        ContactState.off => DbsColors.offBase,
      };

  static Color _border(ContactState s) => switch (s) {
        ContactState.anodic => DbsColors.anodicBorder,
        ContactState.cathodic => DbsColors.cathodicBorder,
        ContactState.off => DbsColors.offBorder,
      };

  /// Qt `QColor.lighter(pct)` — scale HSV value up.
  static Color _lighter(Color c, int pct) {
    final h = HSVColor.fromColor(c);
    return h.withValue((h.value * pct / 100).clamp(0.0, 1.0)).toColor();
  }

  /// Qt `QColor.darker(pct)` — scale HSV value down.
  static Color _darker(Color c, int pct) {
    final h = HSVColor.fromColor(c);
    return h.withValue((h.value * 100 / pct).clamp(0.0, 1.0)).toColor();
  }

  /// White label on active shapes, black on OFF (desktop behaviour).
  static Color _labelOn(ContactState state) =>
      state == ContactState.off ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

  Paint _borderPaint(ContactState state) => Paint()
    ..color = _border(state)
    ..style = PaintingStyle.stroke
    ..strokeWidth = state == ContactState.off ? 1 : 3;

  /// A contact/segment: drop shadow, metallic radial gradient, border, and a
  /// specular highlight when active.
  void _paintContact(Canvas canvas, Rect rect, ContactState state,
      {double radius = 3}) {
    final base = _base(state);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.translate(0, 2), Radius.circular(radius)),
      Paint()..color = const Color(0x14000000), // black alpha 20
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.9,
          colors: [
            _lighter(base, 150),
            _lighter(base, 110),
            _darker(base, 110),
            _darker(base, 130),
          ],
          stops: const [0.0, 0.5, 0.85, 1.0],
        ).createShader(rect),
    );
    canvas.drawRRect(rrect, _borderPaint(state));
    if (state != ContactState.off) {
      final hl = Rect.fromLTWH(rect.left + rect.width * 0.15, rect.top + 1,
          rect.width * 0.3, rect.height * 0.4);
      canvas.drawRRect(RRect.fromRectAndRadius(hl, const Radius.circular(2)),
          Paint()..color = const Color(0x32FFFFFF)); // white alpha 50
    }
  }

  /// The CASE (ground): vertical gradient + top-left specular.
  void _paintCase(Canvas canvas, Rect rect, ContactState state) {
    final base = _base(state);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_lighter(base, 130), base, _darker(base, 120)],
        ).createShader(rect),
    );
    canvas.drawRRect(rrect, _borderPaint(state));
    final hl = Rect.fromLTWH(rect.left + rect.width * 0.05,
        rect.top + rect.height * 0.1, rect.width * 0.4, rect.height * 0.3);
    canvas.drawRRect(RRect.fromRectAndRadius(hl, const Radius.circular(3)),
        Paint()..color = const Color(0x28FFFFFF)); // white alpha 40
  }

  /// A directional ring cap: vertical gradient + shadow + specular.
  void _paintCap(Canvas canvas, Rect rect, ContactState state) {
    final base = _base(state);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.translate(0, 1), const Radius.circular(3)),
      Paint()..color = const Color(0x19000000), // black alpha 25
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_lighter(base, 150), _lighter(base, 120), _darker(base, 80)],
          stops: const [0.0, 0.3, 1.0],
        ).createShader(rect),
    );
    canvas.drawRRect(rrect, _borderPaint(state));
    if (state != ContactState.off) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(rect.left + rect.width * 0.1, rect.top + 1,
                  rect.width * 0.3, rect.height * 0.4),
              const Radius.circular(2)),
          Paint()..color = const Color(0x32FFFFFF));
    }
  }

  /// The lead cylinder: horizontal shading gradient + outline.
  void _paintLead(Canvas canvas, Rect rect) {
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(rect.width / 4));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            _darker(_leadBase, 120),
            _leadBase,
            _leadBase,
            _darker(_leadBase, 120),
          ],
          stops: const [0.0, 0.3, 0.7, 1.0],
        ).createShader(rect),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = _darker(_leadBase, 150)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _paintTextCentered(Canvas canvas, String text, Rect rect, Color color,
      double fontSize) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      rect.center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _paintLevelLabel(Canvas canvas, LevelLayout level) {
    // Right-aligned "E{idx}" just left of the level's leftmost rect.
    final leftmost = level.contactRects.values
        .reduce((a, b) => a.left <= b.left ? a : b);
    final painter = TextPainter(
      text: TextSpan(
        text: 'E${level.levelIdx}',
        style: TextStyle(
          color: labelColor,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        leftmost.left - 8 - painter.width,
        leftmost.center.dy - painter.height / 2,
      ),
    );
  }

  ContactState _ringState(int levelIdx) {
    final segStates = [
      for (var seg = 0; seg < 3; seg++)
        states[ContactKey(levelIdx, seg)] ?? ContactState.off,
    ];
    if (segStates.every((s) => s == ContactState.anodic)) {
      return ContactState.anodic;
    }
    if (segStates.every((s) => s == ContactState.cathodic)) {
      return ContactState.cathodic;
    }
    return ContactState.off;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintLead(canvas, layout.leadRect);

    _paintCase(canvas, layout.caseRect, caseState);
    _paintTextCentered(
        canvas, 'CASE', layout.caseRect, _labelOn(caseState), 12);

    for (final level in layout.levels) {
      for (final entry in level.contactRects.entries) {
        final state = states[entry.key] ?? ContactState.off;
        _paintContact(canvas, entry.value, state);
        if (level.isDirectional) {
          _paintTextCentered(canvas, _segmentLabels[entry.key.segmentIdx],
              entry.value, _labelOn(state), 11);
        }
      }

      final cap = level.ringCapRect;
      if (cap != null) {
        final ringState = _ringState(level.levelIdx);
        _paintCap(canvas, cap, ringState);
        _paintTextCentered(canvas, 'Ring', cap, _labelOn(ringState), 9);
      }

      _paintLevelLabel(canvas, level);
    }
  }

  @override
  bool shouldRepaint(ElectrodePainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.states != states ||
      oldDelegate.caseState != caseState ||
      oldDelegate.labelColor != labelColor;
}
