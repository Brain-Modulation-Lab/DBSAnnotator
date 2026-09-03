import 'schema_columns.dart';
import 'timestamps.dart';
import 'tsv.dart';

/// One timestamped note row of an annotations-only (`task-notes`) TSV.
class Annotation {
  const Annotation({
    required this.date,
    required this.time,
    required this.timezone,
    this.acqTime = '',
    required this.notes,
  });

  final String date;
  final String time;
  final String timezone;

  /// The same instant as [date] + [time] + [timezone] in ISO-8601 with its
  /// offset. Empty on rows written before v0.5.0.
  final String acqTime;
  final String notes;

  /// Build an entry stamped with the current local date and time.
  ///
  /// Before v0.5.0 the `timezone` cell held a bare `DateTime.timeZoneName` with
  /// **no offset**, so an annotation row could not be resolved to an instant at
  /// all — the session writer included the offset but this one did not. Both now
  /// go through [timestamps.dart].
  factory Annotation.now(String notes, {DateTime? at}) {
    final dt = at ?? DateTime.now();
    return Annotation(
      date: dateCell(dt),
      time: timeCell(dt),
      timezone: timezoneCell(dt),
      acqTime: acqTimeCell(dt),
      notes: notes,
    );
  }

  factory Annotation.fromMap(Map<String, String> m) => Annotation(
        date: readColumn(m, 'date'),
        time: readColumn(m, 'time'),
        timezone: readColumn(m, 'timezone'),
        acqTime: readColumn(m, 'acq_time'),
        notes: readColumn(m, 'notes'),
      );

  Map<String, String> toMap() => {
        'date': date,
        'time': time,
        'timezone': timezone,
        'acq_time': acqTime,
        'notes': notes,
      };
}

/// Parse an annotations-only TSV document into [Annotation]s.
List<Annotation> parseAnnotations(String content) =>
    parseTsvRecords(content).map(Annotation.fromMap).toList();

/// Serialize [Annotation]s to a TSV document with the canonical header.
String writeAnnotations(List<Annotation> items) => writeTsvRecords(
      annotationColumns,
      items.map((a) => a.toMap()).toList(),
    );
