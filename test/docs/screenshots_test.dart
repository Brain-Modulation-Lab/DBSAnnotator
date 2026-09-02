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
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui;

import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/core/session/scale_presets.dart';
import 'package:dbs_annotator/ui/annotations_screen.dart';
import 'package:dbs_annotator/ui/home_screen.dart';
import 'package:dbs_annotator/ui/longitudinal_screen.dart';
import 'package:dbs_annotator/ui/painter_font.dart';
import 'package:dbs_annotator/ui/session_screen.dart';
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

/// A tablet-ish canvas: wide enough for the wide layout the documentation
/// describes. Height is set per capture, because a fixed one leaves most of the
/// image empty on the shorter screens and the docs then show more background
/// than app.
const _tablet = Size(1280, 900);

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

  // The optional Unicode report fonts, when present, give the captures the same
  // typeface the PDF reports use. Absent is fine — see report_fonts.dart.
  try {
    final plex = FontLoader('IBMPlexSans')
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSans-Bold.ttf'));
    await plex.load();
  } catch (_) {
    // Not committed in this checkout; the bundled default is used instead.
  }
}

/// The text font to render captures with, or null when none could be found.
///
/// `flutter_tester` ships **no fonts at all**. `FontManifest.json` contains only
/// what `pubspec.yaml` declares — in this project, the Material icon font — and
/// the default text face normally comes from the host platform, which the test
/// binding does not have. Without an explicit text font every glyph renders as a
/// filled box, and the capture still "succeeds", so this is checked loudly.
///
/// Preference order:
///
/// 1. `assets/fonts/IBMPlexSans-*.ttf` if committed. Preferred because it makes
///    the screenshots reproducible on any machine and in CI, and because those
///    are the same files that give the PDF reports full Unicode coverage.
/// 2. A host system font, so a developer can regenerate usable screenshots
///    without first downloading anything. Host-dependent, hence second.
Future<String?> _loadTextFont() async {
  // (1) A committed font: reproducible everywhere.
  try {
    final loader = FontLoader('DocsText')
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSans-Bold.ttf'));
    await loader.load();
    return 'DocsText';
  } catch (_) {
    // Not committed in this checkout; fall through.
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
    ['/System/Library/Fonts/Supplemental/Arial.ttf',
     '/System/Library/Fonts/Supplemental/Arial Bold.ttf'],
    ['/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
     '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'],
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

/// Enables real Material elevation for the duration of one capture.
///
/// The test binding flattens shadows for golden determinism. It also asserts
/// that painting debug variables are back to their defaults, and that check runs
/// INSIDE the test body (before tearDown), so this has to be toggled on here and
/// off again in [_shoot], not in setUp/tearDown, which is too late.
Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Brightness brightness = Brightness.light,
  Size size = _tablet,
}) async {
  debugDisableShadows = false;
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(RepaintBoundary(
    key: _boundary,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      // The app's real theme, with a text font substituted in — see
      // [_loadTextFont] for why one has to be supplied explicitly.
      theme: _withFont(dbsTheme(brightness)),
      home: home,
    ),
  ));
  await tester.pumpAndSettle();
}

/// The app's theme with [_textFont] applied to every text style.
ThemeData _withFont(ThemeData base) => _textFont == null
    ? base
    : base.copyWith(textTheme: base.textTheme.apply(fontFamily: _textFont));

Future<void> _shoot(WidgetTester tester, String name) async {
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
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });

  final file = File('$_outDir/$name.png')..createSync(recursive: true);
  file.writeAsBytesSync(bytes!);

  // Restore before the test body ends; see [_pump].
  debugDisableShadows = true;
}

/// Contracts loaded from the committed schema, so the wizard renders with real
/// electrode models and limits instead of empty dropdowns.
Future<(ElectrodeCatalog, StimLimits, ScalePresets)> _contracts() async => (
      ElectrodeCatalog.fromJson(json.decode(
              File('schema/electrode_models.json').readAsStringSync())
          as Map<String, dynamic>),
      StimLimits.fromJson(json.decode(
              File('schema/limits.json').readAsStringSync())
          as Map<String, dynamic>),
      ScalePresets.fromJson(json.decode(
              File('schema/scale_presets.json').readAsStringSync())
          as Map<String, dynamic>),
    );

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
      // Failing here beats emitting five files full of black rectangles that
      // look like a rendering bug in the app.
      fail('No text font available, so every glyph would render as a filled '
          'box. Commit assets/fonts/IBMPlexSans-{Regular,Bold}.ttf (see '
          'docs/installation.rst) or run on a host with system fonts.');
    }
  });

  testWidgets('home', (tester) async {
    await _pump(tester, const HomeScreen(), size: const Size(1120, 620));
    await _shoot(tester, 'home');
  });

  testWidgets('home (dark)', (tester) async {
    await _pump(tester, const HomeScreen(),
        brightness: Brightness.dark, size: const Size(1120, 620));
    await _shoot(tester, 'home_dark');
  });

  testWidgets('session: file setup', (tester) async {
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(catalog: catalog, limits: limits, scalePresets: presets),
      size: const Size(1280, 480),
    );
    await _shoot(tester, 'session_file_setup');
  });

  testWidgets('session: recording', (tester) async {
    final (catalog, limits, presets) = await _contracts();

    // Seeded with the committed example session, so the charts and the entries
    // table have real content instead of empty-state placeholders.
    final authoring = SessionAuthoring()
      ..loadExisting(File('test/fixtures/'
              'sub-01_ses-20260626_task-programming_run-01_events.tsv')
          .readAsStringSync());

    // Drive the wizard on a tall surface: the Stepper scrolls, and only the
    // active step renders a Next button, so each tap is unambiguous.
    await _pump(
      tester,
      SessionScreen(
        catalog: catalog,
        limits: limits,
        scalePresets: presets,
        authoring: authoring,
      ),
      size: const Size(1500, 2400),
    );

    Future<void> next() async {
      final button = find.text('Next');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    await next(); // -> Initial configuration
    await next(); // -> Session scales configuration

    // A disease preset so the recording step has scales to rate; without it the
    // ratings column is empty and the screenshot shows nothing useful.
    final preset = find.widgetWithText(ChoiceChip, 'OCD');
    if (preset.evaluate().isNotEmpty) {
      await tester.ensureVisible(preset);
      await tester.tap(preset);
      await tester.pumpAndSettle();
    }

    await next(); // -> Recording

    // Shrink to the entry area before capturing. The full step is ~4800 px tall
    // once the review charts and the 40-row table are laid out below it, which
    // is unusable in a document; the parameters/electrodes/ratings rows are the
    // part the page is describing. The review widgets get their own capture.
    await tester.binding.setSurfaceSize(const Size(1500, 1180));
    await tester.pumpAndSettle();
    await _shoot(tester, 'session_recording');
  });

  testWidgets('annotations', (tester) async {
    await _pump(tester, const AnnotationsScreen(),
        size: const Size(1280, 380));
    await _shoot(tester, 'annotations');
  });

  testWidgets('longitudinal (empty state)', (tester) async {
    // Populating this needs the platform file picker, so only the import
    // prompt is capturable from a widget test.
    await _pump(tester, const LongitudinalScreen(),
        size: const Size(1120, 480));
    await _shoot(tester, 'longitudinal');
  });
}
