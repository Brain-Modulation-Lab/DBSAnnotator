import 'schema_columns.dart';
import 'timestamps.dart';
import 'tsv.dart';

/// One timestamped note row of an annotations-only (`task-notes`) TSV.
class Annotation {
  const Annotation({required this.acqTime, required this.notes});

  /// ISO-8601 instant with offset. Legacy notes files stored
  /// `date`/`time`/`timezone` with no offset; [Annotation.fromMap] backfills
  /// those rows.
  final String acqTime;
  final String notes;

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
