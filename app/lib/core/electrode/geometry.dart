/// Pure layout math for the interactive electrode viewer.
///
/// Mirrors the desktop canvas in `src/dbs_annotator/models/electrode_viewer.py`
/// (`calculate_scale` + `paintEvent`) and, like it, is **mm-accurate**: every
/// vertical dimension derives from the model's real `contactHeight` /
/// `contactSpacing` / `leadDiameter` in millimetres times a single `scale`
/// (px per mm). That is what makes physically different leads look different —
/// e.g. Medtronic 3387 (1.5/1.5 mm), 3389 (1.5/0.5) and 3391 (3.0/4.0) all
/// rendered identically before this was mm-based.
///
/// Structure:
/// - The CASE (ground) rect sits at the very top.
/// - Contact levels stack below it with E(numContacts-1) at the TOP and E0 at
///   the BOTTOM (the desktop reverses display order the same way).
/// - A ring (non-directional) level is one full-lead-width rect.
/// - A directional level is three side-by-side cells (left/center/right =
///   segments a/b/c, planar like the desktop) plus a "ring cap" strip just
///   above the segments that cycles all three together.
/// - The lead ends in a hemispherical tip: an insulating polymer dome, or —
///   for `tipContact` models (Boston) — the distal contact itself.
///
/// No Flutter widgets here — only `dart:ui` geometry types — so everything is
/// unit-testable headlessly. Shapes needed only for painting (segment
/// trapezoids, the dome) are exposed alongside the plain `Rect`s that drive
/// hit-testing, so the two never disagree.
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

/// Upper bound on `scale` (px per mm) so a huge canvas doesn't render a
/// cartoonishly large lead. The desktop caps at 24 interactive / 80 export
/// (`electrode_viewer.py:108`); we allow more because the Flutter panes are
/// often taller.
const double kMaxScale = 44.0;

/// A directional segment narrower than this (logical px) is too small to tap
/// reliably, and raises the drawn lead width.
const double _minSegmentWidth = 24.0;

/// Width a directional lead needs so its three flush segments each clear
/// [_minSegmentWidth].
const double _minDirectionalWidth =
    3 * _minSegmentWidth + 2 * _segGap;

/// Fixed (unscaled) pixel overhead, mirroring the desktop's `top_padding` and
/// `lead_gap` (`electrode_viewer.py:95-99`).
const double _topPad = 8.0;
const double _caseGapPx = 14.0;

/// Left gutter reserved for the `E{idx}` labels, which sit outside the lead.
const double _labelGutter = 46.0;

/// Millimetre gap between the lead's top and its first contact
/// (`electrode_viewer.py:101-103`).
const double _initialOffsetMm = 2.0;

/// The CASE (IPG can) is schematic, so it is sized off the drawn lead width
/// rather than in millimetres — see the budget in [computeLayout].
const double _caseHeightOfWidth = 1.75;
const double _caseWidthOfLead = 0.95;

/// Smallest drawn gap (px) between two metal bands, so a tightly-spaced lead
/// (Medtronic 3389: 0.5 mm) still shows daylight between its contacts.
///
/// This replaces the desktop's trick of adding a flat 1 mm to EVERY gap
/// (`electrode_viewer.py:792`). That inflation distorts proportions, and badly:
/// it makes 3387 (1.5/1.5 mm) and 3391 (3.0/4.0 mm) come out at an identical
/// contact:gap ratio of 1:1.667, so two very different leads render the same
/// shape — exactly the flaw this round set out to remove. A pixel floor keeps
/// generously-spaced models perfectly true and only intervenes where a gap
/// would otherwise vanish.
const double _minGapPx = 3.0;

/// Directional leads need a roomier minimum gap, because the gap also hosts the
/// "Ring" cap strip plus [_capClearancePx] of clearance beneath the contact
/// above it.
const double _minGapDirectionalPx = 10.0;

/// Clearance kept between a ring cap and the contact above it. Without it the
/// cap grows to fill the gap and swallows the tap padding below that contact,
/// so a tap just under a segment selects the next level's cap instead.
const double _capClearancePx = 6.0;

/// Never draw a ring cap thinner than this, so it stays a visible, pressable
/// strip even on a cramped pane.
const double _minCapHeight = 6.0;

