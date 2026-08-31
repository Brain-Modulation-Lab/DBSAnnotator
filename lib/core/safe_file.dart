/// Crash-safe, order-preserving writes to the user's working data file.
///
/// ## Why this exists
///
/// The autosave path rewrites the whole session TSV after every insert, and it
/// was doing so with a bare `File.writeAsString`, un-awaited. That has two
/// failure modes on a clinician's only copy of the data:
///
/// - `writeAsString` **truncates and then writes**, so a crash, a full disk or a
///   yanked USB stick mid-write leaves a truncated or empty TSV. The previous
///   good contents are already gone.
/// - Two inserts in quick succession start two un-awaited writes to the same
///   path, which can interleave and produce a file that is neither version.
///
/// [SafeFileWriter] fixes both: it writes to a sibling temp file and then
/// **renames** it over the target (an atomic replace on every platform we ship),
/// so the target is only ever the old contents or the new ones — never a
/// half-written mixture. And it chains writes so they land in call order even
/// when the caller does not await.
library;

import 'dart:async';
import 'dart:io';

/// Atomically replace [path]'s contents with [contents].
///
/// Writes `<path>.tmp` (flushed to the OS) and renames it over [path].
///
/// The guarantee is that a reader never sees a **partial** file: it sees the old
/// contents or the new ones, never a mixture. Two Windows realities, both found
/// by `safe_file_test.dart` rather than by reasoning:
///
/// - the replace can make the target momentarily *unopenable* for a reader — a
///   transient lock, not data loss;
/// - the replace itself can *fail* when something else holds the target open (a
///   reader, antivirus, the search indexer). Those locks clear in milliseconds,
///   so the replace is retried with a short backoff.
///
/// Deliberately never deletes the target: an earlier version fell back to
/// delete-then-rename, which is both unnecessary (delete fails on a locked file
/// too) and worse (it opens a window where neither file exists). If every retry
/// fails this throws with the **old file intact and the new data preserved in
/// `.tmp`** — nothing is lost either way.
Future<void> writeStringAtomic(String path, String contents) async {
  final tmp = File('$path.tmp');
  await tmp.writeAsString(contents, flush: true);
  var delay = const Duration(milliseconds: 15);
  for (var attempt = 0;; attempt++) {
    try {
      await tmp.rename(path);
      return;
    } on FileSystemException {
      if (attempt >= 5) rethrow;
      await Future<void>.delayed(delay);
      delay *= 2;
    }
  }
}

/// Serialises [writeStringAtomic] calls so overlapping saves cannot interleave.
///
/// Hold one per file being autosaved. Callers may ignore the returned future;
/// the write still happens, in order.
class SafeFileWriter {
  Future<void> _chain = Future<void>.value();

  /// True while a queued write has not yet completed.
  bool get isBusy => _busy > 0;
  int _busy = 0;

  /// Queue an atomic write of [contents] to [path].
  Future<void> write(String path, String contents) {
    _busy++;
    final next = _chain.then((_) => writeStringAtomic(path, contents));
    // Swallow errors on the CHAIN only, so one failed write cannot poison every
    // later save; the returned future still surfaces the error to its caller.
    _chain = next.then((_) {}, onError: (_) {});
    return next.whenComplete(() => _busy--);
  }

  /// Completes when every queued write has finished. For tests and for a clean
  /// shutdown.
  Future<void> get settled => _chain;
}
