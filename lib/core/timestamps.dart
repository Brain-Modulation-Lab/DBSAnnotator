/// The three timestamp cells every row carries, in one place.
///
/// ## Why `acq_time` exists
///
/// Until v0.5.0 the only machine-readable part of a timestamp was `date` +
/// `time`, which say nothing about the offset, plus a `timezone` cell holding
/// whatever `DateTime.timeZoneName` returned on the recording machine. On
/// Windows that is a *display* name — `W. Europe Daylight Time +0200` — which no
/// date parser accepts, so the documentation had to tell readers to regex the
/// `+0200` out of it. The annotations writer was worse: it wrote the name with
/// no offset at all, leaving those rows unresolvable to an instant.
///
/// `acq_time` is the whole instant in ISO-8601 with its offset, which
/// `DateTime.parse`, pandas and R all read directly. `date`, `time` and
/// `timezone` are kept because a clinician opening the file in a spreadsheet
/// reads those, not an ISO string.
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

/// The `timezone` cell: the IANA/abbreviated zone name and its offset, e.g.
/// `CEST +02:00`. Retained for human readers; [acqTimeCell] is what tooling
/// should parse.
String timezoneCell(DateTime dt) =>
    '${dt.timeZoneName} ${offsetString(dt)}'.trim();

/// The `acq_time` cell: ISO-8601 with offset, e.g. `2026-06-26T16:46:14+02:00`.
String acqTimeCell(DateTime dt) =>
    '${dateCell(dt)}T${timeCell(dt)}${offsetString(dt)}';
