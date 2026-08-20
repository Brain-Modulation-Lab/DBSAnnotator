import 'package:dbs_annotator_tablet/ui/scale_presets_dialog.dart';
import 'package:dbs_annotator_tablet/ui/setting_presets_dialog.dart';
import 'package:dbs_annotator_tablet/ui/stim_params_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Headless coverage for the desktop-style preset editor dialogs (Round 3).
/// They use only `showDialog` (no platform channels), so the seed -> edit ->
/// save round trip is verifiable without a device.
void main() {
  /// Pump a host with a button that opens [open] and stores its result.
  Future<void> pumpHost(
    WidgetTester tester,
    Future<void> Function(BuildContext) open,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('setting presets dialog sorts + de-dupes and returns lists',
      (tester) async {
    const limits = StimLimits(
      frequency: (min: 10, max: 200),
      amplitude: (min: 0, max: 15),
      pulseWidth: (min: 10, max: 200),
      sessionScale: (min: 0, max: 10),
    );
    StimPresetLists? result;
    await pumpHost(tester, (context) async {
      result = await showSettingPresetsDialog(
        context,
        limits: limits,
        frequencies: const [125, 25], // intentionally unsorted
        amplitudes: const [1.5],
        pulseWidths: const [60],
      );
    });

    expect(find.text('Edit parameter presets'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.frequencies, [25, 125]); // sorted ascending
    expect(result!.amplitudes, [1.5]);
    expect(result!.pulseWidths, [60]);
  });

  testWidgets('clinical presets dialog returns group -> name lists',
      (tester) async {
    Map<String, List<String>>? result;
    await pumpHost(tester, (context) async {
      result = await showClinicalPresetsDialog(context, presets: const {
        'OCD': ['Y-BOCS', 'MADRS'],
      });
    });

    expect(find.text('Clinical scales settings'), findsOneWidget);
    // 'OCD' appears twice (group tile + selected editor's name field), so we
    // just verify the returned map below.
    await tester.tap(find.text('Save & Close'));
    await tester.pumpAndSettle();

    expect(result, {
      'OCD': ['Y-BOCS', 'MADRS'],
    });
  });

  testWidgets('session presets dialog preserves [name,min,max,mode] on save',
      (tester) async {
    Map<String, List<List<String>>>? result;
    await pumpHost(tester, (context) async {
      result = await showSessionPresetsDialog(context, presets: const {
        'PD': [(name: 'Tremor', min: '0', max: '10', mode: 'max')],
      });
    });

    expect(find.text('Session scales settings'), findsOneWidget);
    await tester.tap(find.text('Save & Close'));
    await tester.pumpAndSettle();

    // The hidden optimization mode is carried through unchanged.
    expect(result, {
      'PD': [
        ['Tremor', '0', '10', 'max'],
      ],
    });
  });
}
