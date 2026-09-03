/// Generates the screenshots used in `docs/`.
///
/// Opt-in: a plain `flutter test` skips this. To regenerate, from the repo root:
///
/// ```powershell
/// $env:DOCS_SCREENSHOT_DIR = "docs/_static/screenshots"
/// flutter test test/docs/screenshots_test.dart
/// ```
///
/// ## Why widget tests rather than a driven app
///
/// `RenderRepaintBoundary.toImage` needs no display, so this runs in CI on a
/// headless runner and needs no device, no emulator and no `flutter_driver`.
/// The output is committed, because Read the Docs cannot run Flutter.
///
/// ## Three traps, all of which produce a plausible-looking wrong result
///
/// 1. `toImage()` **never completes** under the widget-test fake clock. Both it
///    and `toByteData` must run inside `tester.runAsync`.
/// 2. `flutter_tester` ships **no fonts**. Text falls back to the engine's test
///    font, which draws every glyph as a filled black box — and the capture
///    still "succeeds". Real fonts have to be registered with [FontLoader],
///    including the Material *icon* font, or the home screen is a grid of boxes.
/// 3. The test binding sets `debugDisableShadows = true` for golden
///    determinism, so Material elevation renders flat.
///
/// ## Two rules every capture follows
///
/// **Never hand-pick a height.** The previous harness named a surface size as a
/// constant per capture, and three of them cut through a widget — a step label,
/// a step circle, the ratings list above the Insert button. [_shootFitted] and
/// [_shootRegion] measure the laid-out content and size the window to it, so a
/// layout change moves the frame instead of cropping it.
///
/// **Never photograph an empty form.** A screenshot of a blank Patient ID,
/// "Select program" and seven ratings reading 0.00 documents nothing. Every
/// capture is seeded first — the `_seed*` helpers here are the Dart
/// counterparts of the v0.4.0 Qt harness's `configure_stimulation` and
/// `fill_step3_session_scale_values`.
library;

import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui;

import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/electrode/geometry.dart';
import 'package:dbs_annotator/core/electrode/stimulation_rule.dart';
import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/core/session/scale_presets.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/report/report_sections.dart';
import 'package:dbs_annotator/ui/annotations_screen.dart';
import 'package:dbs_annotator/ui/electrode_view.dart';
import 'package:dbs_annotator/ui/home_screen.dart';
import 'package:dbs_annotator/ui/longitudinal_screen.dart';
import 'package:dbs_annotator/ui/painter_font.dart';
import 'package:dbs_annotator/ui/report_sections_dialog.dart';
import 'package:dbs_annotator/ui/scale_slider.dart';
import 'package:dbs_annotator/ui/session/entry_charts_view.dart';
import 'package:dbs_annotator/ui/session_screen.dart';
import 'package:dbs_annotator/ui/single_session_report_screen.dart';
import 'package:dbs_annotator/ui/stim_params_form.dart';
import 'package:dbs_annotator/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// Where PNGs are written. Unset means "do nothing", so the default
/// `flutter test` never dirties the working tree.
final String? _outDir = Platform.environment['DOCS_SCREENSHOT_DIR'];

const _boundary = ValueKey('docs-screenshot');

/// Resolved once in `setUpAll`; applied to every capture's theme.
String? _textFont;

/// The two canvas widths every capture uses.
///
/// One number per layout, not one per screenshot: mixed widths (the previous
/// harness used 1120, 1280 and 1500) render at different apparent scales on the
/// same documentation page, which reads as sloppiness rather than as detail.
///
/// [_wide] is above the 900 px breakpoint in `session_screen.dart`, so the
/// two-row layout the docs describe is what gets drawn. [_narrow] is below it,
/// and is also the width for screens whose own content is capped — the home
/// screen's card column is 600 px, so a wider canvas is mostly background.
const double _wide = 1440;
const double _narrow = 900;

/// The tallest window a capture may use before it has to become a region.
///
/// Anything taller renders as an illegible sliver at documentation width. The
/// recording step is ~4800 px once its review charts and entries table are laid
/// out, which is why that step is captured in three parts.
const double _maxHeight = 3000;

/// Device pixels of background kept below the last painted row when a capture
/// is trimmed. 32 device pixels is 16 logical, which reads as a margin rather
/// than as a crop that clipped something.
const int _trimMargin = 32;

// ---------------------------------------------------------------------------
// The demo session
//
// One consistent patient across every capture, so the screenshots read as one
// session rather than as unrelated fragments: sub-01, run 01, an OCD scale set,
// a segmented Medtronic lead with current steered across two segments.
// ---------------------------------------------------------------------------

const _fixture =
    'test/fixtures/sub-01_ses-20260626_task-programming_run-01_beh.tsv';
