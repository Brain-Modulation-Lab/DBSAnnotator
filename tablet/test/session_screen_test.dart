import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator_tablet/core/electrode/electrode_model.dart';
import 'package:dbs_annotator_tablet/ui/session_screen.dart';
import 'package:dbs_annotator_tablet/ui/stim_params_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Headless smoke test for the Complete-Workflow screen. Contracts are
/// injected from the repo-root schema files (like electrode_catalog_test),
/// so no asset bundle or platform channel is touched; Open/Export are never
/// tapped.
void main() {
  Map<String, dynamic> readJson(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  final catalog =
      ElectrodeCatalog.fromJson(readJson('../schema/electrode_models.json'));
  final limits = StimLimits.fromJson(readJson('../schema/limits.json'));

  testWidgets('empty state renders and a baseline insert appears in the list',
      (tester) async {
    // Tall surface so the lazily-built ListView builds every section
    // (insert button and blocks list included) without scrolling.
    await tester.binding.setSurfaceSize(const Size(1400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: SessionScreen(catalog: catalog, limits: limits),
    ));
    // Let the injected-contracts future resolve.
    await tester.pump();
    await tester.pump();

    expect(find.text('Complete workflow'), findsOneWidget);
    expect(find.text('Select an electrode model'), findsNWidgets(2));
    expect(find.text('No blocks inserted yet.'), findsOneWidget);
    expect(find.text('Baseline (initial) block'), findsOneWidget);
    // Three stim fields per side.
    expect(find.text('Frequency'), findsNWidgets(2));
    expect(find.text('Amplitude'), findsNWidgets(2));
    expect(find.text('Pulse width'), findsNWidgets(2));

    // First insert defaults to the baseline block 0.
    final insertButton = find.text('Insert baseline block 0');
    expect(insertButton, findsOneWidget);
    await tester.ensureVisible(insertButton);
    await tester.tap(insertButton);
    await tester.pump();

    expect(find.text('Baseline (initial)'), findsOneWidget);
    // The toggle auto-flips: the next insert is a recording block 1.
    expect(find.text('Insert recording block 1'), findsOneWidget);
    expect(find.text('No blocks inserted yet.'), findsNothing);
  });

  testWidgets('out-of-range stimulation value blocks the insert',
      (tester) async {
    // Tall surface so the lazily-built ListView builds every section
    // (insert button and blocks list included) without scrolling.
    await tester.binding.setSurfaceSize(const Size(1400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: SessionScreen(catalog: catalog, limits: limits),
    ));
    await tester.pump();
    await tester.pump();

    // First TextFormField with the "Hz" suffix is the Left frequency.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Frequency').first,
      '${limits.frequency.max + 1}',
    );
    await tester.pump();

    final insertButton = find.text('Insert baseline block 0');
    await tester.ensureVisible(insertButton);
    await tester.tap(insertButton);
    await tester.pump();

    expect(
      find.text('Fix out-of-range stimulation values before inserting.'),
      findsOneWidget,
    );
    expect(find.text('No blocks inserted yet.'), findsOneWidget);
  });
}
