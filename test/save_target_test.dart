/// The single decision point for "does writing reach the clinician's file",
/// plus the basename helper the report provenance line depends on.
///
/// Nineteen lines of code with no test, and both of the defects it now guards
/// were invisible in exactly the same way: they produced a plausible-looking
/// result rather than an error.
library;

import 'package:dbs_annotator/ui/save_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pickedBasename', () {
    // The regression. Both call sites carried
    // `path.replaceAll(r'', '/').split('/').last`, where `r''` is an EMPTY raw
    // string (almost certainly an `r'\'` that could not compile - a raw string
    // may not end in a backslash). `replaceAll('', '/')` inserts a separator
    // between every character, so `.split('/').last` was ALWAYS ''. Every
    // report builder renders provenance as `sourceFile.isEmpty ? '' : ...`, so
    // every PDF and Word report from the session and annotations screens was
    // filed with no record of which file produced it.
    test('is never empty for a real path (the provenance regression)', () {
      const windows = r'C:\Users\clinician\Documents\sub-01_beh.tsv';
      const posix = '/home/clinician/documents/sub-01_beh.tsv';
      for (final path in [windows, posix, 'sub-01_beh.tsv']) {
        expect(pickedBasename(path), isNotEmpty, reason: path);
        expect(pickedBasename(path), 'sub-01_beh.tsv', reason: path);
      }
    });

    test('handles a Windows path', () {
      expect(
        pickedBasename(r'C:\Users\lucia\sub-01_ses-20260909_beh.tsv'),
        'sub-01_ses-20260909_beh.tsv',
      );
    });

    test('handles a POSIX path', () {
      expect(pickedBasename('/var/mobile/Documents/notes.tsv'), 'notes.tsv');
    });

    test('handles mixed separators, as Windows itself accepts', () {
      expect(pickedBasename(r'C:\Users\lucia/Documents\x.tsv'), 'x.tsv');
    });

    test('a bare filename is returned unchanged', () {
      expect(pickedBasename('x.tsv'), 'x.tsv');
    });

    test('a trailing separator yields empty rather than throwing', () {
      // Not a case the pickers produce, but it must not throw: the value is
      // interpolated straight into a clinical document's header.
      expect(pickedBasename('/a/b/'), '');
    });
  });

  group('pickedPathAutosavesToOriginal', () {
    test('a null path never autosaves anywhere', () {
      expect(pickedPathAutosavesToOriginal(null), isFalse);
    });

    // Platform-dependent beyond this point, and WP2's subject: the reviews
    // established that Android's picker also returns a CACHE copy
    // (file_picker's Android delegate copies into getCacheDir()), so the
    // current `!Platform.isIOS` test reports write-back on a platform where
    // there is none. Asserting the true per-platform answer needs a device, so
    // it is deliberately not asserted here - see the WP2 section of the plan.
    test('a non-null path is answered without throwing on this host', () {
      expect(pickedPathAutosavesToOriginal('/tmp/x.tsv'), isA<bool>());
    });
  });

  group('sandboxCopyNotice', () {
    test('says both what autosave does and what to do instead', () {
      expect(sandboxCopyNotice, contains('not'));
      expect(sandboxCopyNotice.toLowerCase(), contains('export'));
    });
  });
}
