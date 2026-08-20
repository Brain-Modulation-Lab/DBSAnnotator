/// BIDS filename handling, mirroring the desktop app's construction
/// (e.g. views/annotation_only_view.py, views/step1_view.py) and the regex
/// parsing used by the exporters. Contract: schema/tsv_schema.json -> "bids".
class BidsName {
  const BidsName({
    required this.subject,
    required this.session,
    required this.task,
    required this.run,
  });

  final String subject;
  final String session;
  final String task; // "programming" or "notes"
  final String run;

  /// e.g. sub-01_ses-20260724_task-notes_run-01_events.tsv
  String get filename =>
      'sub-${subject}_ses-${session}_task-${task}_run-${run}_events.tsv';

  static String? _group(String pattern, String source) =>
      RegExp(pattern).firstMatch(source)?.group(1);

  /// Parse a BIDS events filename; returns null if no subject entity is found.
  static BidsName? parse(String filename) {
    final subject = _group(r'sub-([^_]+)', filename);
    if (subject == null) return null;
    return BidsName(
      subject: subject,
      session: _group(r'ses-([^_]+)', filename) ?? '',
      task: _group(r'task-([^_]+)', filename) ?? '',
      run: _group(r'run-([0-9]+)', filename) ?? '01',
    );
  }

  /// Session stamp in the desktop format (%Y%m%d).
  static String sessionStamp(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}${two(dt.month)}${two(dt.day)}';
  }
}
