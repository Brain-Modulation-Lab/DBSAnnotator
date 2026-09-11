import 'schema_columns.dart';
import 'timestamps.dart';
import 'tsv.dart';

/// One timestamped note row of an annotations-only (`task-notes`) TSV.
class Annotation {
  const Annotation({required this.acqTime, required this.notes});

  /// The whole instant in ISO-8601 with its offset, and the only timestamp a
  /// note carries.
  ///
  /// Before v0.5.0 a note stored `date` + `time` + a `timezone` cell holding a
  /// bare `DateTime.timeZoneName` with **no offset** — so an annotation row
  /// could not be resolved to an instant at all, where the session writer at
  /// least included one. [Annotation.fromMap] backfills those rows, so an old
  /// notes file now reads as a real instant for the first time.
  final String acqTime;
  final String notes;

  /// Build an entry stamped with the current local date and time.
  factory Annotation.now(String notes, {DateTime? at}) =>
      Annotation(acqTime: acqTimeCell(at ?? DateTime.now()), notes: notes);

  factory Annotation.fromMap(Map<String, String> m) {
    final iso = readColumn(m, 'acq_time').trim();
    return Annotation(
      acqTime: iso.isNotEmpty
          ? iso
          : backfillAcqTime(
              date: readColumn(m, 'date'),
              time: readColumn(m, 'time'),
              timezone: readColumn(m, 'timezone'),
            ),
      notes: readColumn(m, 'notes'),
    );
  }

  Map<String, String> toMap() => {'acq_time': acqTime, 'notes': notes};

  /// The note's instant as a local [DateTime], or null if unparsable.
  DateTime? get timestamp => DateTime.tryParse(acqTime.trim())?.toLocal();
}

/// Parse an annotations-only TSV document into [Annotation]s.
List<Annotation> parseAnnotations(String content) =>
    parseTsvRecords(content).map(Annotation.fromMap).toList();

/// Serialize [Annotation]s to a TSV document with the canonical header.
String writeAnnotations(List<Annotation> items) =>
    writeTsvRecords(annotationColumns, items.map((a) => a.toMap()).toList());