const _defaultModel = 'Medtronic SenSight B33005';
const _subjectId = '01';
const _runId = '01';
const _preset = 'OCD';
const _frequency = '125';
const _amplitude = '5.5';
const _pulseWidth = '90';
const _initialNotes =
    'Baseline on admission settings. Medication unchanged since last visit.';
const _sideEffects = 'Transient paraesthesia in the right hand at 5.5 mA.';
const _recordingNotes =
    'Noticeably less checking behaviour; patient reports a lighter mood.';

/// Session-scale ratings as a fraction of each scale's range, cycled across the
/// rating rows. Chosen to look like a real spread rather than a flat row.
const _ratings = <double>[0.62, 0.35, 0.48, 0.7, 0.25];

/// Register every font in the asset bundle, plus the Material icon font.
///
/// Walks `FontManifest.json` rather than hard-coding asset keys, which is how
/// `golden_toolkit` does it — it picks up `MaterialIcons-Regular.otf` and any
/// family declared in `pubspec.yaml` without needing to know their paths.
Future<void> _loadFonts() async {
  final manifest = await rootBundle.loadString('FontManifest.json');
  for (final entry in json.decode(manifest) as List<dynamic>) {
    final family = (entry as Map<String, dynamic>)['family'] as String;
    final loader = FontLoader(family);
    for (final asset in entry['fonts'] as List<dynamic>) {
      final path = (asset as Map<String, dynamic>)['asset'] as String;
      loader.addFont(rootBundle.load(path));
    }
    await loader.load();
  }
}

/// The text font to render captures with, or null when none could be found.
///
/// `flutter_tester` ships **no fonts at all**. `FontManifest.json` contains only
/// what `pubspec.yaml` declares — in this project, the Material icon font and
/// the committed IBM Plex faces — and the default text face normally comes from
/// the host platform, which the test binding does not have. Without an explicit
/// text font every glyph renders as a filled box, and the capture still
/// "succeeds", so this is checked loudly.
///
/// Preference order:
///
/// 1. `assets/fonts/IBMPlexSans-*.ttf`, committed. Preferred because it makes
///    the screenshots reproducible on any machine and in CI, and because those
///    are the same files that give the PDF reports full Unicode coverage.
/// 2. A host system font, so the harness still works if those are ever dropped
///    from the bundle. Host-dependent, hence second.
Future<String?> _loadTextFont() async {
  // (1) A committed font: reproducible everywhere.
  try {
    final loader = FontLoader('DocsText')
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSans-Bold.ttf'));
    await loader.load();
    return 'DocsText';
  } catch (_) {
    // Not bundled in this checkout; fall through.
  }

  // (2) A host font. Regular and bold are loaded into one family so bold text
  // is really bold rather than synthesised.
  const candidates = <List<String>>[
    // seguisym carries the symbol glyphs (the validity tick is a literal U+2713,
    // which real Windows finds through the OS fallback chain but the test
    // binding does not).
    [
      'C:/Windows/Fonts/segoeui.ttf',
      'C:/Windows/Fonts/segoeuib.ttf',
      'C:/Windows/Fonts/seguisym.ttf',
    ],
    ['C:/Windows/Fonts/arial.ttf', 'C:/Windows/Fonts/arialbd.ttf'],
    [
      '/System/Library/Fonts/Supplemental/Arial.ttf',
      '/System/Library/Fonts/Supplemental/Arial Bold.ttf'
    ],
    [
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
    ],
  ];
  for (final pair in candidates) {
    if (!File(pair.first).existsSync()) continue;
    final loader = FontLoader('DocsText');
    for (final path in pair.where((p) => File(p).existsSync())) {
      loader.addFont(
          Future.value(ByteData.view(File(path).readAsBytesSync().buffer)));
    }
    await loader.load();
    return 'DocsText';
  }
  return null;
}

/// The app's theme with [_textFont] applied to every text style.
ThemeData _withFont(ThemeData base) => _textFont == null
    ? base
    : base.copyWith(textTheme: base.textTheme.apply(fontFamily: _textFont));

/// Pump [home] inside the capture boundary.
///
/// The boundary wraps the `MaterialApp`'s content via its `builder`, not the
/// home widget, so anything pushed into the Navigator's overlay — a dialog, a
/// `MenuAnchor`'s menu — is captured along with the screen behind it. That is
/// what makes the dialog and menu captures possible at all.
///
/// `debugDisableShadows` is toggled here and restored in [_shoot], not in
/// setUp/tearDown: the binding asserts that painting debug variables are back to
/// their defaults, and that check runs INSIDE the test body.
Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Brightness brightness = Brightness.light,
  Size size = const Size(_wide, _maxHeight),
  double textScale = 1.0,
}) async {
  debugDisableShadows = false;
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    // The app's real theme, with a text font substituted in — see
    // [_loadTextFont] for why one has to be supplied explicitly.
    theme: _withFont(dbsTheme(brightness)),
    builder: (context, child) => RepaintBoundary(
      key: _boundary,
      child: MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: child!,
      ),
    ),
    home: home,
  ));
  await tester.pumpAndSettle();
}

