import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The version number is written in four places. This fails if they disagree.
///
/// `pubspec.yaml`'s `version:` is the source of truth, and most consumers derive
/// from it automatically: the Android `versionCode`/`versionName`, the iOS and
/// macOS `FLUTTER_BUILD_NAME`, the Windows `FILEVERSION` (via CMake into
/// `windows/runner/Runner.rc`), and the documentation footer (`docs/conf.py`
/// regex-parses the pubspec and raises if it is missing).
///
/// Three restate it because they cannot read it:
///
/// * `lib/app_info.dart`'s `appVersion` — Dart cannot read the pubspec at
///   runtime without a native plugin. It reaches every report footer, the PDF
///   `/Info` dictionary and the docx `docProps`, so a stale value here is filed
///   in a patient record.
/// * `CITATION.cff`'s `version:` — static metadata; GitHub and Zenodo read it.
/// * `msix_config`'s `msix_version` — needs a fourth component, which the
///   pubspec `major.minor.patch+build` grammar has no room for. Microsoft
///   reserves that fourth field for Store use and requires it to be 0.
///
/// Without this test a release bump that updated three of the four would ship a
/// report claiming one version and a Store listing claiming another, with
/// nothing failing anywhere.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  /// First capture of [pattern] in [text], or null. Regexes rather than a YAML
  /// parser: these are all top-level scalars, and the test should not need a
  /// dependency the app does not have.
  String? firstMatch(String text, String pattern) =>
      RegExp(pattern, multiLine: true).firstMatch(text)?.group(1);

  test('pubspec declares a parseable version', () {
    expect(firstMatch(pubspec, r'^version:\s*([0-9][^\s+#]*)'), isNotNull,
        reason:
            'pubspec.yaml must declare `version: <major.minor.patch>+<build>`.');
  });

  final version = firstMatch(pubspec, r'^version:\s*([0-9][^\s+#]*)')!;

  test('lib/app_info.dart appVersion matches the pubspec', () {
    final appInfo = File('lib/app_info.dart').readAsStringSync();
    expect(
      firstMatch(appInfo, r"""^const String appVersion = '([^']+)';"""),
      version,
      reason: 'appVersion in lib/app_info.dart must equal `version:` in '
          'pubspec.yaml ($version). It is printed on every report.',
    );
  });

  test('CITATION.cff version matches the pubspec', () {
    final citation = File('CITATION.cff').readAsStringSync();
    // `cff-version:` also matches a bare `version:` search, so anchor on a
    // line that starts with it.
    expect(
      firstMatch(citation, r'^version:\s*(\S+)'),
      version,
      reason: 'version: in CITATION.cff must equal `version:` in '
          'pubspec.yaml ($version).',
    );
  });

  test('msix_version matches the pubspec, with the Store-reserved 0 revision',
      () {
    final msixVersion = firstMatch(pubspec, r'^\s+msix_version:\s*(\S+)');
    expect(msixVersion, isNotNull,
        reason: 'msix_config in pubspec.yaml must declare msix_version.');
    expect(
      msixVersion,
      '$version.0',
      reason: 'msix_version must be `<pubspec version>.0`: four components, '
          'with the fourth left 0 because Microsoft reserves the revision '
          'field for Store use. Expected $version.0.',
    );
  });

  // NOT asserted here, deliberately: Microsoft's package-requirements page says
  // "The other sections must be set to an integer between 0 and 65535 (except
  // for the first section, which cannot be 0)", which would make a 0.x
  // msix_version invalid. But that sentence sits in a section about UWP
  // packages, and whether Partner Center enforces it for a packaged desktop
  // (Win32) MSIX is not established. Failing the whole suite on an unconfirmed
  // reading of a doc would be worse than finding out at upload — package
  // validation runs before review, so the feedback is immediate and free.
  // If it is rejected, bump the major version and this test still holds.
}
