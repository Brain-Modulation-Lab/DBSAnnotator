import 'contact_state.dart';

/// Identifies a physical contact: level index plus segment index. Ring
/// contacts always use `segmentIdx == 0`; directional levels use 0/1/2
/// (displayed as a/b/c), mirroring the Python `(contact_idx, segment_idx)`.
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

/// Validates a stimulation configuration against the clinical rules in the
/// Python `StimulationRule.validate_configuration`, with identical error
/// messages: a cathodic case forbids other cathodes, an anodic case forbids
/// other anodes, and any cathode requires at least one anode (or an anodic
/// case).
///
/// Representation invariant (matching Python): OFF contacts are represented by
/// the ABSENCE of the key in [contactStates], never by a stored OFF state.
({bool valid, String error}) validateConfiguration(
  Map<ContactKey, ContactState> contactStates,
  ContactState caseState,
) {
  if (caseState == ContactState.cathodic &&
      contactStates.values.any((s) => s == ContactState.cathodic)) {
    return (
      valid: false,
      error: 'When CASE is cathodic, no other contacts can be cathodic',
    );
  }

  if (caseState == ContactState.anodic &&
      contactStates.values.any((s) => s == ContactState.anodic)) {
    return (
      valid: false,
      error: 'When CASE is anodic, no other contacts can be anodic',
    );
  }

  final hasCathodic = contactStates.values.any(
    (s) => s == ContactState.cathodic,
  );
  final hasAnodic =
      caseState == ContactState.anodic ||
      contactStates.values.any((s) => s == ContactState.anodic);
  if (hasCathodic && !hasAnodic) {
    return (
      valid: false,
      error:
          'At least one anodic contact (or CASE) required when using '
          'cathodic contacts',
    );
  }

  return (valid: true, error: '');
}
