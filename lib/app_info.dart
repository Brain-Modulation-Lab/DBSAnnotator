import 'package:flutter/material.dart';

/// App identity + Help/About, mirroring the desktop `config.py` values and the
/// wizard's Help dialog.
const String appName = 'DBS Annotator';

/// Restates `version:` from pubspec.yaml, which is the source of truth.
///
/// Dart cannot read the pubspec at runtime without a native plugin, so this is
/// a literal — but `test/version_parity_test.dart` fails if it drifts. It
/// reaches every report footer, the PDF `/Info` dictionary and the docx
/// `docProps`, so a stale value here is filed in a patient record.
const String appVersion = '0.5.0';
const String repoUrl = 'https://github.com/Brain-Modulation-Lab/DBSAnnotator';
const String issuesUrl = '$repoUrl/issues';
const String contactEmail = 'lucia.poma@wysscenter.ch';
const String publisher = 'Wyss Center for Bio and Neuroengineering';
const String copyrightHolders =
    'Wyss Center for Bio and Neuroengineering, Massachusetts General Hospital, '
    'and Charité Universitätsmedizin Berlin';

/// The app mark, bundled from `icons/logosimple/`. Declared in pubspec assets.
const String appIconAsset = 'assets/icon/app_icon.png';

/// The app mark as a widget, for AppBars and dialogs.
///
/// [size] is the logical height; the mark is square. Falls back to a Material
/// glyph if the asset is somehow missing, so a packaging slip degrades to an
/// icon rather than a red error box in the AppBar.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        appIconAsset,
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.psychology_outlined, size: size),
      );
}

/// Desktop-style Help/About dialog: name + version, workflow overview,
/// copyright/license, and the repository / issues / contact URLs as
/// SelectableText (copy to open — avoids a url_launcher dependency).
void showAppAbout(BuildContext context) {
  showAboutDialog(
    context: context,
    applicationName: appName,
    applicationVersion: 'v$appVersion',
    applicationIcon: const AppLogo(size: 48),
    children: const [
      SizedBox(height: 8),
      Text('Annotate DBS programming sessions: file setup → initial '
          'configuration → session-scales configuration → active recording. '
          'Writes BIDS behavioural TSV with a JSON sidecar documenting every '
          'column, and exports PDF and Word reports.'),
      SizedBox(height: 12),
      Text('Links (select to copy):',
          style: TextStyle(fontWeight: FontWeight.w600)),
      SelectableText('Repository: $repoUrl'),
      SelectableText('Issues: $issuesUrl'),
      SelectableText('Contact: $contactEmail'),
      SizedBox(height: 12),
      Text('© 2026 $copyrightHolders'),
      Text('MIT License. Publisher: $publisher.'),
    ],
  );
}

/// Shared AppBar action opening [showAppAbout].
class HelpButton extends StatelessWidget {
  const HelpButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        icon: const Icon(Icons.help_outline),
        iconSize: 28,
        tooltip: 'Help / about',
        onPressed: () => showAppAbout(context),
      );
}
