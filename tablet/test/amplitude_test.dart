import 'package:dbs_annotator_tablet/core/electrode/amplitude.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encode: total 2.5 split 60/40 gives "1.5_1"', () {
    expect(encodeAmplitude(2.5, [60, 40]), '1.5_1');
  });

  test('encode: single or no percentage returns the total on its own', () {
    expect(encodeAmplitude(2.5, [100]), '2.5');
    expect(encodeAmplitude(2.0, []), '2');
    expect(encodeAmplitude(1.25, []), '1.25');
  });

  test('encode: trailing zeros and dot are stripped per part', () {
    // 3.0 * 50% = 1.50 -> "1.5"; 3.0 * 50% = 1.50 -> "1.5"
    expect(encodeAmplitude(3.0, [50, 50]), '1.5_1.5');
    // 4.0 * 50% = 2.00 -> "2"
    expect(encodeAmplitude(4.0, [50, 50]), '2_2');
  });

  test('parse: "1.5_1" gives total 2.5 and 60/40 split', () {
    final parsed = parseAmplitude('1.5_1');
    expect(parsed.total, closeTo(2.5, 1e-9));
    expect(parsed.percentages, hasLength(2));
    expect(parsed.percentages[0], closeTo(60.0, 1e-9));
    expect(parsed.percentages[1], closeTo(40.0, 1e-9));
  });

  test('parse: single value passthrough', () {
    final parsed = parseAmplitude('2.5');
    expect(parsed.total, closeTo(2.5, 1e-9));
    expect(parsed.percentages, [100.0]);
  });

  test('parse: zero total guards divide-by-zero', () {
    final parsed = parseAmplitude('0_0');
    expect(parsed.total, 0.0);
    expect(parsed.percentages, [0.0, 0.0]);
  });

  test('parse: empty parts are ignored', () {
    final parsed = parseAmplitude('1.5__1');
    expect(parsed.total, closeTo(2.5, 1e-9));
    expect(parsed.percentages, hasLength(2));
  });

  test('round-trip: "1.5_1" survives parse -> encode', () {
    final parsed = parseAmplitude('1.5_1');
    expect(encodeAmplitude(parsed.total, parsed.percentages), '1.5_1');
  });

  test('round-trip: single value survives parse -> encode', () {
    final parsed = parseAmplitude('2');
    expect(encodeAmplitude(parsed.total, parsed.percentages), '2');
  });
}