/// The last row of [image] that has anything drawn on it.
///
/// "Anything" means "differs from the bottom-right pixel", which on every screen
/// here is the page background. Returns `image.height - 1` when the bottom row
/// is already painted, i.e. there is nothing to trim.
int _lastPaintedRow(ByteData raw, int width, int height) {
  final px = raw.buffer.asUint8List();
  int at(int x, int y) => (y * width + x) * 4;
  final bg = at(width - 1, height - 1);
  bool isBackground(int i) =>
      px[i] == px[bg] &&
      px[i + 1] == px[bg + 1] &&
      px[i + 2] == px[bg + 2] &&
      px[i + 3] == px[bg + 3];

  for (var y = height - 1; y >= 0; y--) {
    for (var x = 0; x < width; x++) {
      if (!isBackground(at(x, y))) return y;
    }
  }
  return height - 1;
}

/// Capture the boundary, optionally cropping dead background off the bottom.
///
/// [trim] exists because a scroll view's `maxScrollExtent` measures the extent
/// it will *scroll*, which on the wizard steps runs well past the last thing
/// actually drawn — step 1 came out 44 % empty, and the narrow variant 46 %.
/// Rather than guess which widget reserves that space, the frame is cut to the
/// last painted row plus [_trimMargin] of breathing room. Only the captures
/// whose height was measured from a scroll view use it: a region, a dialog or a
/// deliberately-sized empty state is already framed on purpose, and a centred
/// empty state would look bottom-heavy with its lower half removed.
Future<void> _shoot(
  WidgetTester tester,
  String name, {
  bool trim = false,
}) async {
  // Image.asset decodes asynchronously and never completes under the fake
  // clock, so the AppBar logo would be missing from every capture.
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pumpAndSettle();

  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
  final bytes = await tester.runAsync(() async {
    var image = await boundary.toImage(pixelRatio: 2);

    if (trim) {
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final keep = raw == null
          ? image.height
          : _lastPaintedRow(raw, image.width, image.height) + 1 + _trimMargin;
      if (keep < image.height) {
        final recorder = ui.PictureRecorder();
        final rect =
            Rect.fromLTWH(0, 0, image.width.toDouble(), keep.toDouble());
        Canvas(recorder).drawImageRect(image, rect, rect, Paint());
        final cropped =
            await recorder.endRecording().toImage(image.width, keep);
        image.dispose();
        image = cropped;
      }
    }

    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });

  final file = File('$_outDir/$name.png')..createSync(recursive: true);
  file.writeAsBytesSync(bytes!);

  // Restore before the test body ends; see [_pump].
  debugDisableShadows = true;
}

// ---------------------------------------------------------------------------
// Fitting the frame to the content
// ---------------------------------------------------------------------------

/// The screen's own vertical scroll view, or null when it has none.
///
/// The first *vertical* one in tree order is the page. A screen may also hold
/// horizontal scrollables — the entries table, the annotations `DataTable` — and
/// measuring one of those would size the window to a row height.
ScrollableState? _pageScroll(WidgetTester tester) {
  for (final element in find.byType(Scrollable).evaluate()) {
    final state = (element as StatefulElement).state as ScrollableState;
    if (state.position.axis == Axis.vertical &&
        state.position.hasContentDimensions) {
      return state;
    }
  }
  return null;
}

/// Capture [name] with the window sized to exactly the laid-out content.
///
/// Nothing is cut off and nothing is padded with background: the height is the
/// scroll view's own `viewportDimension + maxScrollExtent`, plus whatever chrome
/// (the AppBar) sits outside it.
///
/// [fallback] is used for a screen with no scroll view at all — an empty state
/// that is a single centred `Column`, which fills whatever it is given and so
/// cannot be measured.
///
/// [height], when given, skips the measurement entirely. That is for screens
/// whose body *fills* the window rather than flowing down it — the longitudinal
/// review puts its chart in an `Expanded`, so its content is exactly as tall as
/// whatever it is handed and "fit to content" has no fixed point.
Future<void> _shootFitted(
  WidgetTester tester,
  String name, {
  double width = _wide,
  double fallback = 420,
  double max = _maxHeight,
  double? height,
}) async {
  if (height != null) {
    await tester.binding.setSurfaceSize(Size(width, height));
    await tester.pumpAndSettle();
    await _shoot(tester, name);
    return;
  }
  // Measure from a deliberately SHORT window. `maxScrollExtent` is how much
  // content overflows the viewport, so it is 0 whenever the content already
  // fits — measuring from a tall window therefore cannot tell "fits exactly"
  // from "fits with 2000 px to spare", and every capture came out at the
  // maximum height. From a short one the overflow is real and the content
  // height is `viewportDimension + maxScrollExtent`.
  const probe = 400.0;
  await tester.binding.setSurfaceSize(Size(width, probe));
  await tester.pumpAndSettle();

  final scroll = _pageScroll(tester);
  final double fitted;
  if (scroll == null) {
    fitted = fallback;
  } else {
    final position = scroll.position;
    final chrome = probe - position.viewportDimension;
    fitted = (chrome + position.viewportDimension + position.maxScrollExtent)
        .ceilToDouble()
        .clamp(200.0, max);
  }

  await tester.binding.setSurfaceSize(Size(width, fitted));
  await tester.pumpAndSettle();
  await _shoot(tester, name, trim: scroll != null);
}

