/// Pure layout math for the interactive electrode viewer.
///
/// Vertically mm-accurate, mirroring the desktop canvas in
/// `dbs_annotator/models/electrode_viewer.py`: every vertical dimension derives
/// from the model's real contact height, spacing and diameter in millimetres
/// times a single `scale` (px per mm). Before it was mm-based, Medtronic 3387
/// (1.5/1.5 mm), 3389 (1.5/0.5) and 3391 (3.0/4.0) all rendered identically.
///
/// The CASE rect sits at the top, then contact levels with E(numContacts-1)
/// first and E0 last, then a hemispherical tip (insulating polymer, or the
/// distal contact itself on `tipContact` models). A ring level is one
/// full-width rect; a directional level is three segment cells (a/b/c) plus a
/// "ring cap" strip above them that cycles all three together.
///
/// Paint-only shapes are exposed alongside the plain `Rect`s that drive
/// hit-testing, so the two never disagree.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'electrode_model.dart';
import 'stimulation_rule.dart';

/// Default extra padding (px) applied around shapes during [hitTest].
const double kElectrodeTapPadding = 12.0;

/// Ring caps are thin strips; give them extra tap slack on top of the default.
const double kRingCapExtraTapPadding = 8.0;

/// Upper bound on `scale` (px per mm) so a huge canvas does not render a
/// cartoonishly large lead. Higher than the desktop's 24, as these panes are
/// often taller.
const double kMaxScale = 44.0;

/// A directional segment narrower than this (logical px) is too small to tap
/// reliably, and raises the drawn lead width.
const double _minSegmentWidth = 24.0;

/// Width a directional lead needs so its three flush segments each clear
/// [_minSegmentWidth].
const double _minDirectionalWidth = 3 * _minSegmentWidth + 2 * _segGap;

/// Fixed (unscaled) pixel overhead above the case and below it.
const double _topPad = 8.0;
const double _caseGapPx = 14.0;

/// Left gutter reserved for the `E{idx}` labels, which sit outside the lead.
const double _labelGutter = 46.0;

/// Millimetre gap between the lead's top and its first contact.
const double _initialOffsetMm = 2.0;

/// A schematic marker for "stimulate against the can", not a scale drawing of a
/// 50 mm generator, so its height is FIXED: at 1.75 x the lead width it grew
/// with the lead and stole the height the contacts needed, leaving 36 px
/// contacts carrying 11 px labels. The width still tracks the lead.
const double _caseHeight = 34.0;
const double _caseWidthOfLead = 0.95;

/// Smallest drawn gap (px) between two metal bands, so a tightly-spaced lead
/// (Medtronic 3389: 0.5 mm) still shows daylight between its contacts. A pixel
/// floor, not the desktop's flat 1 mm added to EVERY gap: that inflation gives
/// 3387 (1.5/1.5 mm) and 3391 (3.0/4.0 mm) an identical 1:1.667 contact-to-gap
/// ratio, so two very different leads render as the same shape.
const double _minGapPx = 3.0;

/// Directional leads need a roomier gap, because it also hosts the "Ring" cap
/// strip plus [_capClearancePx] of clearance under the contact above.
const double _minGapDirectionalPx = 10.0;

/// Clearance kept between a ring cap and the contact above it. Without it the
/// cap grows to fill the gap and swallows the tap padding below that contact,
/// so a tap just under a segment selects the next level's cap instead.
const double _capClearancePx = 6.0;

/// Never draw a ring cap thinner than this, so it stays pressable on a cramped
/// pane.
const double _minCapHeight = 6.0;

/// Most of the segments' height the ring cap may claim. The gap alone cannot
/// give the cap a comfortable touch target, so it also takes a slice off the
/// TOP of the segments, capped here so the segments stay dominant.
const double _maxSegmentTakeover = 0.34;

/// Comfortable touch height for the "Ring" strip, tablet-first. Grows with the
/// lead so it stays proportionate on a large canvas instead of a hairline.
double _capTarget(double contactHeight) =>
    (contactHeight * 0.55).clamp(26.0, 42.0);

/// Geometry of one contact level in display order.
class LevelLayout {
  const LevelLayout({
    required this.levelIdx,
    required this.isDirectional,
    required this.contactRects,
    this.ringCapRect,
    this.isTip = false,
  });

  /// Contact index (the `idx` in the `E{idx}` label), NOT the display row.
  final int levelIdx;

  final bool isDirectional;

  /// One rect per contact, keyed `ContactKey(levelIdx, 0)` for a ring level and
  /// `ContactKey(levelIdx, 0|1|2)` (a/b/c) for a directional one. Plain
  /// bounding rects: the painter may draw a tapered shape inside them.
  final Map<ContactKey, Rect> contactRects;