/// Most of the segments' height the ring cap may claim. The inter-level gap
/// alone cannot give the cap a comfortable touch target, so it also takes a
/// slice off the TOP of the segments — capped here so the segments always keep
/// the clear majority of the level and stay the dominant shapes.
const double _maxSegmentTakeover = 0.34;

/// Comfortable touch height for the "Ring" strip, tablet-first (the platform
/// guidance is ~44 px for a touch target, and [kElectrodeTapPadding] adds more
/// on top of the drawn strip). Grows with the lead so it stays proportionate on
/// a large desktop canvas instead of looking like a hairline.
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

  /// Whether this level is segmented (three cells) or a ring (one rect).
  final bool isDirectional;

  /// One rect per contact: `{ContactKey(levelIdx, 0)}` for ring levels,
  /// `{ContactKey(levelIdx, 0|1|2)}` (a/b/c) for directional levels.
  ///
  /// These are the plain bounding rects that drive [hitTest]; the painter may
  /// draw a tapered shape inside them (see [segmentInset]).
  final Map<ContactKey, Rect> contactRects;

  /// Tap zone above the segments of a directional level that cycles all
  /// three segments together. `null` for ring levels.
  final Rect? ringCapRect;

  /// True when this level's contact IS the hemispherical lead tip (Boston
  /// `tipContact` models): the painter draws a metal dome below the rect.
  final bool isTip;
}

/// Full electrode layout: the case rect plus levels in display order
/// (top row first, i.e. `levels.first.levelIdx == numContacts - 1` and
/// `levels.last.levelIdx == 0`).
class ElectrodeLayout {
  const ElectrodeLayout({
    required this.caseRect,
    required this.leadRect,
    required this.levels,
    required this.scale,
    required this.domeRect,
    required this.isTipContact,
  });

  /// CASE (ground) rect at the very top.
  final Rect caseRect;

  /// Lead body behind the contacts (painting only, never hit). Exactly the
  /// lead silhouette, so contacts sit flush with it — and the single rect the
  /// painter builds its shared cylinder shader from, so body, contacts and
  /// dome are all lit by one light.
  final Rect leadRect;

  /// Levels in display order, top to bottom.
  final List<LevelLayout> levels;

  /// Pixels per millimetre. Font sizes and stroke widths derive from this so
  /// they track the rendered lead size instead of being hard-coded.
  final double scale;

  /// The hemispherical tip below the distal contact: a square box whose top
  /// half-height is the dome. Insulating polymer, unless [isTipContact].
  final Rect domeRect;

