/// Pure layout math for the interactive electrode viewer.
///
/// Ports the STRUCTURE of the desktop canvas in
/// `src/dbs_annotator/models/electrode_viewer.py` (paintEvent) with
/// simplified, even spacing:
/// - The CASE (ground) rect sits at the very top.
/// - Contact levels are stacked below it with E(numContacts-1) at the TOP and
///   E0 at the BOTTOM (the desktop reverses display order the same way).
/// - A ring (non-directional) level is one full-width rect.
/// - A directional level is three side-by-side cells (left/center/right =
///   segments a/b/c, planar like the desktop) plus a "ring cap" strip just
///   above the segments that cycles all three together.
///
/// No Flutter widgets here — only `dart:ui` geometry types — so everything is
/// unit-testable headlessly.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'electrode_model.dart';
import 'stimulation_rule.dart';

/// Default extra padding (px) applied around shapes during [hitTest], mirrors
/// the desktop's expanded clickable areas (QPainterPathStroker / ring pad).
const double kElectrodeTapPadding = 12.0;

/// Ring caps are thin strips; give them extra tap slack on top of the default.
const double kRingCapExtraTapPadding = 8.0;

/// Geometry of one contact level in display order.
class LevelLayout {
  const LevelLayout({
    required this.levelIdx,
    required this.isDirectional,
    required this.contactRects,
    this.ringCapRect,
  });

  /// Contact index (the `idx` in the `E{idx}` label), NOT the display row.
  final int levelIdx;

  /// Whether this level is segmented (three cells) or a ring (one rect).
  final bool isDirectional;

  /// One rect per contact: `{ContactKey(levelIdx, 0)}` for ring levels,
  /// `{ContactKey(levelIdx, 0|1|2)}` (a/b/c) for directional levels.
  final Map<ContactKey, Rect> contactRects;

  /// Tap zone above the segments of a directional level that cycles all
  /// three segments together. `null` for ring levels.
  final Rect? ringCapRect;
}

/// Full electrode layout: the case rect plus levels in display order
/// (top row first, i.e. `levels.first.levelIdx == numContacts - 1` and
/// `levels.last.levelIdx == 0`).
class ElectrodeLayout {
  const ElectrodeLayout({
    required this.caseRect,
    required this.leadRect,
    required this.levels,
  });

  /// CASE (ground) rect at the very top.
  final Rect caseRect;

  /// Lead body behind the contacts (painting only, never hit).
  final Rect leadRect;

  /// Levels in display order, top to bottom.
  final List<LevelLayout> levels;
}

/// Result of [hitTest]: which interactive shape (if any) contains a point.
sealed class ElectrodeHit {
  const ElectrodeHit();
}

/// The CASE (ground) rect was hit.
class CaseHit extends ElectrodeHit {
  const CaseHit();
}

/// A contact (ring level or one directional segment) was hit.
class ContactHit extends ElectrodeHit {
  const ContactHit(this.key);

  final ContactKey key;
}

/// The ring cap of directional level [levelIdx] was hit.
class RingCapHit extends ElectrodeHit {
  const RingCapHit(this.levelIdx);

  final int levelIdx;
}

