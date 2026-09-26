import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Writes the exact bytes a scan sent, so a miss can be looked at.
///
/// The web scanner has this already — `uploadDebugFrame` posts the frame to
/// `/api/scan-debug` precisely because "a bad final crop is diagnosable end
/// to end" only when you can see the crop. Reasoning backwards from
/// "kartu tidak dikenali" is guesswork: the same message covers a crop that
/// is skewed, off-centre, upside down, too dark, or perfectly good against a
/// catalog that simply has no render of that print.
///
/// Debug builds only, and best-effort: a scan must never fail because its
/// diagnostic copy could not be written.
Future<String?> dumpScanCapture(Uint8List bytes, {String tag = 'scan'}) async {
  if (!kDebugMode) return null;
  try {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/${tag}_$stamp.jpg');
    await file.writeAsBytes(bytes, flush: true);
    debugPrint('[scan] capture written to ${file.path} (${bytes.length}B)');
    return file.path;
  } catch (e) {
    debugPrint('[scan] could not write capture: $e');
    return null;
  }
}