  /// True when the distal contact IS the tip (Boston models): the dome is
  /// metal and takes E0's state, rather than being insulation.
  final bool isTipContact;
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

/// Lead width (px).
///
/// Deliberately **decoupled from the vertical mm scale**. Every lead in the
/// catalogue is 1.27-1.30 mm across — physically the same — so tying width to
/// the height-fitted scale made a widely-spaced model (3391, 4 mm spacing, small
/// scale) render as a visibly *thinner product* than a tightly-spaced one
/// (3389), which is simply wrong. Width therefore comes from the pane, and only
/// the vertical dimensions (contact height, spacing, tip) stay mm-accurate.
///
/// The residual diameter differences are still honoured, scaled off
/// [_referenceDiameterMm] — a 1.30 mm Boston lead comes out ~2 % fatter than a
/// 1.27 mm Medtronic one, which is exactly how much it should be.
///
/// [maxWidth] is what the canvas can spare horizontally; [stackHeight] is the
/// drawn length of the contact stack, which caps the width proportionally so a
/// short lead never reads as a fat stub.
double _leadWidthFor(
  ElectrodeModel model,
  Size size,
  double maxWidth,
  double stackHeight,
) {
  final target = (size.width * _widthOfPane).clamp(_minLeadWidth, _maxLeadWidth);
  final diameterRatio = model.leadDiameter / _referenceDiameterMm;
  final ceiling = math.min(maxWidth, stackHeight * _maxWidthOfLength);
  // Directional segments must stay tappable; that floor outranks the
  // proportional ceiling, since an untappable segment is useless.
  final floor = model.isDirectional
      ? math.min(_minDirectionalWidth, maxWidth)
      : 0.0;
  return math.max(math.min(target * diameterRatio, ceiling), floor);
}

/// Lead width as a fraction of the pane, and its absolute bounds (logical px).
const double _widthOfPane = 0.26;
const double _minLeadWidth = 34.0;
const double _maxLeadWidth = 104.0;

/// The diameter that [_widthOfPane] is calibrated for; other leads scale off it.
const double _referenceDiameterMm = 1.27;

/// Lead width may not exceed this fraction of the contact stack's drawn length,
/// so the lead always reads as a slender probe.
const double _maxWidthOfLength = 0.55;

const double _segGap = 2.0;

/// Computes the electrode layout for [model] inside a canvas of [size].
///
/// Vertical spacing is mm-accurate — `scale` (px per mm) comes from the model's
/// real contact height and spacing, capped at [kMaxScale], and the drawing is
/// centred vertically so a capped scale doesn't strand it at the top. Lead
/// WIDTH is deliberately pane-driven instead (see [_leadWidthFor]).
ElectrodeLayout computeLayout(ElectrodeModel model, Size size) {
  final n = model.numContacts;

  // --- Widths (independent of the vertical scale) ---------------------------
  final availW = math.max(1.0, size.width - _labelGutter - 8);
  final maxLeadWidth = availW;
  // Provisional width, used only to reserve the dome's pixel height before the
  // scale is known. The final width can only shrink from here (the proportional
  // ceiling), and a smaller lead means a shorter dome, so the reservation below
  // can never be too small — which is exactly the overflow the desktop has
  // (it reserves 0.3 mm of tail but draws a leadWidth/2 tip:
  // electrode_viewer.py:101-103 vs :660).
  final provisionalWidth = _leadWidthFor(model, size, maxLeadWidth, 1e9);

  // --- Vertical budget ------------------------------------------------------
  // Only the LEAD is mm-scaled: initial offset + n contacts + (n-1) inflated
  // gaps. The CASE and the tip dome are sized off the lead width instead, and
  // so are reserved as fixed pixels.
  //
  // The case is schematic — a real IPG is ~50 mm, nothing like the 4 mm the
  // desktop scales it by — so tying it to the drawn lead width keeps the can a
  // constant, recognisable shape. Scaling it by mm made it shrink to a stub on
  // a short pane (where the lead width has a tappability floor) while the lead
  // stayed full width.
  final gaps = n - 1;
  final bandsMm = _initialOffsetMm + n * model.contactHeight;

  final fixedPx = _topPad +
      provisionalWidth * _caseHeightOfWidth +
      _caseGapPx +
      provisionalWidth / 2;
  final availH = math.max(1.0, size.height - fixedPx - 2);

  // Fit true millimetres first. If that would squeeze a gap below
  // [_minGapPx], re-fit with the gaps pinned at that floor instead — the
  // contacts then take the remaining height, and only the tightly-spaced
  // models are affected.
  final minGap =
      model.isDirectional ? _minGapDirectionalPx : _minGapPx;
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
  // Segments are FLUSH with the lead: real segmented contacts are the same
  // diameter as the lead, separated by thin bands of the same insulating
  // polymer. The desktop instead flares them 0.22 lead-widths past the
  // silhouette (electrode_viewer.py:453, :562-603) to keep the side segments
  // visible — but with a pane-driven width all three already clear
  // [_minSegmentWidth], so the flare buys nothing and costs the clean
  // cylinder: it renders as a bolted-on collar at every segmented level.
  final segWidth = (leadWidth - 2 * _segGap) / 3;
  final centerX = _labelGutter + (size.width - _labelGutter) / 2;
  final domeHeight = leadWidth / 2;

  // Ring cap: a slim strip in the gap above the segments. Kept deliberately
  // shorter than the desktop's 0.8 contact-heights so the CONTACTS stay the
  // dominant shapes — on a Cartesia (five segmented levels) a tall cap turns
  // the lead into a stack of buttons. Derived from the gap, not a fixed px
  // floor that could exceed it and paint over the level above.
  // Ring-cap sizing, tablet-first: the strip takes whatever the inter-level gap
  // can spare (keeping [_capClearancePx] free under the contact above), and
  // tops that up by claiming a slice off the TOP of the segments until it
  // reaches a comfortable touch height.
  final capFromGap = math.max(gapPx - _capClearancePx, 0.0);
  final capTakeover = (_capTarget(contactHeight) - capFromGap)
      .clamp(0.0, contactHeight * _maxSegmentTakeover);

  // --- Vertical placement, centred -----------------------------------------
  final caseHeight = leadWidth * _caseHeightOfWidth;
  final drawnHeight =
      fixedPx + _initialOffsetMm * scale + stackHeight;
  final top = _topPad + math.max(0.0, (size.height - drawnHeight) / 2);

  final caseWidth = leadWidth * _caseWidthOfLead;
  final caseRect =
      Rect.fromLTWH(centerX - caseWidth / 2, top, caseWidth, caseHeight);

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
      // Segments start below the slice the ring cap claims.
      final segTop = y + capTakeover;
      // Three equal segments across the lead, parted by insulation gaps that
      // show the polymer body beneath — which is what the real gaps are.
      final contactRects = <ContactKey, Rect>{
        // Segment 'a' (left).
        ContactKey(levelIdx, 0):
            Rect.fromLTRB(left, segTop, left + segWidth, bottom),
        // Segment 'b' (center).
        ContactKey(levelIdx, 1): Rect.fromLTRB(left + segWidth + _segGap, segTop,
            left + 2 * segWidth + _segGap, bottom),
        // Segment 'c' (right).
        ContactKey(levelIdx, 2): Rect.fromLTRB(
            left + 2 * (segWidth + _segGap), segTop, left + leadWidth, bottom),
      };
      // Spans the level exactly, so `cap.left == a.left` and
      // `cap.right == c.right` are identities rather than coincidences, and
      // ends a hairline above the segments so `cap.bottom <= a.top` holds.
      final capBottom = segTop - 1;
      final ringCapRect = Rect.fromLTRB(
        left,
        math.min(y - capFromGap, capBottom - _minCapHeight),
        left + leadWidth,
        capBottom,
      );
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
          ContactKey(levelIdx, 0):
              Rect.fromLTWH(centerX - leadWidth / 2, y, leadWidth, contactHeight),
        },
        isTip: isTip,
      ));
    }
    y += pitch;
  }

  // Lead body = the exact silhouette, so contacts sit flush with it. For
  // tipContact models the body stops at the distal contact's top, because the
  // contact plus its dome finishes the lead (desktop: electrode_viewer.py:386).
  final distal = levels.last.contactRects.values.first;
  final leadBottom = model.tipContact ? distal.top : distal.bottom;
  final leadRect = Rect.fromLTRB(
    centerX - leadWidth / 2,
    leadTop,
    centerX + leadWidth / 2,
    leadBottom,
  );

  // The dome hangs below the distal contact; a square box whose lower half is
  // the visible hemisphere of radius leadWidth/2.
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
/// Precedence follows the desktop `mousePressEvent` (contacts, ring caps, then
/// case) but is evaluated **level by level, top to bottom**, and within a level
/// the ring cap is tested before that level's own segments.
///
/// Why: with mm-accurate spacing a ring cap can be only a few pixels tall (a
/// 6-contact lead in a 320 px pane), and the desktop's "all contacts anywhere
/// first" order let a neighbouring level's inflated rect swallow the cap band
/// entirely — the "cycle all three segments" affordance became unreachable, and
/// silently, since the tap still landed on *a* contact. Two rules make it
/// robust for every catalogue model:
///
///  * the cap's generous tap zone never extends **below** its own bottom edge,
///    so it cannot steal taps aimed at the segments underneath it;
///  * levels are walked top-down, so the level above always wins the space
///    between it and the cap.
ElectrodeHit? hitTest(
  ElectrodeLayout layout,
  Offset pos, {
  double tapPadding = kElectrodeTapPadding,
}) {
  // Pass 1 — EXACT hits, no padding. Contacts and caps never overlap (a cap's
  // bottom is above its level's top), so a point inside a drawn shape is
  // unambiguous: tapping a pixel always does what that pixel looks like it
  // does. Padding below only ever rescues near-misses, and can no longer let a
  // neighbouring level's slack swallow a shape outright.
  for (final level in layout.levels) {
    for (final entry in level.contactRects.entries) {
      if (entry.value.contains(pos)) return ContactHit(entry.key);
    }
    final exact = level.ringCapRect;
    if (exact != null && exact.contains(pos)) {
      return RingCapHit(level.levelIdx);
    }
  }

  // Pass 2 — padded, generous touch targets.
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
    // Generous tap zones on adjacent segments overlap, so pick the NEAREST
    // shape rather than the first one iterated. Distance is measured to the
    // un-inflated rect, so a point inside a real contact always wins (distance
    // 0) and a tap in the seam between two segments goes to the closer one —
    // the old first-match order silently biased every seam tap leftwards.
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