/// Computes the electrode layout for [model] inside a canvas of [size].
///
/// Spacing is even (each level gets the same slot height) rather than
/// mm-accurate; ordering and structure match the desktop widget.
ElectrodeLayout computeLayout(ElectrodeModel model, Size size) {
  final n = model.numContacts;
  const pad = 8.0;

  // Vertical budget in abstract units: case + gap below case + n level slots
  // + (n - 1) inter-level gaps (the gaps also host the ring caps).
  const caseUnits = 0.9;
  const caseGapUnits = 0.7;
  const levelUnits = 1.0;
  const gapUnits = 0.45;
  final totalUnits =
      caseUnits + caseGapUnits + n * levelUnits + (n - 1) * gapUnits;
  final unit = math.max(1.0, size.height - 2 * pad) / totalUnits;

  // Lead centred slightly right of centre to leave room for the E-labels.
  final centerX = size.width * 0.55;
  final leadWidth = math.min(size.width * 0.34, unit * 3.0);

  final caseHeight = caseUnits * unit;
  final caseWidth = leadWidth * 1.4;
  final caseRect =
      Rect.fromLTWH(centerX - caseWidth / 2, pad, caseWidth, caseHeight);

  // Directional segment geometry, mirroring desktop proportions: the outer
  // segments extend past the lead, the centre segment 'b' is 0.55 lead-widths.
  final extension = leadWidth * 0.22;
  final fullWidth = leadWidth + 2 * extension;
  final bWidth = leadWidth * 0.55;
  const segGap = 2.0;

  final levelHeight = levelUnits * unit;
  final gap = gapUnits * unit;
  // Keep a comfortable minimum so the "Ring" cap isn't a hairline strip.
  final capHeight = math.max(gap * 0.8, 16.0);

  final levels = <LevelLayout>[];
  var y = caseRect.bottom + caseGapUnits * unit;
  for (var row = 0; row < n; row++) {
    // Display order is reversed: E(n-1) at the top, E0 at the bottom.
    final levelIdx = n - 1 - row;
    final directional = model.isDirectional && model.isLevelDirectional(levelIdx);

    if (directional) {
      final left = centerX - fullWidth / 2;
      final bLeft = centerX - bWidth / 2;
      final contactRects = <ContactKey, Rect>{
        // Segment 'a' (left).
        ContactKey(levelIdx, 0):
            Rect.fromLTRB(left, y, bLeft - segGap, y + levelHeight),
        // Segment 'b' (center).
        ContactKey(levelIdx, 1):
            Rect.fromLTRB(bLeft, y, bLeft + bWidth, y + levelHeight),
        // Segment 'c' (right).
        ContactKey(levelIdx, 2): Rect.fromLTRB(
            bLeft + bWidth + segGap, y, left + fullWidth, y + levelHeight),
      };
      final ringCapRect =
          Rect.fromLTWH(left, y - capHeight - 1, fullWidth, capHeight);
      levels.add(LevelLayout(
        levelIdx: levelIdx,
        isDirectional: true,
        contactRects: contactRects,
        ringCapRect: ringCapRect,
      ));
    } else {
      levels.add(LevelLayout(
        levelIdx: levelIdx,
        isDirectional: false,
        contactRects: <ContactKey, Rect>{
          ContactKey(levelIdx, 0): Rect.fromLTWH(
              centerX - leadWidth / 2, y, leadWidth, levelHeight),
        },
      ));
    }
    y += levelHeight + gap;
  }

  final leadTop = caseRect.bottom + caseGapUnits * unit;
  final leadBottom = y - gap;
  final leadRect = Rect.fromLTRB(
    centerX - leadWidth * 0.42,
    leadTop,
    centerX + leadWidth * 0.42,
    leadBottom,
  );

  return ElectrodeLayout(caseRect: caseRect, leadRect: leadRect, levels: levels);
}

/// Returns the interactive shape containing [pos], or `null`.
///
/// Precedence matches the desktop `mousePressEvent`: contacts first, then
/// ring caps, then the case. Every shape is inflated by [tapPadding] to make
/// touch targets generous.
ElectrodeHit? hitTest(
  ElectrodeLayout layout,
  Offset pos, {
  double tapPadding = kElectrodeTapPadding,
}) {
  for (final level in layout.levels) {
    for (final entry in level.contactRects.entries) {
      if (entry.value.inflate(tapPadding).contains(pos)) {
        return ContactHit(entry.key);
      }
    }
  }
  for (final level in layout.levels) {
    final cap = level.ringCapRect;
    if (cap != null &&
        cap.inflate(tapPadding + kRingCapExtraTapPadding).contains(pos)) {
      return RingCapHit(level.levelIdx);
    }
  }
  if (layout.caseRect.inflate(tapPadding).contains(pos)) {
    return const CaseHit();
  }
  return null;
}
