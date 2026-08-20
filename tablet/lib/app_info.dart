import 'package:flutter/material.dart';

/// App identity + Help/About, mirroring the desktop `config.py` values and the
/// wizard's Help dialog. Keep [appVersion] in sync with pubspec.
const String appName = 'DBS Annotator';
const String appVersion = '0.1.0';
const String repoUrl = 'https://github.com/Brain-Modulation-Lab/DBSAnnotator';
const String issuesUrl = '$repoUrl/issues';
const String contactEmail = 'lucia.poma@wysscenter.ch';
const String publisher = 'Wyss Center for Bio and Neuroengineering';
const String copyrightHolders =
    'Wyss Center for Bio and Neuroengineering, Massachusetts General Hospital, '
    'and Charité Universitätsmedizin Berlin';

/// Desktop-style Help/About dialog: name + version, workflow overview,
/// copyright/license, and the repository / issues / contact URLs as
/// SelectableText (copy to open — avoids a url_launcher dependency).
void showAppAbout(BuildContext context) {
  showAboutDialog(
    context: context,
    applicationName: appName,
    applicationVersion: 'v$appVersion',
    children: const [
      SizedBox(height: 8),
      Text('Annotate DBS programming sessions: file setup → initial '
          'configuration → session-scales configuration → active recording. '
          'Reads/writes the same BIDS TSV as the desktop app and exports PDF '
          'reports.'),
      SizedBox(height: 12),
      Text('Links (select to copy):',
          style: TextStyle(fontWeight: FontWeight.w600)),
      SelectableText('Repository: $repoUrl'),
      SelectableText('Issues: $issuesUrl'),
      SelectableText('Contact: $contactEmail'),
      SizedBox(height: 12),
      Text('© 2025 $copyrightHolders'),
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
        tooltip: 'Help / about',
        onPressed: () => showAppAbout(context),
      );
}
