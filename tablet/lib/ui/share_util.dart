import 'dart:io';

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

/// Hand [file] to the OS share sheet (Android / iPadOS). On desktop — notably
/// Linux, where `share_plus` has no share-sheet implementation — fall back to
/// copying it into the Documents folder so export still works, reporting the
/// destination via [messenger].
///
/// Pass a captured [ScaffoldMessengerState] (resolved before the first await)
/// so the snackbar is safe across the async gap.
///
/// [origin] anchors the sheet. iPadOS presents it as a popover off a source
/// rect and gives no sensible default, so pass the triggering button's bounds
/// via [shareOriginFrom]; Android ignores it.
Future<void> shareOrSaveFile(
  ScaffoldMessengerState messenger,
  File file,
  String filename, {
  Rect? origin,
}) async {
  try {
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: filename,
      sharePositionOrigin: origin,
    );
  } catch (_) {
    final dir = await getApplicationDocumentsDirectory();
    await Directory(dir.path).create(recursive: true);
    final dest = '${dir.path}/$filename';
    await file.copy(dest);
    messenger.showSnackBar(
      SnackBar(content: Text('Sharing unavailable here; saved to $dest')),
    );
  }
}
