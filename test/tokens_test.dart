import 'package:dbs_annotator/core/electrode/contact_state.dart';
import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/electrode/stimulation_rule.dart';
import 'package:dbs_annotator/core/electrode/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ring(tip)-Seg3-Seg3-Ring, like Boston Scientific Vercise Directed.
const directedModel = ElectrodeModel(
  name: 'Boston Scientific Vercise Directed',
  numContacts: 4,
  contactHeight: 1.5,
  contactSpacing: 0.5,
  leadDiameter: 1.3,
  isDirectional: true,
  tipContact: true,
  segmentsPerLevel: 3,
  directionalLevels: [1, 2],
  levelDirectional: [false, true, true, false],
);

/// 4 plain ring contacts, like Medtronic 3389.
const ringModel = ElectrodeModel(
  name: 'Medtronic 3389',
  numContacts: 4,
  contactHeight: 1.5,
  contactSpacing: 0.5,
  leadDiameter: 1.27,
  isDirectional: false,
  tipContact: false,
  segmentsPerLevel: 1,
  directionalLevels: null,
  levelDirectional: [false, false, false, false],
);

void main() {
  test('encode: case, ring contact, and individual segments', () {
    final states = {
      const ContactKey(0, 0): ContactState.anodic, // Ring level.
      const ContactKey(1, 0): ContactState.anodic, // Segment a.
      const ContactKey(2, 0): ContactState.cathodic, // Segment a.
      const ContactKey(2, 1): ContactState.cathodic, // Segment b.
    };
    final encoded = encodeTokens(states, ContactState.off, directedModel);
    expect(encoded.anode, 'E0_E1a');
    expect(encoded.cathode, 'E2a_E2b');
  });

  test('encode: case token comes first with matching polarity', () {
    final states = {const ContactKey(2, 1): ContactState.cathodic};
    final encoded = encodeTokens(states, ContactState.anodic, directedModel);
    expect(encoded.anode, 'case');
    expect(encoded.cathode, 'E2b');

    final encodedCathodicCase =
        encodeTokens({const ContactKey(0, 0): ContactState.anodic},
            ContactState.cathodic, directedModel);
    expect(encodedCathodicCase.anode, 'E0');
    expect(encodedCathodicCase.cathode, 'case');
  });

  test('decode: known string "E1_E2a_case" as anode', () {
    final decoded = decodeTokens('E1_E2a_case', 'E3', directedModel);

    expect(decoded.caseState, ContactState.anodic);
    // E1 on a directional level expands to all 3 segments.
    expect(decoded.states[const ContactKey(1, 0)], ContactState.anodic);
    expect(decoded.states[const ContactKey(1, 1)], ContactState.anodic);
    expect(decoded.states[const ContactKey(1, 2)], ContactState.anodic);
    // E2a is a single segment.
    expect(decoded.states[const ContactKey(2, 0)], ContactState.anodic);
    // E3 is a ring level of the directional lead -> single (3, 0) key.
    expect(decoded.states[const ContactKey(3, 0)], ContactState.cathodic);
    expect(decoded.states.length, 5);
    // OFF is represented by absence.
    expect(decoded.states.containsKey(const ContactKey(0, 0)), isFalse);
  });

  test('round-trip: directional mix with segments, ring, and case', () {
    final states = {
      const ContactKey(0, 0): ContactState.cathodic, // Ring (tip).
      const ContactKey(1, 1): ContactState.anodic, // Segment b.
      const ContactKey(2, 2): ContactState.cathodic, // Segment c.
    };
    const caseState = ContactState.anodic;

    final encoded = encodeTokens(states, caseState, directedModel);
    expect(encoded.anode, 'case_E1b');
    expect(encoded.cathode, 'E0_E2c');

    final decoded =
        decodeTokens(encoded.anode, encoded.cathode, directedModel);
    expect(decoded.states, states);
    expect(decoded.caseState, caseState);
  });

  test('round-trip: non-directional model', () {
    final states = {
      const ContactKey(0, 0): ContactState.anodic,
      const ContactKey(2, 0): ContactState.cathodic,
    };
    final encoded = encodeTokens(states, ContactState.off, ringModel);
    expect(encoded.anode, 'E0');
    expect(encoded.cathode, 'E2');

    final decoded = decodeTokens(encoded.anode, encoded.cathode, ringModel);
    expect(decoded.states, states);
    expect(decoded.caseState, ContactState.off);
  });

  test('decode: empty strings give empty configuration', () {
    final decoded = decodeTokens('', '', directedModel);
    expect(decoded.states, isEmpty);
    expect(decoded.caseState, ContactState.off);
  });

  test('decode: invalid tokens are skipped', () {
    final decoded = decodeTokens('Exa_E_bogus_E1a', '', directedModel);
    expect(decoded.states, {const ContactKey(1, 0): ContactState.anodic});
  });

  test('decode: cathode applied after anode wins on overlap', () {
    final decoded = decodeTokens('E0', 'E0', ringModel);
    expect(decoded.states[const ContactKey(0, 0)], ContactState.cathodic);
  });
}
