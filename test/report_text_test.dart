import 'package:dbs_annotator/report/report_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sanitiseForLatin1', () {
    test('passes plain ASCII through untouched', () {
      const s = 'Paresthesia at 2.5 mA, resolved after 30 s.';
      final r = sanitiseForLatin1(s);
      expect(r.text, s);
      expect(r.replaced, isFalse);
    });

    test('passes Latin-1 accents and the micro sign through', () {
      // These are exactly the characters Helvetica CAN encode, so they must not
      // be touched: 'µs' appears in our own table headers.
      const s = 'Contrôle à 60 µs, ±0.5 °C, café';
      final r = sanitiseForLatin1(s);
      expect(r.text, s);
      expect(r.replaced, isFalse);
    });

    test('maps iOS smart punctuation faithfully, without flagging loss', () {
      final r = sanitiseForLatin1('‘tremor’ “better” – much — improved…');
      expect(r.text, "'tremor' \"better\" - much - improved...");
      // Faithful substitutions are not data loss, so no warning.
      expect(r.replaced, isFalse);
    });

    test('maps clinical symbols', () {
      final r = sanitiseForLatin1('≥ 3 mA, ≤ 5 V, ≠ baseline');
      expect(r.text, '>= 3 mA, <= 5 V, != baseline');
      expect(r.replaced, isFalse);
    });

    test('maps GREEK MU to the Latin-1 MICRO SIGN, not to "?"', () {
      // U+03BC (Greek mu) is NOT Latin-1; U+00B5 (micro sign) is. Word
      // autocorrect and some keyboards produce the former.
      final r = sanitiseForLatin1('60 μs');
      expect(r.text, '60 µs');
      expect(r.replaced, isFalse);
    });

    test('maps non-breaking and thin spaces to a plain space', () {
      final r = sanitiseForLatin1('130 Hz and 60  µs');
      expect(r.text, '130 Hz and 60  µs');
      expect(r.replaced, isFalse);
    });

    test('replaces genuinely unsupported characters and reports the loss', () {
      final r = sanitiseForLatin1('注意 ❤');
      expect(r.text, '?? ?');
      expect(r.replaced, isTrue);
    });

    test('handles the empty string', () {
      expect(sanitiseForLatin1('').text, '');
      expect(sanitiseForLatin1('').replaced, isFalse);
    });

    test('every replacement maps INTO Latin-1', () {
      // A mapping whose output is itself unencodable would defeat the purpose,
      // which is exactly the trap the Greek-mu case above falls into.
      const probes = '‘’‚‛“”„′″'
          '–—―−…•   '
          '≥≤≠≈×→←↑↓'
          'Δμ℃℉';
      final out = sanitiseForLatin1(probes);
      expect(out.replaced, isFalse,
          reason: 'a known character fell through to "?"');
      for (final rune in out.text.runes) {
        expect(rune, lessThanOrEqualTo(0xFF),
            reason: 'replacement emitted U+${rune.toRadixString(16)}, '
                'which Helvetica cannot encode');
      }
    });
  });

  group('ReportTextSanitiser', () {
    test('passes through whatever the loaded font covers', () {
      // `’` is in the substitution table, so it is normalised either way; `注意`
      // is not, so coverage is the only thing that decides its fate. The set is
      // authoritative — ASCII is in it because every real font has it, not
      // because the sanitiser assumes it.
      final s = ReportTextSanitiser(coverage: {
        for (var r = 0x20; r < 0x7f; r++) r,
        ...'注意'.runes,
      });
      expect(s('注意 ’'), "注意 '");
      expect(s.lostCharacters, isFalse);
    });

    test('tracks loss across many calls', () {
      final s = ReportTextSanitiser();
      expect(s('fine'), 'fine');
      expect(s.lostCharacters, isFalse);
      s('’ still fine');
      expect(s.lostCharacters, isFalse, reason: 'faithful substitution');
      s('注');
      expect(s.lostCharacters, isTrue);
    });

    test('sanitises table rows', () {
      final s = ReportTextSanitiser();
      final out = s.rows([
        ['1', 'L', '‘A’'],
        ['1', 'R', '注'],
      ]);
      expect(out[0][2], "'A'");
      expect(out[1][2], '?');
      expect(s.lostCharacters, isTrue);
    });
  });
}
