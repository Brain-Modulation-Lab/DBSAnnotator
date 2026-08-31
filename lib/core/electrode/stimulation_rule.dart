import 'contact_state.dart';

/// Identifies a physical contact: contact level index plus segment index.
///
/// Ring (non-directional) contacts always use `segmentIdx == 0`; directional
/// levels use segments 0/1/2 (displayed as a/b/c). Mirrors the Python
/// `(contact_idx, segment_idx)` tuple keys used by the desktop canvas.
class ContactKey {
  const ContactKey(this.contactIdx, this.segmentIdx);

  final int contactIdx;
  final int segmentIdx;

  @override
  bool operator ==(Object other) =>
      other is ContactKey &&
      other.contactIdx == contactIdx &&
      other.segmentIdx == segmentIdx;

  @override
  int get hashCode => Object.hash(contactIdx, segmentIdx);

  @override
  String toString() => 'ContactKey($contactIdx, $segmentIdx)';
}

/// Validates a stimulation configuration according to the clinical rules in
/// the Python `StimulationRule.validate_configuration`
/// (`dbs_annotator/config_electrode_models.py`).
///
/// IMPORTANT representation invariant (matching Python): OFF contacts are
/// represented by the ABSENCE of the key in [contactStates] — an OFF state is
/// never stored in the map.
///
/// Rules:
/// 1. If the case is cathodic, no other contact may be cathodic.
/// 2. If the case is anodic, no other contact may be anodic.
/// 3. If any contact is cathodic, at least one anodic contact (or an anodic
///    case) must exist.
///
/// Returns `(valid: true, error: '')` when the configuration is acceptable;
/// error messages are identical to the Python ones.
({bool valid, String error}) validateConfiguration(
  Map<ContactKey, ContactState> contactStates,
  ContactState caseState,
) {
  // Rule 1: If case is cathodic, no other contact can be cathodic.
  if (caseState == ContactState.cathodic &&
      contactStates.values.any((s) => s == ContactState.cathodic)) {
    return (
      valid: false,
      error: 'When CASE is cathodic, no other contacts can be cathodic',
    );
  }

  // Rule 2: If case is anodic, no other contact can be anodic.
  if (caseState == ContactState.anodic &&
      contactStates.values.any((s) => s == ContactState.anodic)) {
    return (
      valid: false,
      error: 'When CASE is anodic, no other contacts can be anodic',
    );
  }

  // Rule 3: At least one anodic contact must exist if any cathodic exists.
  final hasCathodic =
      contactStates.values.any((s) => s == ContactState.cathodic);
  final hasAnodic = caseState == ContactState.anodic ||
      contactStates.values.any((s) => s == ContactState.anodic);
  if (hasCathodic && !hasAnodic) {
    return (
      valid: false,
      error: 'At least one anodic contact (or CASE) required when using '
          'cathodic contacts',
    );
  }

  return (valid: true, error: '');
}
