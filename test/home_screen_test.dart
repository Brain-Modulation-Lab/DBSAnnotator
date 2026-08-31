import 'package:dbs_annotator/app_info.dart';
import 'package:dbs_annotator/ui/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();
  }

  testWidgets('shows the app mark and every workflow option', (tester) async {
    await pumpHome(tester);

    // Branding: the logo, not just a text title.
    expect(find.byType(AppLogo), findsWidgets);
    expect(find.text(appName), findsOneWidget);

    // Every entry point is reachable. Group 4 adds "Single session report"
    // here; this list is the regression gate for that restructure.
    expect(find.text('Complete workflow'), findsOneWidget);
    expect(find.text('Annotations only'), findsOneWidget);
    expect(find.text('Longitudinal review'), findsOneWidget);
  });

  testWidgets('the About dialog carries the logo and version', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byTooltip('Help / about'));
    await tester.pumpAndSettle();

    expect(find.text(appName), findsWidgets);
    expect(find.text('v$appVersion'), findsOneWidget);
    // applicationIcon — the mark, not a Material glyph.
    expect(find.byType(AppLogo), findsWidgets);
  });

  testWidgets('AppLogo degrades to an icon when the asset is missing',
      (tester) async {
    // A packaging slip must not put a red error box in the AppBar.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AppLogo(size: 24)),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the logo asset is really bundled, not silently falling back',
      (tester) async {
    // AppLogo has an errorBuilder, which is right for robustness but would hide
    // a packaging mistake. Load the asset directly so a missing or undeclared
    // icon fails loudly here instead of shipping as a Material glyph.
    final data = await rootBundle.load(appIconAsset);
    final bytes = data.buffer.asUint8List();
    expect(bytes.sublist(0, 8),
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        reason: 'not a PNG');
    // The 1024x1024 master, read from the IHDR.
    int be32(int o) => (bytes[o] << 24) | (bytes[o + 1] << 16) |
        (bytes[o + 2] << 8) | bytes[o + 3];
    expect(be32(16), 1024);
    expect(be32(20), 1024);
  });
}
