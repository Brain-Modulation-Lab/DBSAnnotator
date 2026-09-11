/// `acq_time`, the only timestamp a row carries, and how older rows reach it.
///
/// It is the whole instant in ISO-8601 with its offset — what `DateTime.parse`,
/// pandas and R all read directly, and BIDS' own timestamp column name.
///
/// Files up to v0.5.0 stored `date` + `time` + a free-text `timezone` instead.
/// Those three are no longer written: four cells describing one instant can
/// disagree, and `timezone` was not reproducible, since `DateTime.timeZoneName`
/// yields `W. Europe Daylight Time` on Windows and `CEST` on Linux for the same
/// clinic. [backfillAcqTime] composes an instant from them on read, so an older
/// file needs no conversion step.
///
/// Two ways to read the result, and they are not interchangeable:
/// [recordedDate] / [recordedTime] for display, `DateTime.parse` for
/// arithmetic. See [recordedDate].
library;

String _two(int n) => n.toString().padLeft(2, '0');

/// UTC offset as `+02:00` / `-05:00`, the ISO-8601 form.
String offsetString(DateTime dt) {
  final offset = dt.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  return '$sign${_two(abs.inHours)}:${_two(abs.inMinutes.remainder(60))}';
}

/// The `date` cell: `YYYY-MM-DD`.
String dateCell(DateTime dt) => '${dt.year}-${_two(dt.month)}-${_two(dt.day)}';

/// The `time` cell: `HH:MM:SS`.
String timeCell(DateTime dt) =>
    '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';

/// The `acq_time` cell: ISO-8601 with offset, e.g. `2026-02-03T09:00:00+00:00`.
String acqTimeCell(DateTime dt) =>
    '${dateCell(dt)}T${timeCell(dt)}${offsetString(dt)}';

/// The ISO offset (`+02:00`) carried in a pre-0.5.0 `timezone` cell, or `''`.
///
/// Accepts both forms ever written: `UTC +00:00` and the Windows display name
/// `W. Europe Daylight Time +0200`. Only the offset half is portable.
String offsetFromTimezoneCell(String timezone) {
  final m = RegExp(r'([+-])(\d{2}):?(\d{2})').firstMatch(timezone);
  return m == null ? '' : '${m.group(1)}${m.group(2)}:${m.group(3)}';
}

/// An `acq_time` composed from a pre-0.5.0 row's `date`, `time` and `timezone`.
///
/// Returns `''` when there is not enough to build a real instant, so a caller
/// can leave the cell empty (which the TSV writer renders as `n/a`) rather than
/// inventing one.
///
/// The offset is never guessed: a missing or unparsable `timezone` yields a
/// zone-less ISO string. Stamping it with the reading machine's offset would
/// assert a clinic location that could be hours wrong, invisibly.
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

/// The date recorded in an `acq_time` cell, `YYYY-MM-DD`, or `''`.
///
/// Not via `DateTime`, deliberately: rendering an instant picks a zone, so an
/// event recorded at `09:00:00+00:00` would show as 10:00 at +02:00 and 04:00
/// in New York. A clinical record must show the time it happened at the clinic.
///
/// Display therefore reads the literal characters; [SessionRow.timestamp] is
/// the instant, for ordering and intervals only.
String recordedDate(String acqTime) => _wallClock(acqTime)?.group(1) ?? '';

/// The clock time recorded in an `acq_time` cell, `HH:MM:SS`, or `''`.
/// See [recordedDate] for why this does not go through `DateTime`.
String recordedTime(String acqTime) => _wallClock(acqTime)?.group(2) ?? '';

/// Accepts both the `T` separator and the space form an external tool may write.
final RegExp _wallClockPattern = RegExp(
  r'^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})',
);

RegExpMatch? _wallClock(String acqTime) =>
    _wallClockPattern.firstMatch(acqTime.trim());