/// Capture the band of the page running from [from]'s top edge to [to]'s bottom.
///
/// For steps too tall to photograph whole. The page is scrolled so [from] sits
/// flush under the AppBar and the window is sized to the band, so both cuts land
/// on a real boundary rather than through a widget — which is exactly what the
/// previous `setSurfaceSize(Size(1500, 1180))` did not do.
///
/// [max] caps the band for content that is unboundedly long on purpose. The
/// entries table grows a row per (block, scale) and reaches ~2900 px on the
/// example session, which is both a poor figure and over this repo's 600 KB
/// large-file gate; a capped table visibly continuing past the frame is what a
/// long table looks like, and is a different thing from a button cut in half.
Future<void> _shootRegion(
  WidgetTester tester,
  String name, {
  required Finder from,
  required Finder to,
  double width = _wide,
  double pad = 16,
  double max = _maxHeight,
}) async {
  Future<void> alignTop() async {
    if (_pageScroll(tester) == null) return;
    await Scrollable.ensureVisible(tester.element(from),
        alignment: 0, duration: Duration.zero);
    await tester.pumpAndSettle();
  }

  await tester.binding.setSurfaceSize(Size(width, _maxHeight));
  await tester.pumpAndSettle();
  await alignTop();

  // `from` is now at the top of the viewport, so its own offset is the chrome
  // height; the band below it is what the capture should show.
  final top = tester.getRect(from.first).top;
  final band = tester.getRect(to.last).bottom - top;
  final height = (top + band + pad).ceilToDouble().clamp(200.0, max);

  await tester.binding.setSurfaceSize(Size(width, height));
  await tester.pumpAndSettle();
  // Shrinking the viewport moves the scroll offset; realign before capturing.
  await alignTop();
  await _shoot(tester, name);
}

