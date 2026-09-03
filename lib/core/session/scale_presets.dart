/// Scale presets from the generated contract `schema/scale_presets.json`
/// (source of truth: the Python desktop app's config). Pure parse/lookup
/// code — no widgets — so behaviour is verifiable headlessly.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// One session-scale preset row: name, its own slider bounds, and the default
/// direction the report's block ranking optimises it in (kept as the
/// contract's strings; the UI parses them when building sliders).
///
/// [mode] is `min` | `max` | `custom` | `ignore`, mirroring
/// `config.SESSION_SCALES_PRESETS`. Contracts generated before the field
/// existed carry 3-element rows, which decode to
/// [defaultScaleOptimizationMode].
typedef SessionScaleRow = ({
  String name,
  String min,
  String max,
  String mode,
});

/// Fallback for a preset row with no mode cell — matches the desktop's
/// `config.DEFAULT_SCALE_OPTIMIZATION_MODE`.
const String defaultScaleOptimizationMode = 'min';

/// The modes the contract may carry; anything else decodes to the default.
const List<String> scaleOptimizationModes = [
  'min',
  'max',
  'custom',
  'ignore',
];

/// The desktop's disease preset tables:
/// - [buttons]: ordered preset names shown as the pill/button bar;
/// - [clinical]: preset -> clinical scale NAMES (Step-1 baseline rows);
/// - [session]: preset -> (name, min, max) session-scale rows (Step 2/3).
class ScalePresets {
  const ScalePresets({
    required this.buttons,
    required this.clinical,
    required this.session,
  });

  factory ScalePresets.fromJson(Map<String, dynamic> json) {
    final buttons = (json['buttons'] as List)
        .map((e) => e as String)
        .toList(growable: false);

    final clinicalJson = json['clinical'] as Map<String, dynamic>;
    final clinical = <String, List<String>>{
      for (final entry in clinicalJson.entries)
        entry.key: (entry.value as List)
            .map((e) => e as String)
            .toList(growable: false),
    };

    final sessionJson = json['session'] as Map<String, dynamic>;
    final session = <String, List<SessionScaleRow>>{
      for (final entry in sessionJson.entries)
        entry.key: (entry.value as List).map((row) {
          final cells = (row as List).map((e) => '$e').toList();
          // The 4th cell (optimization mode) is absent in contracts
          // generated before it was added.
          final mode = cells.length > 3
              ? cells[3].trim().toLowerCase()
              : defaultScaleOptimizationMode;
          return (
            name: cells[0],
            min: cells[1],
            max: cells[2],
            mode: scaleOptimizationModes.contains(mode)
                ? mode
                : defaultScaleOptimizationMode,
          );
        }).toList(growable: false),
    };

    return ScalePresets(buttons: buttons, clinical: clinical, session: session);
  }

  /// Ordered preset names for the button bar (OCD, MDD, PD, ET, ...).
  final List<String> buttons;

  /// Preset -> clinical scale names (baseline / is_initial rows).
  final Map<String, List<String>> clinical;

  /// Preset -> session scale rows with per-scale min/max (recording rows).
  final Map<String, List<SessionScaleRow>> session;
}

/// Clinical scale names for [preset]; empty for unknown presets.
List<String> clinicalRows(ScalePresets p, String preset) =>
    p.clinical[preset] ?? const [];

/// Session scale rows for [preset]; empty for unknown presets.
List<SessionScaleRow> sessionRows(ScalePresets p, String preset) =>
    p.session[preset] ?? const [];

/// Loads the scale-presets contract from the bundled asset at runtime.
///
/// NOTE: the build/CI copies the repo-root `schema/*.json` contracts into
/// `app/assets/schema/` before building (same as `loadElectrodeCatalog`).
/// Tests read the repo-root file directly via `dart:io` instead.
Future<ScalePresets> loadScalePresets() async {
  final raw = await rootBundle.loadString('assets/schema/scale_presets.json');
  return ScalePresets.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