  /// Tap zone above the segments that cycles all three together, null on a ring
  /// level.
  final Rect? ringCapRect;

  /// True when this level's contact IS the hemispherical lead tip (Boston
  /// `tipContact` models), so the painter draws a metal dome below the rect.
  final bool isTip;
}

/// Full electrode layout: the case rect plus levels in display order, so
/// `levels.first.levelIdx == numContacts - 1` and `levels.last.levelIdx == 0`.
class ElectrodeLayout {
  const ElectrodeLayout({
    required this.caseRect,
    required this.leadRect,
    required this.levels,
    required this.scale,
    required this.domeRect,
    required this.isTipContact,
  });

  final Rect caseRect;

  /// Lead body behind the contacts, painting only, never hit. Exactly the lead
  /// silhouette, so contacts sit flush with it, and the one rect the painter
  /// builds its cylinder shader from so body, contacts and dome share a light.
  final Rect leadRect;

  final List<LevelLayout> levels;

  /// Pixels per millimetre. Font sizes and stroke widths derive from this so
  /// they track the rendered lead size instead of being hard-coded.
  final double scale;

  /// The hemispherical tip below the distal contact: a square box whose top
  /// half-height is the dome. Insulating polymer, unless [isTipContact].
  final Rect domeRect;

  /// True when the distal contact IS the tip (Boston models), so the dome is
  /// metal and takes E0's state rather than being insulation.
  final bool isTipContact;
}

/// Result of [hitTest]: which interactive shape, if any, contains a point.
sealed class ElectrodeHit {
  const ElectrodeHit();
}

class CaseHit extends ElectrodeHit {
  const CaseHit();
}

/// A ring level or one directional segment.
class ContactHit extends ElectrodeHit {
  const ContactHit(this.key);

  final ContactKey key;
}

class RingCapHit extends ElectrodeHit {
  const RingCapHit(this.levelIdx);

  final int levelIdx;
}

/// Lead width (px), deliberately decoupled from the vertical mm scale.
///
/// Every lead in the catalogue is 1.27-1.30 mm across, so tying width to the
/// height-fitted scale made a widely-spaced model (3391) render as a visibly
/// thinner product than a tightly-spaced one (3389). Width comes from the pane
/// instead, with residual diameter differences honoured off
/// [_referenceDiameterMm]; [stackHeight] caps it so a short lead is not a stub.
double _leadWidthFor(
  ElectrodeModel model,
  Size size,
  double maxWidth,
  double stackHeight,
) {
  final target = (size.width * _widthOfPane).clamp(
    _minLeadWidth,
    _maxLeadWidth,
  );
  final diameterRatio = model.leadDiameter / _referenceDiameterMm;
  final ceiling = math.min(maxWidth, stackHeight * _maxWidthOfLength);

  // Two floors, both about legibility rather than proportion. Directional
  // segments must stay tappable, so that floor outranks the proportional
  // ceiling. And a lead with many levels must be WIDER: the levels share a
  // fixed pane height, so each contact gets shorter as their number grows and
  // cannot hold a readable label. Height cannot grow, so width does.
  final crowding = ((model.numContacts - _widthRampFrom) * _widthPerExtraLevel)
      .clamp(0.0, _maxCrowdingWidth);
  final floor = math.min(
    maxWidth,
    math.max(
      model.isDirectional ? _minDirectionalWidth : 0.0,
      crowding > 0 ? _minLeadWidth + crowding : 0.0,
    ),
  );
  return math.max(math.min(target * diameterRatio, ceiling), floor);
}

/// Lead width as a fraction of the pane, and its absolute bounds (logical px).
const double _widthOfPane = 0.26;
const double _minLeadWidth = 34.0;
const double _maxLeadWidth = 104.0;

/// The diameter [_widthOfPane] is calibrated for; other leads scale off it.
const double _referenceDiameterMm = 1.27;

/// Cap on lead width as a fraction of the contact stack's drawn length.
const double _maxWidthOfLength = 0.55;

/// Contact count at which the crowding width bonus starts. Four levels is the
/// common case (Medtronic, Abbott, ALEVA) and needs no help.
const int _widthRampFrom = 4;

/// Extra width per level beyond [_widthRampFrom], and the cap on that bonus.
/// This is what keeps a 10 px label inside a contact the vertical budget has
/// squeezed: a six-level Cartesia gains 18 px, an eight-ring Vercise all 30.
const double _widthPerExtraLevel = 9.0;
const double _maxCrowdingWidth = 30.0;

const double _segGap = 2.0;

