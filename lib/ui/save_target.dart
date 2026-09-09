import 'dart:io';

/// Whether a path handed back by the document picker autosaves back to the
/// file the user actually chose.
///
/// On Android and desktop it does: [path] points at the real file, so the
/// desktop-parity "autosave after every insert" round-trips. On iOS/iPadOS it
/// does not — `UIDocumentPickerViewController` copies the selection into the
/// app sandbox and returns the copy, so writes never reach the original in
/// Files / iCloud. Autosaving to the copy is still worth doing (it survives a
/// crash and costs nothing), but the UI must not imply the original changed.
bool pickedPathAutosavesToOriginal(String? path) =>
    path != null && !Platform.isIOS;

/// Shown wherever a sandbox-copy save path is in effect, so "autosaved" is
/// never read as "written back to your file".
const String sandboxCopyNotice =
    'Autosave keeps edits inside the app only — the file you opened is not '
    'updated. Use Export to save your changes.';

/// The final segment of [path], handling both separators.
///
/// Named and shared because the two call sites that needed it both had the same
/// broken copy: `path.replaceAll(r'', '/').split('/').last`. That `r''` is an
/// EMPTY raw string - very likely a `r'\'` that could not compile, since a raw
/// string may not end in a backslash - so `replaceAll` inserted a `/` between
/// every character and `.last` was therefore *always* the empty string.
///
/// It failed silently and invisibly: this feeds `sourceFile` on
/// `SessionReportData`, and all four report builders render the provenance line
/// as `sourceFile.isEmpty ? '' : ' | Source: ...'`. So every PDF and Word report
/// exported from the session and annotations screens was filed into a patient
/// record with no record of which file produced it. Only
/// single_session_report_screen escaped, because it passes its own filename.
String pickedBasename(String path) =>
    path.replaceAll('\\', '/').split('/').last;
