import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// What the app's CSV exports share: how a file is laid out, and how it
/// reaches the user.

/// A CSV file of [rows], the first being the header.
///
/// It opens with a byte-order mark, without which Excel reads the file as
/// Latin-1 and garbles any name outside ASCII, and breaks lines CRLF, as
/// RFC 4180 has it.
String csvDocument(List<List<String>> rows) =>
    '﻿${rows.map((r) => r.map(_field).join(',')).join('\r\n')}\r\n';

/// A value someone typed or a name from the catalog. A spreadsheet runs a
/// cell that opens with one of these as a formula; a leading quote keeps
/// the text text.
String csvText(String value) =>
    value.startsWith(RegExp(r'[=+\-@]')) ? "'$value" : value;

/// `2026-09-13`.
String csvDay(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// `2026-09-13 14:05` — what every spreadsheet reads as a date and time.
String csvStamp(DateTime d) => '${csvDay(d)} ${_two(d.hour)}:${_two(d.minute)}';

String _two(int n) => n.toString().padLeft(2, '0');

/// Quoted when it holds a comma, a quote or a line break.
String _field(String value) {
  if (!value.contains(RegExp(r'[",\r\n]'))) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// Hands a finished CSV to the share sheet, where it can be saved to
/// Files, Drive, or sent on. A provider so tests can catch the file rather
/// than reach for a platform directory they don't have.
typedef CsvSharer =
    Future<void> Function(String fileName, String csv, Rect? origin);

final csvSharerProvider = Provider<CsvSharer>((ref) => _shareCsv);

Future<void> _shareCsv(String fileName, String csv, Rect? origin) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(utf8.encode(csv));
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      fileNameOverrides: [fileName],
      // iPad anchors the share popover here, and refuses without it.
      sharePositionOrigin: origin,
    ),
  );
}

/// Where the share popover should point: the widget [context] belongs to.
Rect? shareOriginOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
