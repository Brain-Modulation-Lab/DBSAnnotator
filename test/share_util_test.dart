/// The export delivery path's pure functions.
///
/// `lib/ui/share_util.dart` had zero test coverage while carrying the code that
/// decides where every exported report goes. Delivery itself needs a device -
/// the share sheet and the Save-As dialog are native - but the two decisions
/// made *before* the platform is asked are pure, and both have already been the
/// site of a real bug.
library;

import 'dart:ui';

import 'package:dbs_annotator/ui/share_util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mimeTypeFor', () {
    // Not cosmetic: Android's MimeTypeMap does not know `.docx`, so without an
    // explicit type the share sheet degrades to a generic `*/*` chooser and
    // some target apps refuse the file outright.
    test('.docx is the full OOXML wordprocessing type', () {
      expect(
        mimeTypeFor('sub-01_report.docx'),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
    });

    test('.pdf, .tsv and .zip', () {
      expect(mimeTypeFor('r.pdf'), 'application/pdf');
      expect(mimeTypeFor('s.tsv'), 'text/tab-separated-values');
      expect(mimeTypeFor('d.zip'), 'application/zip');
    });

    test('is case-insensitive, since a user can rename a file', () {
      expect(mimeTypeFor('REPORT.PDF'), 'application/pdf');
      expect(mimeTypeFor('Session.TSV'), 'text/tab-separated-values');
    });

    test('an unknown extension and a bare name yield null, not a guess', () {
      expect(mimeTypeFor('notes.rtf'), isNull);
      expect(mimeTypeFor('noextension'), isNull);
      expect(mimeTypeFor(''), isNull);
    });

    test('only the last extension counts', () {
      expect(mimeTypeFor('sub-01_ses-1.task.pdf'), 'application/pdf');
    });
  });

  group('safeOrigin', () {
    const screen = Size(1024, 768);

    // The bug this exists to prevent, from Round 11: share_plus's iOS plugin
    // THROWS when a popover is required and the origin is null or empty. The
    // throw sent the export down the disk-save path and into the app container,
    // while the snackbar still claimed success. So an empty rect must be
    // treated exactly like a null one - it is not merely "unusual input".
    test('an empty rect is replaced, not passed through', () {
      final origin = safeOrigin(Rect.zero, screen);
      expect(origin.isEmpty, isFalse);
      expect(origin.center, const Offset(512, 384));
    });

    test('a null origin falls back to the centre of the screen', () {
      final origin = safeOrigin(null, screen);
      expect(origin.isEmpty, isFalse);
      expect(origin.center, const Offset(512, 384));
    });

    test(
      'a zero-width but non-zero-height rect is still empty, so replaced',
      () {
        final origin = safeOrigin(const Rect.fromLTWH(10, 10, 0, 40), screen);
        expect(origin.center, const Offset(512, 384));
      },
    );

    test('a real laid-out rect passes through untouched', () {
      const button = Rect.fromLTWH(700, 40, 120, 44);
      expect(safeOrigin(button, screen), button);
    });
  });

  group('shareOriginFrom', () {
    test('a null context yields null, which shareOrSaveFile tolerates', () {
      expect(shareOriginFrom(null), isNull);
    });
  });
}
