/// A test-only override for the font that `CustomPainter`s draw text with.
///
/// A `CustomPainter` builds its own `TextStyle` and never consults the widget
/// tree, so `ThemeData.textTheme` cannot reach it. A null family resolves to
/// the platform default in the app, but to `flutter_tester`'s test font, which
/// draws every glyph as a filled rectangle, so the docs screenshot harness
/// needs a way in. A global debug flag follows the framework's own precedent
/// (`debugDisableShadows`).
library;

/// Font family for painter-drawn text, or null for the platform default.
///
/// Set only by `test/docs/screenshots_test.dart`.
String? debugPainterFontFamily;