/// Computes the electrode layout for [model] inside a canvas of [size].
///
/// Vertical spacing is mm-accurate, capped at [kMaxScale], and centred so a
/// capped scale does not strand the drawing at the top. Lead WIDTH is
/// deliberately pane-driven instead (see [_leadWidthFor]).
ElectrodeLayout computeLayout(ElectrodeModel model, Size size) {
  final n = model.numContacts;

  final availW = math.max(1.0, size.width - _labelGutter - 8);
  final maxLeadWidth = availW;
  // Reserves the dome's pixel height before the scale is known. The final width
  // can only shrink from here (the proportional ceiling) and a smaller lead
  // means a shorter dome, so the reservation below can never be too small.
  final provisionalWidth = _leadWidthFor(model, size, maxLeadWidth, 1e9);

  // Only the LEAD is mm-scaled: initial offset, n contacts, n-1 inflated gaps.
  // The case and the tip dome are sized off the lead width and so reserved as
  // fixed pixels. Scaling the case by mm shrank it to a stub on a short pane,
  // where the lead width has a tappability floor and stayed full width.
  final gaps = n - 1;
  final bandsMm = _initialOffsetMm + n * model.contactHeight;

  final fixedPx = _topPad + _caseHeight + _caseGapPx + provisionalWidth / 2;
  final availH = math.max(1.0, size.height - fixedPx - 2);

  // Fit true millimetres first. If that squeezes a gap below the floor, re-fit
  // with the gaps pinned there instead and let the contacts take the remaining
  // height; only tightly-spaced models are affected.
  final minGap = model.isDirectional ? _minGapDirectionalPx : _minGapPx;
  final trueScale = availH / (bandsMm + gaps * model.contactSpacing);
  final scale = math.min(
    model.contactSpacing * trueScale >= minGap
        ? trueScale
        : math.max(1.0, availH - gaps * minGap) / bandsMm,
    kMaxScale,
  );

  final contactHeight = model.contactHeight * scale;
  final gapPx = math.max(model.contactSpacing * scale, minGap);
  final pitch = contactHeight + gapPx;
  final stackHeight = n * contactHeight + gaps * gapPx;

  final leadWidth = _leadWidthFor(model, size, maxLeadWidth, stackHeight);
  // Segments are FLUSH with the lead, as real segmented contacts are. The
  // desktop flares them 0.22 lead-widths past the silhouette to keep the side
  // segments visible, but with a pane-driven width all three already clear
  // [_minSegmentWidth], so the flare only costs the clean cylinder.
  final segWidth = (leadWidth - 2 * _segGap) / 3;
  final centerX = _labelGutter + (size.width - _labelGutter) / 2;
  final domeHeight = leadWidth / 2;

  // The cap takes whatever the gap can spare, keeping [_capClearancePx] free
  // under the contact above, then tops that up from the TOP of the segments.
  // Derived from the gap rather than a fixed floor that could exceed it and
  // paint over the level above, and kept short so the CONTACTS stay dominant.
  final capFromGap = math.max(gapPx - _capClearancePx, 0.0);
  final capTakeover = (_capTarget(contactHeight) - capFromGap).clamp(
    0.0,
    contactHeight * _maxSegmentTakeover,
  );

  const caseHeight = _caseHeight;
  final drawnHeight = fixedPx + _initialOffsetMm * scale + stackHeight;
  final top = _topPad + math.max(0.0, (size.height - drawnHeight) / 2);

  final caseWidth = leadWidth * _caseWidthOfLead;
  final caseRect = Rect.fromLTWH(
    centerX - caseWidth / 2,
    top,
    caseWidth,
    caseHeight,
  );

  final leadTop = caseRect.bottom + _caseGapPx;
  var y = leadTop + _initialOffsetMm * scale;

  final levels = <LevelLayout>[];
  for (var row = 0; row < n; row++) {
    // Display order is reversed: E(n-1) at the top, E0 at the bottom.
    final levelIdx = n - 1 - row;
    final directional =
        model.isDirectional && model.isLevelDirectional(levelIdx);
    final isTip = levelIdx == 0 && model.tipContact;

    if (directional) {
      final left = centerX - leadWidth / 2;
      final bottom = y + contactHeight;
      final segTop = y + capTakeover;
      // Three equal segments, parted by gaps that show the polymer body
      // beneath, which is what the real gaps are.
      final contactRects = <ContactKey, Rect>{
        ContactKey(levelIdx, 0): Rect.fromLTRB(
          left,
          segTop,
          left + segWidth,
          bottom,
        ),
        ContactKey(levelIdx, 1): Rect.fromLTRB(
          left + segWidth + _segGap,
          segTop,
          left + 2 * segWidth + _segGap,
          bottom,
        ),
        ContactKey(levelIdx, 2): Rect.fromLTRB(
          left + 2 * (segWidth + _segGap),
          segTop,
          left + leadWidth,
          bottom,
        ),
      };
      // Spans the level exactly, so `cap.left == a.left` and
      // `cap.right == c.right` are identities, and ends a hairline above the
      // segments so `cap.bottom <= a.top` holds.
      final capBottom = segTop - 1;
      final ringCapRect = Rect.fromLTRB(
        left,
        math.min(y - capFromGap, capBottom - _minCapHeight),
        left + leadWidth,
        capBottom,
      );
      levels.add(
        LevelLayout(
          levelIdx: levelIdx,
          isDirectional: true,
          contactRects: contactRects,
          ringCapRect: ringCapRect,
        ),
      );
    } else {
      levels.add(
        LevelLayout(
          levelIdx: levelIdx,
          isDirectional: false,
          contactRects: <ContactKey, Rect>{
            ContactKey(levelIdx, 0): Rect.fromLTWH(
              centerX - leadWidth / 2,
              y,
              leadWidth,
              contactHeight,
            ),
          },
          isTip: isTip,
        ),
      );
    }
    y += pitch;
  }

  // The exact silhouette, so contacts sit flush with it. On tipContact models
  // the body stops at the distal contact's top, because that contact plus its
  // dome finishes the lead.
  final distal = levels.last.contactRects.values.first;
  final leadBottom = model.tipContact ? distal.top : distal.bottom;
  final leadRect = Rect.fromLTRB(
    centerX - leadWidth / 2,
    leadTop,
    centerX + leadWidth / 2,
    leadBottom,
  );

  // A square box whose lower half is the visible hemisphere, radius
  // leadWidth/2.
  final domeRect = Rect.fromLTWH(
    centerX - leadWidth / 2,
    distal.bottom - domeHeight,
    leadWidth,
    domeHeight * 2,
  );

  return ElectrodeLayout(
    caseRect: caseRect,
    leadRect: leadRect,
    levels: levels,
    scale: scale,
    domeRect: domeRect,
    isTipContact: model.tipContact,
  );
}

