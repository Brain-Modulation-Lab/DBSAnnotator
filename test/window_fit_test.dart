import 'package:dbs_annotator/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real work areas (logical px, i.e. after DPI scaling) that a clinician might
/// launch on. The last two are the cases that used to break: a small laptop, and
/// a high-DPI panel whose LOGICAL resolution is small even though the physical
/// one is large.
const _workAreas = <String, Size>{
  '4K desktop @100%': Size(3840, 2120),
  '1080p desktop @100%': Size(1920, 1032),
  '1080p laptop @150%': Size(1280, 672),
  '1366x768 laptop': Size(1366, 728),
  '1280x800 @125%': Size(1024, 552),
  'netbook 1024x600': Size(1024, 552),
  'tiny 800x600': Size(800, 552),
};

void main() {
  group('fitWindowRect', () {
    _workAreas.forEach((name, work) {
      test('fits entirely inside the work area: $name', () {
        final r = fitWindowRect(work: work);

        // The whole point: never larger than the screen can show.
        expect(r.width, lessThanOrEqualTo(work.width),
            reason: 'wider than the work area');
        expect(r.height, lessThanOrEqualTo(work.height),
            reason: 'taller than the work area — this is what hid the title '
                'bar and the taskbar');
        // And fully within it, so the title bar can be grabbed.
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.top, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(work.width + 0.01));
        expect(r.bottom, lessThanOrEqualTo(work.height + 0.01));
        // Still usable.
        expect(r.width, greaterThan(300));
        expect(r.height, greaterThan(300));
      });
    });

    test('honours a multi-monitor work-area origin', () {
      // A second display to the right of a 1920-wide primary.
      final r = fitWindowRect(
          work: const Size(1280, 700), workOrigin: const Offset(1920, 0));
      expect(r.left, greaterThanOrEqualTo(1920));
      expect(r.right, lessThanOrEqualTo(1920 + 1280.01));
    });

    test('uses the preferred size when the display is roomy', () {
      final r = fitWindowRect(work: const Size(3840, 2120));
      expect(r.size, const Size(1500, 950));
    });

    test('centres the window', () {
      final r = fitWindowRect(work: const Size(1920, 1032));
      expect(r.center.dx, closeTo(960, 0.01));
      expect(r.center.dy, closeTo(516, 0.01));
    });

    test('degrades sanely on an absurdly small work area', () {
      final r = fitWindowRect(work: const Size(200, 150));
      expect(r.width, lessThanOrEqualTo(200));
      expect(r.height, lessThanOrEqualTo(150));
      expect(r.width, greaterThan(0));
      expect(r.height, greaterThan(0));
    });
  });

  group('fitMinimumSize', () {
    test('never exceeds the window it is applied to', () {
      // A minimum larger than the screen is what makes an oversized window
      // impossible to shrink, so this must clamp.
      for (final work in _workAreas.values) {
        final bounds = fitWindowRect(work: work);
        final min = fitMinimumSize(bounds.size);
        expect(min.width, lessThanOrEqualTo(bounds.width));
        expect(min.height, lessThanOrEqualTo(bounds.height));
      }
    });

    test('keeps the full minimum when there is room', () {
      expect(fitMinimumSize(const Size(1500, 950)), const Size(640, 520));
    });
  });
}
