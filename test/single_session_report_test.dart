/// The from-a-file report screen, and the home screen that reaches it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/ui/home_screen.dart';
import 'package:dbs_annotator/ui/single_session_report_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ElectrodeCatalog> _catalog() async => ElectrodeCatalog.fromJson(
  jsonDecode(File('assets/schema/electrode_models.json').readAsStringSync())
      as Map<String, dynamic>,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('home screen', () {
    testWidgets('groups the four entries under Record and Reports', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

      expect(find.text('RECORD'), findsOneWidget);
      expect(find.text('REPORTS'), findsOneWidget);
      for (final title in [
        'Complete workflow',
        'Annotations only',
        'Single session report',
        'Longitudinal review',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
    });

    testWidgets('recording comes before reporting on screen', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      // A flat list put "review last year's visits" next to "start seeing a
      // patient now"; the order now follows the two questions.
      expect(y('RECORD'), lessThan(y('Complete workflow')));
      expect(y('Annotations only'), lessThan(y('REPORTS')));
      expect(y('REPORTS'), lessThan(y('Single session report')));
    });

    testWidgets('both recording entries share the annotate icon', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      // They differ by how much they capture, not by what kind of act they are.
      expect(find.byIcon(Icons.edit_note), findsNWidgets(2));
    });
  });

  group('single session report screen', () {
    testWidgets('opens on a prompt, with no export offered yet', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: SingleSessionReportScreen(catalog: await _catalog())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Single session report'), findsOneWidget);
      expect(find.text('Open TSV'), findsOneWidget);
      expect(find.text('No file opened.'), findsOneWidget);
      // Nothing to export until something is open, so the control is absent
      // rather than present and inert.
      expect(find.byTooltip('Export report'), findsNothing);
    });

    test('the screen composes rather than reimplements', () {
      // This screen legitimately owns file-kind detection, the targets and
      // section choice, and two report families (session and notes) across
      // two formats. What it must not do is reimplement anything shared, and
      // the line bound is what makes a slide back into that visible.
      final src = File(
        'lib/ui/single_session_report_screen.dart',
      ).readAsLinesSync();
      final code = src.where((l) {
        final t = l.trim();
        return t.isNotEmpty && !t.startsWith('//') && !t.startsWith('///');
      }).length;
      // Deliberately loose: `dart format` decides where lines wrap, so the
      // count moves by a few whenever the formatter's style does. A limit
      // that fails on a reformat only teaches people to raise the limit.
      expect(
        code,
        lessThan(360),
        reason: 'code lines excluding comments and blanks: $code',
      );

      // The composition itself: these must come from elsewhere.
      final text = src.join(String.fromCharCode(10));
      for (final shared in [
        'SessionEntriesTable(',
        'EntryChartsView(',
        'showScaleTargetsDialog(',
        'showReportSectionsDialog(',
        'renderReportGraphics(',
        'exportFile(',
        'buildSessionReportData(',
        'buildAnnotationsReportData(',
      ]) {
        expect(text, contains(shared), reason: shared);
      }
    });
  });
}
