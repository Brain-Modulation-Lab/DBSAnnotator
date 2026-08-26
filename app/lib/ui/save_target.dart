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