/// Returns the interactive shape containing [pos], or `null`.
///
/// Precedence is evaluated level by level, top to bottom, and within a level
/// the ring cap is tested before that level's own segments.
///
/// With mm-accurate spacing a ring cap can be only a few pixels tall (a
/// 6-contact lead in a 320 px pane), and the desktop's "all contacts anywhere
/// first" order let a neighbouring level's inflated rect swallow the cap band
/// entirely, making the cycle-all-three affordance unreachable, and silently,
/// since the tap still landed on *a* contact. Two rules prevent that: a cap's
/// tap zone never extends below its own bottom edge, so it cannot steal taps
/// aimed at the segments under it, and levels are walked top-down, so the level
/// above always wins the space between it and the cap.
ElectrodeHit? hitTest(
  ElectrodeLayout layout,
  Offset pos, {
  double tapPadding = kElectrodeTapPadding,
}) {
  // Pass 1: exact hits, no padding. Contacts and caps never overlap, so a point
  // inside a drawn shape is unambiguous and tapping a pixel does what that
  // pixel looks like it does. Pass 2 then only rescues near-misses.
  for (final level in layout.levels) {
    for (final entry in level.contactRects.entries) {
      if (entry.value.contains(pos)) return ContactHit(entry.key);
    }
    final exact = level.ringCapRect;
    if (exact != null && exact.contains(pos)) {
      return RingCapHit(level.levelIdx);
    }
  }

  // Pass 2: padded, generous touch targets.
  for (final level in layout.levels) {
    final cap = level.ringCapRect;
    if (cap != null) {
      final pad = tapPadding + kRingCapExtraTapPadding;
      // Grow up/left/right for reachability, but never down into the segments.
      final zone = Rect.fromLTRB(
        cap.left - pad,
        cap.top - pad,
        cap.right + pad,
        cap.bottom,
      );
      if (zone.contains(pos)) return RingCapHit(level.levelIdx);
    }
    // Padded zones on adjacent segments overlap, so pick the NEAREST shape
    // rather than the first iterated; first-match biased every seam tap
    // leftwards. Distance is to the un-inflated rect, so a point inside a real
    // contact always wins at 0.
    ContactKey? best;
    var bestDist = double.infinity;
    for (final entry in level.contactRects.entries) {
      if (!entry.value.inflate(tapPadding).contains(pos)) continue;
      final d = _distanceToRect(pos, entry.value);
      if (d < bestDist) {
        bestDist = d;
        best = entry.key;
      }
    }
    if (best != null) return ContactHit(best);
  }
  if (layout.caseRect.inflate(tapPadding).contains(pos)) {
    return const CaseHit();
  }
  return null;
}

/// Euclidean distance from [p] to the nearest point of [r] (0 when inside).
double _distanceToRect(Offset p, Rect r) {
  final dx = math.max(math.max(r.left - p.dx, p.dx - r.right), 0.0);
  final dy = math.max(math.max(r.top - p.dy, p.dy - r.bottom), 0.0);
  return math.sqrt(dx * dx + dy * dy);
}
