import 'package:csv/csv.dart';

/// Tab-separated I/O that matches Python's `csv` module with `delimiter='\t'`.
///
/// The desktop app quotes any field containing a tab, newline, or quote (CSV
/// RFC4180 style), so fields such as `notes` and newline-separated `scale_name`
/// values can contain embedded newlines. We reuse the `csv` package rather than
/// hand-rolling a parser so that quoting/escaping stays compatible.

/// Parse a TSV document into rows of string cells. Auto-detects `\r\n` vs `\n`
/// line endings (the desktop app writes `\r\n`, but be lenient on read).
List<List<String>> parseTsv(String content) {
  if (content.isEmpty) return <List<String>>[];
  final eol = content.contains('\r\n') ? '\r\n' : '\n';
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

/// Serialize rows to a TSV document using `\r\n` line endings to match the
/// desktop writer, so a tablet-written file is drop-in for the Qt app.
String writeTsv(List<List<String>> rows) {
  return const ListToCsvConverter(
    fieldDelimiter: '\t',
    textDelimiter: '"',
    eol: '\r\n',
  ).convert(rows);
}

/// Parse a TSV with a header row into a list of column->value maps.
List<Map<String, String>> parseTsvRecords(String content) {
  final rows = parseTsv(content);
  if (rows.isEmpty) return <Map<String, String>>[];
  final header = rows.first;
  return rows.skip(1).map((row) {
    final record = <String, String>{};
    for (var i = 0; i < header.length; i++) {
      record[header[i]] = i < row.length ? row[i] : '';
    }
    return record;
  }).toList();
}

/// Serialize records to a TSV with the given column order as the header.
String writeTsvRecords(
  List<String> columns,
  List<Map<String, String>> records,
) {
  final rows = <List<String>>[columns];
  for (final record in records) {
    rows.add(columns.map((col) => record[col] ?? '').toList());
  }
  return writeTsv(rows);
}