/// Capture the dialog that is currently open, framed by a thin band of the
/// screen behind it.
///
/// The window is sized to the dialog rather than the other way round. A dialog
/// photographed on a 1440 px canvas is a small box in a field of scrim, which is
/// the complaint the whole of this rewrite is answering; sized to its own
/// content it fills the figure. The previous size is restored afterwards, so a
/// test can capture several dialogs in turn and still reach the controls that
/// open them.
Future<void> _shootDialog(
  WidgetTester tester,
  String name, {
  double margin = 56,
}) async {
  final before = tester.view.physicalSize / tester.view.devicePixelRatio;
  // Measure from a modest window, for the same reason [_shootFitted] probes
  // from a short one: several of these dialogs size themselves to the space
  // available (a preset list in an `Expanded`), so measured on a 3000 px canvas
  // they report being 3000 px tall.
  await tester.binding.setSurfaceSize(const Size(1100, 900));
  await tester.pumpAndSettle();
  // The `Dialog` render box is the whole overlay — it holds the `Align` that
  // centres the surface — so measuring it just returns the window size and the
  // frame grows by one margin per pass. The `Material` inside it is the actual
  // card.
  final surface = find
      .descendant(of: find.byType(Dialog).last, matching: find.byType(Material))
      .first;
  // Two passes: resizing lets the dialog re-lay out, and the second
  // measurement is of the size it will actually be captured at.
  for (var pass = 0; pass < 2; pass++) {
    final rect = tester.getRect(surface);
    await tester.binding.setSurfaceSize(Size(
      (rect.width + margin * 2).ceilToDouble().clamp(320.0, _wide),
      (rect.height + margin * 2).ceilToDouble().clamp(240.0, _maxHeight),
    ));
    await tester.pumpAndSettle();
  }
  await _shoot(tester, name);
  await tester.binding.setSurfaceSize(before);
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Contracts and seeding
// ---------------------------------------------------------------------------

/// Contracts loaded from the committed schema, so the wizard renders with real
/// electrode models and limits instead of empty dropdowns.
Future<(ElectrodeCatalog, StimLimits, ScalePresets)> _contracts() async => (
      ElectrodeCatalog.fromJson(
          json.decode(File('schema/electrode_models.json').readAsStringSync())
              as Map<String, dynamic>),
      StimLimits.fromJson(
          json.decode(File('schema/limits.json').readAsStringSync())
              as Map<String, dynamic>),
      ScalePresets.fromJson(
          json.decode(File('schema/scale_presets.json').readAsStringSync())
              as Map<String, dynamic>),
    );

/// The committed example session, so the charts and the entries table have real
/// content instead of empty-state placeholders.
SessionAuthoring _seededAuthoring() =>
    SessionAuthoring()..loadExisting(File(_fixture).readAsStringSync());

/// Tap the current step's `Next`. Only the active step renders one, so the
/// finder is unambiguous.
Future<void> _next(WidgetTester tester) async => _tapText(tester, 'Next');

/// Scroll [finder] into view, let the scroll settle, then tap it.
///
/// The settle between the two matters: `ensureVisible` starts an animation, and
/// tapping before it finishes uses the widget's pre-scroll position, which the
/// framework then reports as a tap outside the render tree.
Future<void> _tapFinder(WidgetTester tester, Finder finder) async {
  final target = finder.first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) =>
    _tapFinder(tester, find.text(text));

Future<void> _tapTooltip(WidgetTester tester, String tooltip) =>
    _tapFinder(tester, find.byTooltip(tooltip));

/// Fill a labelled text field, addressing it by the label the user sees.
///
/// Silently does nothing when the field is absent, so a helper can be reused
/// across steps that do not all have every field.
Future<void> _type(
  WidgetTester tester,
  String label,
  String text, {
  int at = 0,
}) async {
  final field = find.widgetWithText(TextField, label);
  if (field.evaluate().length <= at) return;
  await tester.ensureVisible(field.at(at));
  await tester.enterText(field.at(at), text);
  await tester.pumpAndSettle();
}

/// Pick a stimulation program, so the card reads a group rather than its
/// "Select program" hint.
///
/// Addressed through the hint text, not `find.byType(DropdownButton).first`:
/// the electrode-model dropdown is built above this one, so `.first` opened
/// that instead, found no program in it, and left the card unset — which is
/// exactly the empty-form state these captures exist to avoid.
///
/// The dropdown renders its selected value AND its menu items as `Text`, so the
/// menu item is addressed as the last match rather than the first.
Future<void> _selectProgram(WidgetTester tester, {String program = 'B'}) async {
  final dropdown = find.ancestor(
    of: find.text('Select program'),
    matching: find.byType(DropdownButton<String>),
  );
  if (dropdown.evaluate().isEmpty) return;
  await _tapFinder(tester, dropdown);
  final item = find.text(program);
  if (item.evaluate().isEmpty) {
    await tester.tapAt(const Offset(4, 4)); // dismiss
    await tester.pumpAndSettle();
    return;
  }
  await tester.tap(item.last);
  await tester.pumpAndSettle();
}

/// Step 0: a patient and a run, so the BIDS filename the app composes is real.
Future<void> _seedFileStep(WidgetTester tester) async {
  await _type(tester, 'Patient ID (sub-)', _subjectId);
  await _type(tester, 'Run', _runId);
}

/// Tap a shape on the [index]th lead.
///
/// The layout comes from the same pure `computeLayout` the widget uses, so the
/// tap targets are exact rather than guessed — the approach
/// `test/electrode_view_test.dart` already takes. One tap leaves a contact
/// anodic, two cathodic (OFF -> ANODIC -> CATHODIC -> OFF).
Future<void> _tapElectrode(
  WidgetTester tester,
  ElectrodeModel model, {
  required int index,
  required Offset Function(ElectrodeLayout) target,
  int taps = 1,
}) async {
  final view = find.byType(ElectrodeView).at(index);
  if (view.evaluate().isEmpty) return;
  await tester.ensureVisible(view);
  final origin = tester.getTopLeft(view);
  final layout = computeLayout(model, tester.getSize(view));
  for (var i = 0; i < taps; i++) {
    await tester.tapAt(origin + target(layout));
    await tester.pumpAndSettle();
  }
}

Offset _contact(ElectrodeLayout layout, int level, int segment) => layout.levels
    .firstWhere((l) => l.levelIdx == level)
    .contactRects[ContactKey(level, segment)]!
    .center;

/// A full baseline configuration — the state the previous captures showed as
/// empty placeholders.
///
/// Current is steered across two segments of one level, which is the case the
/// documentation spends most of its words on and which is also what makes the
/// amplitude-split rows appear (they stay hidden below two cathodes).
///
/// With [invalid] the case is left off, so the left lead has cathodes and no
/// return path: applied anyway, like the desktop, and reported invalid.
Future<void> _seedConfiguration(
  WidgetTester tester,
  ElectrodeModel model, {
  bool invalid = false,
}) async {
  await _selectProgram(tester);
  await _tapElectrode(tester, model,
      index: 0, taps: 2, target: (l) => _contact(l, 2, 1));
  await _tapElectrode(tester, model,
      index: 0, taps: 2, target: (l) => _contact(l, 2, 2));
  if (!invalid) {
    await _tapElectrode(tester, model,
        index: 0, target: (l) => l.caseRect.center);
  }

  // Right lead: a plain ring cathode against the case.
  await _tapElectrode(tester, model,
      index: 1, taps: 2, target: (l) => _contact(l, 3, 0));
  await _tapElectrode(tester, model,
      index: 1, target: (l) => l.caseRect.center);

  for (var side = 0; side < 2; side++) {
    await _type(tester, 'Frequency', _frequency, at: side);
    await _type(tester, 'Amplitude', _amplitude, at: side);
    await _type(tester, 'Pulse width', _pulseWidth, at: side);
  }
}

/// Rate every session scale, leaving the last omitted so the "not assessed"
/// state is documented beside the normal one.
Future<void> _seedRatings(WidgetTester tester) async {
  final sliders = find.byType(ScaleSlider);
  final count = sliders.evaluate().length;
  for (var i = 0; i < count; i++) {
    if (i == count - 1) {
      final omit = find.descendant(
        of: sliders.at(i),
        matching: find.byTooltip('Omit (not assessed)'),
      );
      if (omit.evaluate().isEmpty) continue;
      await tester.ensureVisible(omit);
      await tester.tap(omit);
      await tester.pumpAndSettle();
      continue;
    }
    // Tapping the bar sets the value from the x fraction, which is how a
    // clinician sets it too.
    final bar =
        find.descendant(of: sliders.at(i), matching: find.byType(CustomPaint));
    if (bar.evaluate().isEmpty) continue;
    await tester.ensureVisible(sliders.at(i));
    final rect = tester.getRect(bar.first);
    await tester.tapAt(Offset(
      rect.left + rect.width * _ratings[i % _ratings.length],
      rect.center.dy,
    ));
    await tester.pumpAndSettle();
  }
}

/// Two visits of one patient, for the longitudinal captures.
///
/// Built from the committed example with its dates shifted, so the chart plots
/// real recorded scale values twice rather than invented ones.
List<ImportedSessionFile> _visits({bool mismatchedPatients = false}) {
  final source = File(_fixture).readAsStringSync();
  return [
    ImportedSessionFile(
      name: 'sub-01_ses-20260626_task-programming_run-01_beh.tsv',
      rows: parseSessionTsv(source),
    ),
    ImportedSessionFile(
      name: mismatchedPatients
          ? 'sub-04_ses-20260918_task-programming_run-01_beh.tsv'
          : 'sub-01_ses-20260918_task-programming_run-02_beh.tsv',
      rows: parseSessionTsv(source.replaceAll('2026-06-26', '2026-09-18')),
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  if (_outDir == null) {
    test('docs screenshots', () {},
        skip: 'set DOCS_SCREENSHOT_DIR to generate');
    return;
  }

  setUpAll(() async {
    await _loadFonts();
    _textFont = await _loadTextFont();
    // CustomPainters never see the theme, so the electrode labels, the "Ring"
    // caps, the slider values and the chart ticks need this separately or they
    // render as filled boxes in the app's most recognisable artwork.
    debugPainterFontFamily = _textFont;
    if (_textFont == null) {
      // Failing here beats emitting thirty files full of black rectangles that
      // look like a rendering bug in the app.
      fail('No text font available, so every glyph would render as a filled '
          'box. Restore assets/fonts/IBMPlexSans-{Regular,Bold}.ttf or run on '
          'a host with system fonts.');
    }
  });

  // ---- Home -------------------------------------------------------------

  testWidgets('home', (tester) async {
    await _pump(tester, const HomeScreen());
    await _shootFitted(tester, 'home', width: _narrow, fallback: 620);
  });

  testWidgets('home (dark)', (tester) async {
    await _pump(tester, const HomeScreen(), brightness: Brightness.dark);
    await _shootFitted(tester, 'home_dark', width: _narrow, fallback: 620);
  });

  testWidgets('home (large text)', (tester) async {
    // The text-size control in the top bar goes to 1.6; this is what the docs
    // point at when they say the app stays legible at a bedside.
    await _pump(tester, const HomeScreen(), textScale: 1.4);
    await _shootFitted(tester, 'home_large_text',
        width: _narrow, fallback: 800);
  });

  // ---- Complete workflow ------------------------------------------------

  testWidgets('session: file step', (tester) async {
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(
        catalog: catalog,
        limits: limits,
        scalePresets: presets,
        authoring: _seededAuthoring(),
      ),
    );
    await _seedFileStep(tester);
    await _shootFitted(tester, 'session_step0_file');
  });

  testWidgets('session: initial configuration', (tester) async {
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(catalog: catalog, limits: limits, scalePresets: presets),
    );
    await _seedFileStep(tester);
    await _next(tester);
    await _seedConfiguration(tester, catalog.models[_defaultModel]!);
    await _tapText(tester, _preset);
    await _type(tester, 'Notes', _initialNotes);
    await _shootFitted(tester, 'session_step1_config');
  });

  testWidgets('session: initial configuration (narrow)', (tester) async {
    // Below the 900 px breakpoint the two rows stack into one column — the
    // layout a phone, or a tablet held in portrait, actually gets.
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(catalog: catalog, limits: limits, scalePresets: presets),
      size: const Size(_narrow, _maxHeight),
    );
    await _seedFileStep(tester);
    await _next(tester);
    await _tapText(tester, _preset);
    await _shootFitted(tester, 'session_step1_narrow',
        width: _narrow, max: 4400);
  });

  testWidgets('session: electrodes, valid and invalid', (tester) async {
    final (catalog, limits, presets) = await _contracts();
    final model = catalog.models[_defaultModel]!;
    await _pump(
      tester,
      SessionScreen(catalog: catalog, limits: limits, scalePresets: presets),
    );
    await _next(tester);

    await _seedConfiguration(tester, model, invalid: true);
    await _shootRegion(tester, 'session_electrodes_invalid',
        from: find.text('Electrodes'), to: find.text('Cathodic (−)'));

    // Completing the circuit with the case turns the pane green.
    await _tapElectrode(tester, model,
        index: 0, target: (l) => l.caseRect.center);
    await _shootRegion(tester, 'session_electrodes',
        from: find.text('Electrodes'), to: find.text('Cathodic (−)'));
  });

  testWidgets('session: session scales configuration', (tester) async {
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(catalog: catalog, limits: limits, scalePresets: presets),
    );
    await _next(tester);
    await _next(tester);
    await _tapText(tester, _preset);
    await _shootFitted(tester, 'session_step2_scales');
  });

  testWidgets('session: recording and charts', (tester) async {
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(
        catalog: catalog,
        limits: limits,
        scalePresets: presets,
        authoring: _seededAuthoring(),
      ),
    );
    await _seedFileStep(tester);
    await _next(tester);
    await _seedConfiguration(tester, catalog.models[_defaultModel]!);
    await _next(tester);
    await _tapText(tester, _preset);
    await _next(tester);

    await _seedRatings(tester);
    await _type(tester, 'Side effects (if any)', _sideEffects);
    await _type(tester, 'Notes', _recordingNotes);

    // The step is ~4800 px tall, so it is documented in the two parts the
    // pages actually describe rather than shrunk into one unreadable image.
    await _shootRegion(tester, 'session_step3_recording',
        from: find.text('Program'), to: find.text('Insert recording block'));
    await _shootRegion(tester, 'session_step3_charts',
        from: find.textContaining('Inserted entries'),
        to: find.byType(EntryChartsView));
  });

  testWidgets('session: recording (dark)', (tester) async {
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(
        catalog: catalog,
        limits: limits,
        scalePresets: presets,
        authoring: _seededAuthoring(),
      ),
      brightness: Brightness.dark,
    );
    await _next(tester);
    await _seedConfiguration(tester, catalog.models[_defaultModel]!);
    await _next(tester);
    await _tapText(tester, _preset);
    await _next(tester);
    await _seedRatings(tester);
    await _shootRegion(tester, 'session_step3_recording_dark',
        from: find.text('Program'), to: find.text('Insert recording block'));
  });

  // ---- Menus ------------------------------------------------------------

  testWidgets('session: export menu and paper-size submenu', (tester) async {
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(
        catalog: catalog,
        limits: limits,
        scalePresets: presets,
        authoring: _seededAuthoring(),
      ),
    );
    await _next(tester);
    await _next(tester);
    await _next(tester);

    // Shrink to the frame BEFORE the menu opens. A menu lives in the overlay,
    // not in the page's scroll view, so [_shootFitted] would measure the page
    // and shrink the window out from under the menu — which is how the submenu
    // item ended up outside the render tree on the first attempt.
    await tester.binding.setSurfaceSize(const Size(_wide, 620));
    await tester.pumpAndSettle();
    // Put the Export button just below the AppBar so the menu opens into the
    // frame rather than off the bottom of it.
    await Scrollable.ensureVisible(tester.element(find.text('Export')),
        alignment: 0.05, duration: Duration.zero);
    await tester.pumpAndSettle();

    // Only the submenu shot is kept: it shows the whole menu as well, so a
    // separate capture of the menu alone was the same picture twice.
    await _tapText(tester, 'Export');
    await _tapText(tester, 'Paper size: A4');
    await _shoot(tester, 'session_paper_size_submenu');
  });

  // ---- Dialogs ----------------------------------------------------------

  testWidgets('dialogs: programs, parameter presets, clinical scales',
      (tester) async {
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(catalog: catalog, limits: limits, scalePresets: presets),
    );
    await _next(tester);
    await _tapText(tester, _preset);

    for (final entry in const [
      ('Edit programs', 'dialog_programs'),
      ('Edit parameter presets', 'dialog_parameter_presets'),
      ('Settings clinical scales', 'dialog_clinical_scales'),
    ]) {
      await _tapTooltip(tester, entry.$1);
      await _shootDialog(tester, entry.$2);
      await _tapText(tester, 'Cancel');
    }
  });

  testWidgets('dialogs: session scales settings', (tester) async {
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(catalog: catalog, limits: limits, scalePresets: presets),
    );
    await _next(tester);
    await _next(tester);
    await _tapText(tester, _preset);
    await _tapTooltip(tester, 'Settings session scales');
    // Unlike the clinical variant, each row here carries a Min and a Max —
    // which is the reason both dialogs are documented rather than one.
    await _shootDialog(tester, 'dialog_session_scales');
  });

  testWidgets('dialogs: scale targets and report sections', (tester) async {
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(
        catalog: catalog,
        limits: limits,
        scalePresets: presets,
        authoring: _seededAuthoring(),
      ),
    );
    await _next(tester);
    await _next(tester);
    await _tapText(tester, _preset);
    await _next(tester);

    await _tapText(tester, 'Scale targets');
    await _shootDialog(tester, 'dialog_scale_targets');
    await _tapText(tester, 'Cancel');

    // Reached through Export in the app, which needs the share and file-picker
    // channels a widget test has no answer for. The dialog itself is a plain
    // function, so it is opened directly over the same screen.
    unawaited(showReportSectionsDialog(
        tester.element(find.byType(SessionScreen)), kAllReportSections));
    await tester.pumpAndSettle();
    await _shootDialog(tester, 'dialog_report_sections');
  });

  testWidgets('dialogs: help / about', (tester) async {
    await _pump(tester, const HomeScreen(), size: const Size(_narrow, 1200));
    await _tapTooltip(tester, 'Help / about');
    await _shootDialog(tester, 'dialog_about');
  });

  // ---- Annotations ------------------------------------------------------

  testWidgets('annotations: file step', (tester) async {
    await _pump(tester, const AnnotationsScreen());
    await _seedFileStep(tester);
    await _shootFitted(tester, 'annotations_file');
  });

  testWidgets('annotations: notes step', (tester) async {
    await _pump(tester, const AnnotationsScreen());
    await _seedFileStep(tester);
    await _next(tester);
    for (final note in const [
      'Session started; patient alert and oriented.',
      'Reports the paraesthesia has settled since the last change.',
      'Discussed raising the left amplitude at the next visit.',
    ]) {
      await _type(tester, 'Note', note);
      await _tapText(tester, 'Insert timestamped note');
    }
    await _shootFitted(tester, 'annotations_notes');
  });

  // ---- Single session report -------------------------------------------

  testWidgets('single session report: empty', (tester) async {
    final contracts = await _contracts();
    await _pump(tester, SingleSessionReportScreen(catalog: contracts.$1),
        size: const Size(_narrow, 1000));
    await _shootFitted(tester, 'report_empty', width: _narrow, height: 520);
  });

  // ---- Longitudinal -----------------------------------------------------

  testWidgets('longitudinal: empty', (tester) async {
    await _pump(tester, const LongitudinalScreen(),
        size: const Size(_narrow, 1000));
    await _shootFitted(tester, 'longitudinal_empty',
        width: _narrow, fallback: 420);
  });

  testWidgets('longitudinal: populated', (tester) async {
    await _pump(tester, LongitudinalScreen(initialFiles: _visits()));
    await _shootFitted(tester, 'longitudinal_populated', height: 900);
  });

  testWidgets('longitudinal: patient mismatch', (tester) async {
    // Combining two people into one longitudinal report is a safety problem,
    // not a formatting one, so the banner is worth documenting on its own.
    await _pump(
      tester,
      LongitudinalScreen(initialFiles: _visits(mismatchedPatients: true)),
    );
    await _shootFitted(tester, 'longitudinal_mismatch', height: 900);
  });
}
