import 'schema_columns.dart';
import 'tsv.dart';

/// One timestamped note row of an annotations-only (`task-notes`) TSV.
class Annotation {
  const Annotation({
    required this.date,
    required this.time,
    required this.timezone,
    required this.notes,
  });

  final String date;
  final String time;
  final String timezone;
  final String notes;

  /// Build an entry stamped with the current local date/time (matches the
  /// desktop app, which records local date, time, and timezone abbreviation).
  factory Annotation.now(String notes, {DateTime? at}) {
    final dt = at ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return Annotation(
      date: '${dt.year}-${two(dt.month)}-${two(dt.day)}',
      time: '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}',
      timezone: dt.timeZoneName,
      notes: notes,
    );
  }

  factory Annotation.fromMap(Map<String, String> m) => Annotation(
        date: m['date'] ?? '',
        time: m['time'] ?? '',
        timezone: m['timezone'] ?? '',
        notes: m['notes'] ?? '',
      );

  Map<String, String> toMap() => {
        'date': date,
        'time': time,
        'timezone': timezone,
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
