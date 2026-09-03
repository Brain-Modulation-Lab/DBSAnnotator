import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Global bounds of the widget at [context], for [shareOrSaveFile]'s `origin`.
///
/// Attach a [GlobalKey] to the button that triggers the export and pass its
/// `currentContext` here, in the button's callback and *before* the first
/// await — after one the widget may be gone. Returns null if the widget is not
/// laid out, which [shareOrSaveFile] tolerates.
Rect? shareOriginFrom(BuildContext? context) {
  final box = context?.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

bool get _isMobile => Platform.isAndroid || Platform.isIOS;

/// MIME type for the file kinds we export. Android's `MimeTypeMap` does not
/// know `.docx`, so without an explicit type the share sheet degrades to a
/// generic `*/*` chooser and some target apps refuse the file.
String? mimeTypeFor(String filename) {
  final ext = _ext(filename).toLowerCase();
  return switch (ext) {
    '.pdf' => 'application/pdf',
    '.docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.tsv' => 'text/tab-separated-values',
    '.zip' => 'application/zip',
    _ => null,
  };
}

/// A non-empty popover anchor for the iPad share sheet.
///
/// share_plus's iOS plugin **throws** when a popover is required and the origin
/// is null or empty (`FPPSharePlusPlugin.m`), which used to send the export down
/// the disk-save path and into the app container. A centred fallback keeps the
/// sheet presentable even when the triggering button is not laid out.
Rect _safeOrigin(Rect? origin, Size screen) {
  if (origin != null && !origin.isEmpty) return origin;
  return Rect.fromCenter(
    center: Offset(screen.width / 2, screen.height / 2),
    width: 1,
    height: 1,
  );
}

/// Deliver [file] to the user: the OS share sheet on mobile (Android / iPadOS),
/// or a saved copy on desktop, where `share_plus` has no share sheet. Never
/// throws, and always reports the outcome via [messenger] so an export can
/// never fail silently.
///
/// Pass a captured [ScaffoldMessengerState] (resolved before the first await)
/// so the snackbar is safe across the async gap. [origin] anchors the iPadOS
/// share popover (see [shareOriginFrom]); other platforms ignore it. [screen]
/// supplies the fallback anchor — pass `MediaQuery.sizeOf(context)`.
Future<void> shareOrSaveFile(
  ScaffoldMessengerState messenger,
  File file,
  String filename, {
  Rect? origin,
  Size screen = const Size(768, 1024),
}) async {
  if (_isMobile) {
    try {
      final result = await Share.shareXFiles(
        [XFile(file.path, mimeType: mimeTypeFor(filename))],
        subject: filename,
        sharePositionOrigin: _safeOrigin(origin, screen),
      );
      // Confirm on mobile too: previously the happy path returned silently, so
      // a dismissed sheet was indistinguishable from a completed share.
      if (result.status != ShareResultStatus.unavailable) {
        messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(result.status == ShareResultStatus.success
              ? 'Shared $filename'
              : 'Export ready: $filename'),
        ));
        return;
      }
    } catch (e) {
      debugPrint('Share sheet unavailable for $filename: $e');
      // Fall through to a disk save.
    }
  }
  final saved = await _saveToDisk(file, filename);
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 6),
      content: Text(
        saved != null ? 'Saved to $saved' : 'Could not save $filename',
      ),
    ),
  );
}

/// What an export produced: the file's bytes, and an optional warning to show
/// after it has been delivered (e.g. the PDF sanitiser replaced a character).
typedef ExportPayload = ({List<int> bytes, String? warning});

/// Build a file and deliver it, reporting every failure.
///
/// One home for the sequence five call sites each had their own copy of:
/// capture the messenger / screen / share anchor **before** the first await,
/// build the bytes, write a temp file, share-or-save, and turn any throw into a
/// snackbar. Capturing up front is not a style point — a menu item is unmounted
/// by the time the iPad share sheet needs its anchor, and using a `BuildContext`
/// across an await is exactly the bug `use_build_context_synchronously` warns
/// about.
///
/// [anchor] is the key on the widget the share popover should point at; pass the
/// enclosing button, not a menu item that is about to disappear.
Future<void> exportFile(
  BuildContext context, {
  required String filename,
  required Future<ExportPayload> Function() build,
  GlobalKey? anchor,
  String failureLabel = 'Export failed',
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final screen = MediaQuery.sizeOf(context);
  final origin = shareOriginFrom(anchor?.currentContext);
  try {
    final payload = await build();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(payload.bytes);
    await shareOrSaveFile(messenger, file, filename,
        origin: origin, screen: screen);
    final warning = payload.warning;
    if (warning != null) {
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(warning),
      ));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$failureLabel: $e')));
  }
}

/// Save [file] to a user-visible location: a native Save-As dialog first, then
/// the first writable well-known directory. Returns the destination path, or
/// null if every option failed. Never throws.
Future<String?> _saveToDisk(File file, String filename) async {
  // 1) Native Save-As dialog (desktop with zenity/kdialog; a document picker on
  //    mobile). Absent on a bare Linux box → the auto-save below runs instead.
  try {
    final picked = await FilePicker.platform.saveFile(
      dialogTitle: 'Save $filename',
      fileName: filename,
    );
    if (picked != null) {
      final ext = _ext(filename);
      final dest = picked.endsWith(ext) ? picked : '$picked$ext';
      await file.copy(dest);
      return dest;
    }
  } catch (_) {
    // No dialog available — auto-save below.
  }

  // 2) First writable well-known directory. Application-support is
  //    XDG-user-dirs-independent, so it resolves even on a minimal Linux box
  //    where Downloads/Documents are unset.
  final getters = <Future<Directory?> Function()>[
    getDownloadsDirectory,
    getApplicationDocumentsDirectory,
    getApplicationSupportDirectory,
  ];
  for (final getDir in getters) {
    try {
      final dir = await getDir();
      if (dir == null) continue;
      await Directory(dir.path).create(recursive: true);
      final dest = '${dir.path}/$filename';
      await file.copy(dest);
      return dest;
    } catch (_) {
      // Try the next location.
    }
  }

  // 3) The temp file already exists; report its path as a last resort.
  return file.path;
}

/// The extension of [filename] including the dot ('' when there is none).
String _ext(String filename) {
  final i = filename.lastIndexOf('.');
  return i < 0 ? '' : filename.substring(i);
}
