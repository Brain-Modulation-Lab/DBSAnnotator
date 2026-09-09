import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

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

/// The filesystem path for a URI handed back by the picker, or null when the
/// platform gave us something `dart:io` cannot open.
///
/// file_picker 12 returns a [Uri] from `saveFile` rather than a path, and its
/// own documentation is explicit that the scheme "may be `file`, `content`,
/// `http(s)`, `data` or `blob`" depending on platform. Only `file` can back an
/// autosave. This mirrors what `PlatformFile.path` does internally, so the two
/// halves of the app agree on what counts as a real path.
String? pickerUriToPath(Uri? uri) =>
    uri != null && uri.scheme == 'file' ? uri.toFilePath() : null;

/// Read a picked file as text, or null if it could not be read.
///
/// One owner for what four screens each had their own copy of, and each copy
/// was `picked.bytes != null ? utf8.decode(picked.bytes!) : await
/// File(picked.path!).readAsString()` - a force-unwrap that threw on any
/// platform handing back bytes without a path. `readAsBytes` is file_picker 12's
/// replacement for the deprecated `withData` flag and works on every platform,
/// so the two-branch dance is gone.
///
/// Returns null rather than throwing, because every call site wants to name the
/// file in its own message.
Future<String?> readPickedText(PlatformFile picked) async {
  try {
    return utf8.decode(await picked.readAsBytes());
  } catch (_) {
    return null;
  }
}

/// Where a newly created TSV ended up.
typedef NewTsvTarget = ({
  /// Path for autosave to write back to, or null when the platform returned a
  /// non-`file` URI. Null means "recorded data lives only in this app".
  String? path,

  /// Destination to show the user.
  String location,

  /// True when no save dialog could be shown and a default directory was used.
  bool fellBack,
});

/// Ask the user where to create a new TSV, seed it with [header], and report
/// where it went. Returns null if they cancelled.
///
/// Collapses the two near-identical copies the session and annotations screens
/// each carried. file_picker 12 requires `bytes` and writes the file itself, so
/// the old "get a path, then write the header" pair is now one atomic step that
/// cannot half-succeed.
Future<NewTsvTarget?> createNewTsv({
  required String dialogTitle,
  required String fileName,
  required String header,
}) async {
  final bytes = Uint8List.fromList(utf8.encode(header));
  try {
    final uri = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      bytes: bytes,
      mimeType: 'text/tab-separated-values',
      type: FileType.custom,
      allowedExtensions: const ['tsv'],
    );
    if (uri == null) return null; // cancelled
    final path = pickerUriToPath(uri);
    return (path: path, location: path ?? uri.toString(), fellBack: false);
  } catch (_) {
    // No dialog available. On a bare Linux box that means zenity/kdialog is
    // missing; a real dialog appears once it is installed, or on a tablet.
    final dir = await getApplicationDocumentsDirectory();
    await Directory(dir.path).create(recursive: true);
    final path = _unusedPath(dir.path, fileName);
    await File(path).writeAsString(header);
    return (path: path, location: path, fellBack: true);
  }
}

/// `<dir>/<fileName>`, suffixed `-2`, `-3`, ... if that name is taken.
///
/// The fallback path above has no dialog, so nothing warns about overwriting -
/// and the BIDS session stamp is DATE-only while Patient ID and Run both
/// default to `01`. Same patient, same run, same day meant an identical
/// filename, and the old code wrote the bare header straight over it: a
/// morning's recorded visit truncated to a header by an afternoon "New", with
/// no prompt and no recovery.
String _unusedPath(String dir, String fileName) {
  if (!File('$dir/$fileName').existsSync()) return '$dir/$fileName';
  final dot = fileName.lastIndexOf('.');
  final stem = dot < 0 ? fileName : fileName.substring(0, dot);
  final ext = dot < 0 ? '' : fileName.substring(dot);
  for (var n = 2; n < 1000; n++) {
    final candidate = '$dir/$stem-$n$ext';
    if (!File(candidate).existsSync()) return candidate;
  }
  return '$dir/$stem-${DateTime.now().millisecondsSinceEpoch}$ext';
}
