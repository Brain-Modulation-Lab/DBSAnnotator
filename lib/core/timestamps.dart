/// `acq_time`, the only timestamp a row carries: the whole instant in ISO-8601
/// with its offset, which `DateTime.parse`, pandas and R all read directly.
library;

String _two(int n) => n.toString().padLeft(2, '0');

String offsetString(DateTime dt) {
  final offset = dt.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  return '$sign${_two(abs.inHours)}:${_two(abs.inMinutes.remainder(60))}';
}

String dateCell(DateTime dt) => '${dt.year}-${_two(dt.month)}-${_two(dt.day)}';

String timeCell(DateTime dt) =>
    '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';

String acqTimeCell(DateTime dt) =>
    '${dateCell(dt)}T${timeCell(dt)}${offsetString(dt)}';

/// The ISO offset carried in a legacy `timezone` cell, or `''`. Accepts both
/// forms written: `UTC +00:00` and `W. Europe Daylight Time +0200`.
String offsetFromTimezoneCell(String timezone) {
  final m = RegExp(r'([+-])(\d{2}):?(\d{2})').firstMatch(timezone);
  return m == null ? '' : '${m.group(1)}${m.group(2)}:${m.group(3)}';
}

/// An `acq_time` composed from a legacy row's `date`, `time` and `timezone`,
/// or `''` when there is not enough. The offset is never guessed.
String backfillAcqTime({
  required String date,
  required String time,
  required String timezone,
}) {
  final d = date.trim();
  if (d.isEmpty) return '';
  final t = time.trim().isEmpty ? '00:00:00' : time.trim();
  final candidate = '${d}T$t${offsetFromTimezoneCell(timezone)}';
  return DateTime.tryParse(candidate) == null ? '' : candidate;
}

/// The date in an `acq_time` cell, `YYYY-MM-DD`, or `''`. Read as characters:
/// a rendered `DateTime` picks a zone, losing the clinic's own wall clock.
String recordedDate(String acqTime) => _wallClock(acqTime)?.group(1) ?? '';

/// The clock time in an `acq_time` cell, `HH:MM:SS`, or `''`.
String recordedTime(String acqTime) => _wallClock(acqTime)?.group(2) ?? '';

final RegExp _wallClockPattern = RegExp(
  r'^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})',
);

RegExpMatch? _wallClock(String acqTime) =>
    _wallClockPattern.firstMatch(acqTime.trim());
