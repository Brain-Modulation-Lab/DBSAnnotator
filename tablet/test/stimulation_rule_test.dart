import 'package:dbs_annotator_tablet/core/electrode/contact_state.dart';
import 'package:dbs_annotator_tablet/core/electrode/stimulation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty configuration is valid', () {
    final result = validateConfiguration({}, ContactState.off);
    expect(result.valid, isTrue);
    expect(result.error, '');
  });

  test('bipolar contact pair is valid', () {
    final result = validateConfiguration(
      {
        const ContactKey(0, 0): ContactState.anodic,
        const ContactKey(1, 0): ContactState.cathodic,
      },
      ContactState.off,
    );
    expect(result.valid, isTrue);
    expect(result.error, '');
  });

  test('cathodic contact with anodic case (monopolar) is valid', () {
    final result = validateConfiguration(
      {const ContactKey(1, 1): ContactState.cathodic},
      ContactState.anodic,
    );
    expect(result.valid, isTrue);
    expect(result.error, '');
  });

  test('rule 1: cathodic case forbids cathodic contacts', () {
    final result = validateConfiguration(
      {const ContactKey(0, 0): ContactState.cathodic},
      ContactState.cathodic,
    );
    expect(result.valid, isFalse);
    expect(
      result.error,
      'When CASE is cathodic, no other contacts can be cathodic',
    );
  });

  test('rule 1: cathodic case with only anodic contacts passes rule 1', () {
    // Cathodic case acts as the cathode; anodic contacts are allowed.
    final result = validateConfiguration(
      {const ContactKey(0, 0): ContactState.anodic},
      ContactState.cathodic,
    );
    expect(result.valid, isTrue);
  });

  test('rule 2: anodic case forbids anodic contacts', () {
    final result = validateConfiguration(
      {const ContactKey(2, 0): ContactState.anodic},
      ContactState.anodic,
    );
    expect(result.valid, isFalse);
    expect(
      result.error,
      'When CASE is anodic, no other contacts can be anodic',
    );
  });

  test('rule 3: cathodic contact requires an anode somewhere', () {
    final result = validateConfiguration(
      {const ContactKey(0, 0): ContactState.cathodic},
      ContactState.off,
    );
    expect(result.valid, isFalse);
    expect(
      result.error,
      'At least one anodic contact (or CASE) required when using '
      'cathodic contacts',
    );
  });

  test('rule 3: anodic contacts alone are valid', () {
    final result = validateConfiguration(
      {const ContactKey(0, 0): ContactState.anodic},
      ContactState.off,
    );
    expect(result.valid, isTrue);
  });

  test('ContactKey equality and hashing', () {
    expect(const ContactKey(1, 2), const ContactKey(1, 2));
    expect(const ContactKey(1, 2).hashCode, const ContactKey(1, 2).hashCode);
    expect(const ContactKey(1, 2), isNot(const ContactKey(2, 1)));

    // Map lookups work across distinct instances.
    final states = {const ContactKey(3, 0): ContactState.anodic};
    expect(states[const ContactKey(3, 0)], ContactState.anodic);
  });
}
