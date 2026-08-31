import 'dart:io';

import 'package:dbs_annotator/core/safe_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('safe_file_test');
    path = '${dir.path}/session.tsv';
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('writeStringAtomic', () {
    test('creates the file when absent', () async {
      await writeStringAtomic(path, 'a\tb\n');
      expect(File(path).readAsStringSync(), 'a\tb\n');
    });

    test('replaces existing contents', () async {
      File(path).writeAsStringSync('old contents, much longer than the new');
      await writeStringAtomic(path, 'new');
      expect(File(path).readAsStringSync(), 'new');
    });

    test('leaves no .tmp file behind', () async {
      await writeStringAtomic(path, 'x');
      await writeStringAtomic(path, 'y');
      expect(File('$path.tmp').existsSync(), isFalse);
      expect(dir.listSync().map((e) => e.path.split(RegExp(r'[\\/]')).last),
          ['session.tsv']);
    });

    test('round-trips content with CRLF and embedded quotes', () async {
      const tsv = 'date\tnotes\r\n2026-01-01\t"quoted, with comma"\r\n';
      await writeStringAtomic(path, tsv);
      expect(File(path).readAsStringSync(), tsv);
    });
  });

  group('SafeFileWriter', () {
    test('applies overlapping writes in call order', () async {
      final w = SafeFileWriter();
      // Deliberately NOT awaited individually — this is the autosave pattern
      // that previously let two truncate-then-write calls interleave.
      w.write(path, 'first');
      w.write(path, 'second');
      w.write(path, 'third');
      await w.settled;
      expect(File(path).readAsStringSync(), 'third');
    });

    test('a reader never observes a PARTIAL file', () async {
      final w = SafeFileWriter();
      final long = 'x' * 20000;
      await w.write(path, long);
      // Fire overlapping writes and sample throughout. The guarantee is that no
      // read ever returns a half-written mixture — which is exactly what
      // truncate-then-write DID produce. On Windows the replace step can make
      // the target briefly unopenable; that is acceptable (and recoverable),
      // a truncated file is not.
      for (var i = 0; i < 12; i++) {
        w.write(path, i.isEven ? long : 'short');
      }
      var reads = 0;
      for (var i = 0; i < 40; i++) {
        try {
          final seen = File(path).readAsStringSync();
          reads++;
          expect(seen == long || seen == 'short', isTrue,
              reason: 'observed a partial file (${seen.length} chars)');
        } on FileSystemException {
          // Transient lock during the atomic replace — allowed.
        }
        await Future<void>.delayed(Duration.zero);
      }
      await w.settled;
      expect(reads, greaterThan(0), reason: 'never managed to read the file');
      expect(File(path).readAsStringSync(), 'short');
    });

    test('one failed write does not poison later ones', () async {
      final w = SafeFileWriter();
      // A path inside a non-existent directory fails.
      await expectLater(
          w.write('${dir.path}/nope/deeper/x.tsv', 'boom'), throwsA(anything));
      await w.write(path, 'recovered');
      await w.settled;
      expect(File(path).readAsStringSync(), 'recovered');
    });

    test('reports busy state and settles', () async {
      final w = SafeFileWriter();
      expect(w.isBusy, isFalse);
      final f = w.write(path, 'data');
      expect(w.isBusy, isTrue);
      await f;
      expect(w.isBusy, isFalse);
    });
  });
}
