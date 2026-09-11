import 'contact_state.dart';
import 'electrode_model.dart';
import 'stimulation_rule.dart';

/// Anode/cathode token grammar shared with the desktop app's TSV files,
/// ported from `step3_view.py`.
///
/// Tokens joined with `_`: `case`, `E{idx}{a|b|c}` for one segment of a
/// directional level (seg 0/1/2 maps to a/b/c), and `E{idx}` for a ring level
/// (on decode it activates all 3 segments of a directional level).

const List<String> _segmentLabels = ['a', 'b', 'c'];
const Map<String, int> _segmentIndices = {'a': 0, 'b': 1, 'c': 2};

/// Encodes contact [states] and [caseState] into underscore-separated anode
/// and cathode token strings. `case` comes first, then contacts in level
/// order; segments of a directional level are emitted individually, never
/// grouped into a bare `E{idx}`.
({String anode, String cathode}) encodeTokens(
  Map<ContactKey, ContactState> states,
  ContactState caseState,
  ElectrodeModel model,
) {
  final anodeItems = <String>[];
  final cathodeItems = <String>[];

  void addToken(String token, ContactState state) {
    if (state == ContactState.anodic) {
      anodeItems.add(token);
    } else if (state == ContactState.cathodic) {
      cathodeItems.add(token);
    }
  }

  if (caseState == ContactState.anodic) {
    anodeItems.add('case');
  } else if (caseState == ContactState.cathodic) {
    cathodeItems.add('case');
  }

  for (var contactIdx = 0; contactIdx < model.numContacts; contactIdx++) {
    if (model.isDirectional && model.isLevelDirectional(contactIdx)) {
      for (var seg = 0; seg < 3; seg++) {
        final state = states[ContactKey(contactIdx, seg)] ?? ContactState.off;
        addToken('E$contactIdx${_segmentLabels[seg]}', state);
      }
    } else {
      final state = states[ContactKey(contactIdx, 0)] ?? ContactState.off;
      addToken('E$contactIdx', state);
    }
  }

  return (anode: anodeItems.join('_'), cathode: cathodeItems.join('_'));
}

/// Decodes [anode] and [cathode] token strings into a contact-state map and
/// case state. Anode tokens are applied first, so a contact listed in both
/// ends up cathodic (matching Python); invalid tokens are skipped silently and
/// OFF is represented by key absence.
///
/// On a bare `E{idx}` the Python parser expands to all 3 segments whenever the
/// model is directional; this port expands only when that level is
/// directional, which round-trips with [encodeTokens].
///
/// TODO: the legacy forms `"{idx} ring"` and bare `"{idx}{a|b|c}"` (no `E`
/// prefix) accepted by `_apply_contact_text_to_canvas` are not supported.
({Map<ContactKey, ContactState> states, ContactState caseState}) decodeTokens(
  String anode,
  String cathode,
  ElectrodeModel model,
) {
  final states = <ContactKey, ContactState>{};
  var caseState = ContactState.off;

  void applyTokens(String text, ContactState state) {
    if (text.isEmpty) return;
    for (final rawToken in text.split('_')) {
      final token = rawToken.trim();
      if (token.isEmpty) continue;

      if (token == 'case') {
        caseState = state;
        continue;
      }

      if (token.startsWith('E') && token.length >= 2) {
        final lastChar = token[token.length - 1];
        if (_isAsciiLetter(lastChar)) {
          final idx = int.tryParse(token.substring(1, token.length - 1));
          final seg = _segmentIndices[lastChar.toLowerCase()];
          if (idx == null || seg == null) continue;
          states[ContactKey(idx, seg)] = state;
        } else {
          final idx = int.tryParse(token.substring(1));
          if (idx == null) continue;
          if (model.isDirectional &&
              idx < model.numContacts &&
              model.isLevelDirectional(idx)) {
            for (var seg = 0; seg < 3; seg++) {
              states[ContactKey(idx, seg)] = state;
            }
          } else {
            states[ContactKey(idx, 0)] = state;
          }
        }
        continue;
      }
    }
  }

  applyTokens(anode, ContactState.anodic);
  applyTokens(cathode, ContactState.cathodic);

  return (states: states, caseState: caseState);
}

bool _isAsciiLetter(String char) {
  final c = char.codeUnitAt(0);
  return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
}
