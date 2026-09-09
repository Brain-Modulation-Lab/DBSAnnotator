import 'package:csv/csv.dart';

/// Tab-separated I/O that matches Python's `csv` module with `delimiter='\t'`.
///
/// The desktop app quotes any field containing a tab, newline, or quote (CSV
/// RFC4180 style), so fields such as `notes` and newline-separated `scale_name`
/// values can contain embedded newlines. We reuse the `csv` package rather than
/// hand-rolling a parser so that quoting/escaping stays compatible.

/// Parse a TSV document into rows of string cells. Auto-detects `\r\n` vs `\n`
/// line endings (pre-0.5.0 files were written with `\r\n`; see [writeTsv]).
///
/// Detection reads the FIRST line ending only, deliberately. It used to be
/// `content.contains('\r\n')`, which scans the whole document including quoted
/// cell content - and a `notes` field can legitimately contain a `\r\n`, pasted
/// from a Windows app or an EHR page. One such cell in an LF-terminated file
/// made the parser take `\r\n` as the row terminator; the quoted `\r\n` is not a
/// row break (the parser only matches the terminator outside quotes) and the
/// real LF terminators no longer matched, so the entire document collapsed to a
/// single row and `parseTsvRecords` - which skips the header - returned ZERO
/// records. `sniffTsvKind` still recognised the file, because the header cells
/// were intact, so the session opened reporting "0 rows" and the next insert
/// autosaved a one-row file over it.
///
/// The header row cannot contain a quoted newline, so the first terminator in
/// the document is always a real one.
List<List<String>> parseTsv(String content) {
  if (content.isEmpty) return <List<String>>[];
  final firstLf = content.indexOf('\n');
  final eol = firstLf > 0 && content[firstLf - 1] == '\r' ? '\r\n' : '\n';
  final rows = CsvToListConverter(
    fieldDelimiter: '\t',
    textDelimiter: '"',
    eol: eol,
    shouldParseNumbers: false,
  ).convert(content);
  return rows
      .map((row) => row.map((cell) => cell?.toString() ?? '').toList())
      .toList();
}

/// Serialize rows to a TSV document.
///
/// LF, not CRLF. The CRLF was chosen so a tablet-written file was byte-identical
/// to the Qt desktop writer's; that app is frozen and no longer shipped, and a
/// stray `\r` ends up inside the last field of every row for any reader that
/// splits on `\n` alone. [parseTsv] still accepts both, so files written by
/// earlier versions read unchanged.
/// Ends with a newline, as a text file should: without one, concatenating two
/// exports runs the last row of the first into the header of the second.
String writeTsv(List<List<String>> rows) {
  if (rows.isEmpty) return '';
  return '${const ListToCsvConverter(fieldDelimiter: '\t', textDelimiter: '"', eol: '\n').convert(rows)}\n';
}

/// What BIDS requires in a cell that has no value: "Missing and non-applicable
/// values MUST be coded as `n/a`" (Common principles, tabular files). An empty
/// cell is not allowed, and neither is `NaN`.
const String naCell = 'n/a';

/// Parse a TSV with a header row into a list of column->value maps.
///
/// [naCell] is normalised back to the empty string, the inverse of what
/// [writeTsvRecords] does. Without this the marker would surface as literal
/// "n/a" text in note fields and report tables — `n/a` is BIDS' encoding of
/// *absent*, so absent is what a reader should get back.
List<Map<String, String>> parseTsvRecords(String content) {
  final rows = parseTsv(content);
  if (rows.isEmpty) return <Map<String, String>>[];
  final header = rows.first;
  return rows.skip(1).map((row) {
    final record = <String, String>{};
    for (var i = 0; i < header.length; i++) {
      final cell = i < row.length ? row[i] : '';
      record[header[i]] = cell.trim() == naCell ? '' : cell;
    }
    return record;
  }).toList();
}

/// Serialize records to a TSV with the given column order as the header.
///
/// A column a record does not carry, or carries as an empty string, is written
/// as [naCell] rather than left blank — see its doc comment for why.
String writeTsvRecords(
  List<String> columns,
  List<Map<String, String>> records,
) {
  final rows = <List<String>>[columns];
  for (final record in records) {
    rows.add(
      columns.map((col) {
        final value = record[col] ?? '';
        return value.isEmpty ? naCell : value;
      }).toList(),
    );
  }
  return writeTsv(rows);
}
