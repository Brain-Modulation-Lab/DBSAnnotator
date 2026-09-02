/// A test-only override for the font that `CustomPainter`s draw text with.
///
/// ## Why this exists
///
/// A `CustomPainter` builds its own `TextStyle` and never consults the widget
/// tree, so `ThemeData.textTheme` cannot reach it. That is fine in the running
/// app, where a `TextStyle` with no family resolves to the platform default.
///
/// It is not fine in `flutter test`. `flutter_tester` ships no fonts, and a
/// null family there resolves to the engine's test font, which draws every
/// glyph as a filled rectangle. So the docs screenshot harness can register a
/// real font and set the theme, and the electrode contact labels, the "Ring"
/// caps, the scale-slider values and the chart tick labels still come out as
/// black boxes — in the app's most recognisable artwork.
///
/// This is a global debug flag rather than a parameter threaded through five
/// widgets, following the framework's own precedent (`debugDisableShadows`,
/// `debugPaintSizeEnabled`). Production always leaves it null, which is exactly
/// the behaviour it had before this existed.
library;

/// Font family for painter-drawn text, or null for the platform default.
///
/// Set only by `test/docs/screenshots_test.dart`. Leave null everywhere else.
String? debugPainterFontFamily;
