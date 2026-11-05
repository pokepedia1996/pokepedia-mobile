import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'detector_worker.dart';

/// Explicitly opt in when profiling on a physical device. Normal production
/// builds do not save camera frames or emit scanner diagnostics.
const scanDiagnosticsEnabled =
    kDebugMode || bool.fromEnvironment('SCAN_DIAGNOSTICS');

// Frame encoding is intentionally opt-in; timing diagnostics alone should
// not turn every fifth second into extra JPEG work on a warm phone.
const scanSaveFrames = bool.fromEnvironment('SCAN_SAVE_FRAMES');
Future<void> _eventWrites = Future.value();

Future<void> recordScanEvent(Map<String, dynamic> event) {
  if (!scanDiagnosticsEnabled) return Future.value();
  final row = {'at': DateTime.now().toIso8601String(), ...event};
  debugPrint('[scan] $row');
  _eventWrites = _eventWrites
      .then((_) async {
        final root = await getTemporaryDirectory();
        final dir = Directory('${root.path}/scanner_diagnostics');
        await dir.create(recursive: true);
        final file = File('${dir.path}/events.jsonl');
        if (await file.exists() && await file.length() > 1024 * 1024) {
          await file.rename('${dir.path}/events.previous.jsonl');
        }
        await file.writeAsString('${jsonEncode(row)}\n', mode: FileMode.append);
      })
      .catchError((Object e) {
        debugPrint('[scan] diagnostic write failed: $e');
      });
  return _eventWrites;
}

Future<void> saveDiagnosticSnapshot(
  DetectorWorker worker,
  Map<String, dynamic> metadata, {
  required String tag,
}) async {
  try {
    final bytes = await worker.snapshot();
    if (bytes != null) {
      await dumpScanCapture(bytes, tag: tag, metadata: metadata);
    }
  } catch (e) {
    // Diagnostics must never stop recognition or replace the camera preview.
    debugPrint('[scan] optional snapshot skipped: $e');
  }
}

/// Writes the exact bytes a scan sent, so a miss can be looked at.
///
/// The web scanner has this already — `uploadDebugFrame` posts the frame to
/// `/api/scan-debug` precisely because "a bad final crop is diagnosable end
/// to end" only when you can see the crop. Reasoning backwards from
/// "kartu tidak dikenali" is guesswork: the same message covers a crop that
/// is skewed, off-centre, upside down, too dark, or perfectly good against a
/// catalog that simply has no render of that print.
///
/// Debug builds or explicit diagnostic builds, and best-effort: a scan must never fail because its
/// diagnostic copy could not be written.
Future<String?> dumpScanCapture(
  Uint8List bytes, {
  String tag = 'scan',
  Map<String, dynamic>? metadata,
}) async {
  if (!scanDiagnosticsEnabled) return null;
  try {
    final dir = await getTemporaryDirectory();
    final captures = Directory('${dir.path}/scanner_diagnostics');
    await captures.create(recursive: true);
    // Bound local storage even during a long debug scanning session.
    final old = await captures
        .list()
        .where((f) => f is File)
        .cast<File>()
        .toList();
    old.sort((a, b) => a.path.compareTo(b.path));
    for (final file in old.take((old.length - 38).clamp(0, old.length))) {
      await file.delete();
    }
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${captures.path}/${stamp}_$tag.jpg');
    await file.writeAsBytes(bytes, flush: true);
    if (metadata != null) {
      await File('${file.path}.json').writeAsString(
        jsonEncode(metadata, toEncodable: (value) => value.toString()),
      );
    }
    debugPrint('[scan] capture written to ${file.path} (${bytes.length}B)');
    return file.path;
  } catch (e) {
    debugPrint('[scan] could not write capture: $e');
    return null;
  }
}
