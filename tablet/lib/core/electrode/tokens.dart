import 'contact_state.dart';
import 'electrode_model.dart';
import 'stimulation_rule.dart';

/// Anode/cathode token grammar shared with the desktop app's TSV files.
///
/// Ports `_get_anode_cathode_texts` and `_apply_contact_text_to_canvas` from
/// `src/dbs_annotator/views/step3_view.py`.
///
/// Grammar (tokens joined with `_`):
/// - `case`          — the stimulator case carries this polarity.
/// - `E{idx}{a|b|c}` — one segment of a directional level (seg 0/1/2 -> a/b/c).
/// - `E{idx}`        — a ring (non-directional) level; on decode, if the level
///   is directional this activates all 3 segments.

const List<String> _segmentLabels = ['a', 'b', 'c'];
const Map<String, int> _segmentIndices = {'a': 0, 'b': 1, 'c': 2};

/// Encodes contact [states] (plus [caseState]) into underscore-separated
/// anode and cathode token strings for the given [model].
///
/// The `case` token (if any) comes first, then contacts in level order; each
/// active segment of a directional level is emitted individually (segments
/// are never grouped into a bare `E{idx}` on encode).
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
      // Segmented level: always emit individual segments, never grouped.
      for (var seg = 0; seg < 3; seg++) {
        final state = states[ContactKey(contactIdx, seg)] ?? ContactState.off;
        addToken('E$contactIdx${_segmentLabels[seg]}', state);
      }
    } else {
      // Ring contact (or non-directional model).
      final state = states[ContactKey(contactIdx, 0)] ?? ContactState.off;
      addToken('E$contactIdx', state);
    }
  }

  return (anode: anodeItems.join('_'), cathode: cathodeItems.join('_'));
}

/// Decodes underscore-separated [anode] and [cathode] token strings into a
/// contact-state map and case state for the given [model].
///
/// Anode tokens are applied first, then cathode tokens (matching Python, so a
/// contact listed in both ends up cathodic). Invalid tokens are skipped
/// silently, like the Python parser. OFF is represented by key absence.
///
/// Note: on a bare `E{idx}` token the Python parser expands to all 3 segments
/// whenever the MODEL is directional; this port only expands when that LEVEL
/// is directional (ring levels of directional leads get a single
/// `(idx, 0)` key), which matches what `encodeTokens` produces and
/// round-trips cleanly.
///
/// TODO: legacy token forms found in very old TSVs are not supported yet:
/// `"{idx} ring"` and bare `"{idx}{a|b|c}"` (without the `E` prefix) — see
/// `_apply_contact_text_to_canvas` in step3_view.py. Add them here if old
/// desktop files must be loadable on the tablet.
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
          // E{digits}{a|b|c} -> single segment.
          final idx = int.tryParse(token.substring(1, token.length - 1));
          final seg = _segmentIndices[lastChar.toLowerCase()];
          if (idx == null || seg == null) continue; // Invalid token: skip.
          states[ContactKey(idx, seg)] = state;
        } else {
          // E{digits} -> ring contact, or all 3 segments of a directional
          // level.
          final idx = int.tryParse(token.substring(1));
          if (idx == null) continue; // Invalid token: skip.
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
      // Unrecognized token (including the legacy forms above): skip.
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
