/// The one timestamp cell every row carries, and how legacy rows reach it.
///
/// ## Why `acq_time` is the only one
///
/// Until v0.5.0 a row's timestamp was spread over `date` + `time`, which say
/// nothing about the offset, plus a `timezone` cell holding whatever
/// `DateTime.timeZoneName` returned on the recording machine. On Windows that
/// is a *display* name — `W. Europe Daylight Time +0200` — which no date parser
/// accepts, so the documentation had to tell readers to regex the `+0200` out
/// of it. The annotations writer was worse: it wrote the name with no offset at
/// all, leaving those rows unresolvable to an instant.
///
/// `acq_time` is the whole instant in ISO-8601 with its offset, which
/// `DateTime.parse`, pandas and R all read directly. It is also BIDS' own
/// timestamp column name, used in `scans.tsv` and `sessions.tsv`.
///
/// `date`, `time` and `timezone` were kept alongside it for one release, on the
/// theory that a clinician reading the TSV in a spreadsheet wants them. They are
/// **no longer written**, for three reasons that outweigh it:
///
///  * four cells describing one instant can disagree, and nothing asserted that
///    they agreed;
///  * `timezone` was not reproducible — `timeZoneName` yields
///    `W. Europe Daylight Time` on Windows and `CEST` on Linux/macOS, so the
///    same clinic produced different cells per platform, which is worse than
///    absent in a scientific record. Its only machine-usable half, the offset,
///    is already inside `acq_time`;
///  * the recipe the docs had to teach was
///    `pd.to_datetime(df.date + ' ' + df.time)` plus a regex over `df.timezone`,
///    where `pd.to_datetime(df.acq_time)` is one offset-aware line.
///
/// Files written before this change still carry the old cells, and
/// [backfillAcqTime] is what turns them into an instant on read — so a 0.4.x or
/// Qt file gains a usable `acq_time` the moment it is opened, and nothing
/// downstream has to know it was missing.
///
/// [dateCell] and [timeCell] survive as **display** formatters: the entries
/// table and the report headers still show a human a date and a clock time,
/// now derived from the instant rather than stored beside it.
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
/// Accepts both forms the app and the Qt desktop ever wrote: `UTC +00:00` and
/// the Windows display name `W. Europe Daylight Time +0200`. Only the offset is
/// portable — the name half differs per platform for the same clinic — so this
/// deliberately extracts the offset and discards the rest.
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
/// **The offset is never guessed.** A missing or unparsable `timezone` yields a
/// zone-less ISO string, which is honest: it says "this clock reading, offset
/// unknown". Stamping it with the *reading* machine's offset would assert a
/// clinic location that could be hours wrong, and would do so invisibly.
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
/// **Deliberately not via `DateTime`.** Parsing an ISO string with an offset
/// yields an *instant*, and rendering an instant necessarily picks a zone: on a
/// machine at +02:00, an event recorded at `09:00:00+00:00` renders as 10:00,
/// and in New York as 04:00. For a clinical record that is simply wrong — the
/// reader wants the time it happened *at the clinic*, which is the wall clock
/// the recording machine wrote down.
///
/// So display reads the literal characters, and [SessionRow.timestamp] — a real
/// instant — is reserved for arithmetic: ordering rows, measuring the gap
/// between two blocks, computing a session's span. Getting that split wrong is
/// how the retired `date` / `time` columns came to be trusted more than the ISO
/// one.
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
