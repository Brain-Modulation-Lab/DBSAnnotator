import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../session/scale_presets.dart';

/// Per-user preset overrides, persisted as JSON in the app-support directory
/// and layered over the bundled contract defaults — the tablet counterpart of
/// the desktop's per-user managers (`setting_presets_manager`,
/// `scale_preset_manager`, `program_config_manager`) under `user_data_dir()`.
///
/// Any field left null means "use the bundled default"; the UI merges with
/// `?? <default>`. Pure `fromJson`/`toJson` so the round-trip is unit-testable.
class UserPrefs {
  UserPrefs({
    this.stimFrequencies,
    this.stimAmplitudes,
    this.stimPulseWidths,
    this.programs,
    this.clinical,
    this.session,
  });

  /// Stimulation quick-pick lists (override `limits.json` stimulation_presets).
  List<num>? stimFrequencies;
  List<num>? stimAmplitudes;
  List<num>? stimPulseWidths;

  /// Program names (override the default None/A/B/C/D).
  List<String>? programs;

  /// Clinical scale presets: group name -> scale names.
  Map<String, List<String>>? clinical;

  /// Session scale presets: group name -> [name, min, max] rows.
  Map<String, List<List<String>>>? session;

  factory UserPrefs.fromJson(Map<String, dynamic> j) {
    List<num>? nums(String k) =>
        (j[k] as List?)?.map((e) => e as num).toList();
    return UserPrefs(
      stimFrequencies: nums('stim_frequencies'),
      stimAmplitudes: nums('stim_amplitudes'),
      stimPulseWidths: nums('stim_pulse_widths'),
      programs: (j['programs'] as List?)?.map((e) => e as String).toList(),
      clinical: (j['clinical'] as Map?)?.map((k, v) => MapEntry(
          k as String, (v as List).map((e) => e as String).toList())),
      session: (j['session'] as Map?)?.map((k, v) => MapEntry(
          k as String,
          (v as List)
              .map((r) => (r as List).map((e) => e as String).toList())
              .toList())),
    );
  }

  Map<String, dynamic> toJson() => {
        if (stimFrequencies != null) 'stim_frequencies': stimFrequencies,
        if (stimAmplitudes != null) 'stim_amplitudes': stimAmplitudes,
        if (stimPulseWidths != null) 'stim_pulse_widths': stimPulseWidths,
        if (programs != null) 'programs': programs,
        if (clinical != null) 'clinical': clinical,
        if (session != null) 'session': session,
      };
}

/// Default program names (desktop `ProgramConfigManager.DEFAULT_PROGRAMS`).
const List<String> kDefaultPrograms = ['None', 'A', 'B', 'C', 'D'];

/// Bundled [base] scale presets with the user's saved overrides layered on top
/// (F7) — edited/added disease groups win over the contract defaults, and any
/// new group name is appended to the button bar. Pure so it is unit-testable;
/// the tablet counterpart of the desktop ScalePresetManager merge.
ScalePresets mergeScalePresets(ScalePresets base, UserPrefs prefs) {
  final clinical = {...base.clinical};
  prefs.clinical?.forEach((k, v) => clinical[k] = v);
  final session = {...base.session};
  prefs.session?.forEach((k, rows) => session[k] = [
        for (final r in rows)
          (
            name: r.isNotEmpty ? r[0] : '',
            min: r.length > 1 ? r[1] : '0',
            max: r.length > 2 ? r[2] : '10',
            // The 4th cell is the report's optimization mode. Rows saved
            // before it existed fall back to the contract default.
            mode: r.length > 3 &&
                    scaleOptimizationModes.contains(r[3].trim().toLowerCase())
                ? r[3].trim().toLowerCase()
                : defaultScaleOptimizationMode,
          ),
      ]);
  final buttons = [
    ...base.buttons,
    for (final k in {...clinical.keys, ...session.keys})
      if (!base.buttons.contains(k)) k,
  ];
  return ScalePresets(buttons: buttons, clinical: clinical, session: session);
}

Future<File> _prefsFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}/dbs_user_prefs.json');
}

/// Load overrides, or empty prefs when absent/unreadable.
Future<UserPrefs> loadUserPrefs() async {
  try {
    final f = await _prefsFile();
    if (!await f.exists()) return UserPrefs();
    return UserPrefs.fromJson(
        jsonDecode(await f.readAsString()) as Map<String, dynamic>);
  } catch (_) {
    return UserPrefs();
  }
}

/// Persist overrides so edits survive relaunch.
Future<void> saveUserPrefs(UserPrefs prefs) async {
  final f = await _prefsFile();
  await f.writeAsString(jsonEncode(prefs.toJson()));
}
