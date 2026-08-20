/// Possible states for an electrode contact or the stimulator case.
///
/// The integer values mirror the Python `ContactState` constants in
/// `src/dbs_annotator/config_electrode_models.py` (OFF=0, ANODIC=1,
/// CATHODIC=2) so serialized values stay interchangeable with the desktop app.
enum ContactState {
  off(0),
  anodic(1),
  cathodic(2);

  const ContactState(this.value);

  /// Integer value used by the Python desktop app.
  final int value;

  /// Maps a Python-side integer value back to the enum.
  ///
  /// Throws an [ArgumentError] for values outside 0..2.
  static ContactState fromValue(int value) {
    return switch (value) {
      0 => ContactState.off,
      1 => ContactState.anodic,
      2 => ContactState.cathodic,
      _ => throw ArgumentError.value(
          value, 'value', 'Unknown ContactState value'),
    };
  }
}
