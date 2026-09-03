/// BIDS filename handling. Contract: schema/tsv_schema.json -> "bids".
///
/// ## Why the suffix is `_beh`, not `_events`
///
/// The BIDS specification reserves `_events.tsv` for files whose first two
/// columns are `onset` and `duration`, and requires each one to accompany a
/// recording ("Each `events.tsv` file REQUIRES at least one corresponding data
/// file"). This app records neither — a programming session has no acquisition
/// to measure an onset from, and there is no imaging or electrophysiology file
/// beside it. The spec names the correct alternative directly:
///
/// > events files that do not include the mandatory `onset` and `duration`
/// > columns MAY be included, but MUST be labeled `_beh.tsv` rather than
/// > `_events.tsv`.
///
/// So `_beh.tsv` in a `beh/` datatype directory is not a compromise, it is the
/// suffix the specification points at for exactly this shape of file.
///
/// Files written before v0.5.0 use `_events.tsv`. Nothing here parses the
/// suffix, and `sniffTsvKind` classifies on the header rather than the name, so
/// those keep opening unchanged.
library;

class BidsName {
  const BidsName({
    required this.subject,
    required this.session,
    required this.task,
    required this.run,
    this.suffix = behSuffix,
    this.extension = 'tsv',
  });

  /// The suffix for this app's tabular output. See the library comment.
  static const String behSuffix = 'beh';

  /// The suffix written before v0.5.0. Read-only: never written again, but
  /// recognised so an older file round-trips through [parse].
  static const String legacySuffix = 'events';

  /// The BIDS datatype directory these files belong in.
  static const String datatype = 'beh';

  final String subject;
  final String session;
  final String task; // "programming" or "notes"
  final String run;
  final String suffix;
  final String extension;

  /// Strip a BIDS entity label to the alphanumerics the spec allows.
  ///
  /// Subject and session come from free-text fields that end up in a **file
  /// path**. A typed `/`, `\`, `:` or a leading `..` otherwise produces a failed
  /// write on Windows or a path escaping the temp directory. BIDS labels are
  /// alphanumeric by specification, so stripping is both safe and correct.
  static String label(String raw) =>
      raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');

  /// Reduce a run entity to the *index* BIDS requires, zero-padded.
  ///
  /// `run-` is an index, not a label: "non-negative integers, optionally zero
  /// padded", and the spec recommends the padding. [label] would happily emit
  /// `run-pre`, which [parse] then reads back as `01` because its pattern is
  /// digits-only — so a filename could silently lose information on a
  /// round-trip. Normalising here makes write and read agree.
  ///
  /// Falls back to `01` when nothing numeric is left, which is the same default
  /// [parse] applies to a name with no run entity at all.
  static String index(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final n = int.tryParse(digits);
    if (n == null) return '01';
    return n.toString().padLeft(2, '0');
  }

  /// The entity chain without suffix or extension, e.g.
  /// `sub-01_ses-20260724_task-notes_run-01`.
  ///
  /// Entity labels are sanitised, so this is always a safe path segment.
  String get stem => 'sub-${label(subject)}_ses-${label(session)}'
      '_task-${label(task)}_run-${index(run)}';

  /// e.g. `sub-01_ses-20260724_task-notes_run-01_beh.tsv`
  String get filename => '${stem}_$suffix.$extension';

  /// The sidecar that documents this file's columns, e.g.
  /// `sub-01_ses-20260724_task-notes_run-01_beh.json`.
  String get sidecarFilename => '${stem}_$suffix.json';

  /// The same entities with a different suffix/extension — for the report
  /// derivatives, which would otherwise be hand-built strings per screen.
  BidsName withSuffix(String suffix, {String extension = 'tsv'}) => BidsName(
        subject: subject,
        session: session,
        task: task,
        run: run,
        suffix: suffix,
        extension: extension,
      );

  /// `sub-<label>/ses-<label>/beh` — the directory a raw file belongs in.
  String get relativeDir =>
      'sub-${label(subject)}/ses-${label(session)}/$datatype';

  static String? _group(String pattern, String source) =>
      RegExp(pattern).firstMatch(source)?.group(1);

  /// Parse a BIDS filename; returns null if no subject entity is found.
  ///
  /// Accepts both the current `_beh` suffix and the pre-0.5.0 `_events` one.
  static BidsName? parse(String filename) {
    final subject = _group(r'sub-([^_]+)', filename);
    if (subject == null) return null;
    return BidsName(
      subject: subject,
      session: _group(r'ses-([^_]+)', filename) ?? '',
      task: _group(r'task-([^_]+)', filename) ?? '',
      run: _group(r'run-([0-9]+)', filename) ?? '01',
      suffix: filename.contains('_$legacySuffix.') ? legacySuffix : behSuffix,
    );
  }

  /// Session stamp in the BIDS-label format used for `ses-` (%Y%m%d).
  static String sessionStamp(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}${two(dt.month)}${two(dt.day)}';
  }
}
