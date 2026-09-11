import 'package:flutter/material.dart';

/// Desktop-matched palette (from styles/*.qss and
/// models/electrode_viewer.py `get_state_color`). Text size adapts to the
/// tablet, but colours match the Qt app.
class DbsColors {
  // Accent / primary (amber).
  static const accent = Color(0xFFF59E0B);
  static const primary = Color(0xFFB45309);
  static const primaryHover = Color(0xFFD97706);
  static const pillActiveBorder = Color(0xFF92400E);

  // Electrode contact states: base + border.
  static const offBase = Color(0xFF969696);
  static const offBorder = Color(0xFF323232);
  static const anodicBase = Color(0xFFFF6464);
  static const anodicBorder = Color(0xFFC83232);
  static const cathodicBase = Color(0xFF6496FF);
  static const cathodicBorder = Color(0xFF3264C8);

  // Validation.
  static const valid = Color(0xFF22C55E);
  static const invalid = Color(0xFFCC0000);

  // Session-scale progress fill (green gradient), per brightness.
  static List<Color> scaleFill(bool dark) => dark
      ? const [Color(0xFF10B981), Color(0xFF34D399), Color(0xFF10B981)]
      : const [Color(0xFF059669), Color(0xFF10B981), Color(0xFF059669)];

  /// Warm fill for the titled group cards: a translucent amber over the
  /// scaffold, never the Material-3 blue surface tint, which callers suppress
  /// with `surfaceTintColor: Colors.transparent`.
  static Color cardFill(bool dark) =>
      accent.withValues(alpha: dark ? 0.16 : 0.14);
}

/// Non-state colours for the electrode canvas: the lead's insulating polymer
/// body and its outline.
///
/// Only the inert lead material follows the theme. The contact state colours
/// (off / anodic / cathodic in [DbsColors]) stay brightness-independent
/// because grey / red / blue are clinical semantics, not decoration, and must
/// read the same in both themes and in a printed report, which passes
/// [ElectrodePalette.light] explicitly.
class ElectrodePalette {
  const ElectrodePalette({
    required this.polymer,
    required this.outline,
    required this.label,
  });

  /// Mid-tone of the insulating lead body; the painter derives the whole
  /// cylinder shading from it.
  final Color polymer;

  /// Lead / dome outline.
  final Color outline;

  /// `E{idx}` labels in the gutter beside the lead.
  final Color label;

  static const light = ElectrodePalette(
    polymer: Color(0xFFEFEFEF),
    outline: Color(0xFF8A8A8A),
    label: Color(0xFF0F172A),
  );

  static const dark = ElectrodePalette(
    polymer: Color(0xFF9BA3AF),
    outline: Color(0xFF5A6472),
    label: Color(0xFFF1F5F9),
  );

  static ElectrodePalette of(Brightness b) =>
      b == Brightness.dark ? dark : light;
}

/// App-wide light/dark selection, defaulting to light. Not persisted, which
/// matches the desktop app.
final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);

/// AppBar action that flips light/dark, showing the icon of the theme it
/// switches to.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
      iconSize: 28,
      tooltip: 'Switch light/dark',
      onPressed: () =>
          themeMode.value = dark ? ThemeMode.light : ThemeMode.dark,
    );
  }
}

/// App-wide text-scale factor, applied in [main] via MediaQuery's textScaler.
/// Session-only, like [themeMode].
final ValueNotifier<double> textScale = ValueNotifier(1.0);

const double _kMinTextScale = 0.8;
const double _kMaxTextScale = 1.6;
const double _kTextScaleStep = 0.1;

/// Connected +/- pair that changes the app text size at runtime.
class TextSizeButtons extends StatelessWidget {
  const TextSizeButtons({super.key});

  void _bump(double delta) {
    final next = (textScale.value + delta).clamp(
      _kMinTextScale,
      _kMaxTextScale,
    );
    // Round to the step grid so repeated taps do not accumulate float noise.
    textScale.value = (next * 10).roundToDouble() / 10;
  }

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).colorScheme.outlineVariant;
    Widget btn(IconData icon, String tip, VoidCallback onTap) =>
        IconButton(icon: Icon(icon, size: 26), tooltip: tip, onPressed: onTap);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: divider),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            btn(
              Icons.text_decrease,
              'Smaller text',
              () => _bump(-_kTextScaleStep),
            ),
            SizedBox(
              height: 28,
              child: VerticalDivider(width: 1, color: divider),
            ),
            btn(
              Icons.text_increase,
              'Larger text',
              () => _bump(_kTextScaleStep),
            ),
          ],
        ),
      ),
    );
  }
}

/// App theme mirroring the desktop dark/light surfaces with the amber accent.
ThemeData dbsTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: DbsColors.accent,
    brightness: brightness,
    primary: DbsColors.accent,
    surface: dark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
  );
}

/// A titled card, matching the desktop `QGroupBox`.
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      // A transparent surfaceTintColor (below) keeps Material 3 from tinting
      // the warm amber blue.
      color: DbsColors.cardFill(
        Theme.of(context).brightness == Brightness.dark,
      ),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: DbsColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
