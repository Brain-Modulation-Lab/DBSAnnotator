/// State of an electrode contact or the stimulator case; the integer values
/// mirror the Python `ContactState` constants so serialized values stay
/// interchangeable with the desktop app.
enum ContactState {
  off(0),
  anodic(1),
  cathodic(2);

  const ContactState(this.value);

  final int value;

  /// Maps a Python-side integer back to the enum; throws outside 0..2.
  static ContactState fromValue(int value) {
    return switch (value) {
      0 => ContactState.off,
      1 => ContactState.anodic,
      2 => ContactState.cathodic,
      _ => throw ArgumentError.value(
        value,
        'value',
        'Unknown ContactState value',
      ),
    };
  }
}
