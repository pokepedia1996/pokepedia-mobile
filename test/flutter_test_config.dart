import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:pokepedia_mobile/shared/widgets/app_network_image.dart';

/// Runs before every test file.
///
/// The app's image cache keeps its files under the OS cache directory and
/// its index in SQLite, neither of which exists under `flutter test`, and
/// its download never settles under the widget-test binding — so a picture
/// neither loads nor fails and its `errorBuilder` never shows. This one is
/// offline: every fetch fails at once, the way `Image.network` always did
/// here, so the error branch is what a pump lands on.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  appImageCacheManager = _OfflineCacheManager();
  await testMain();
}

class _OfflineCacheManager implements BaseCacheManager {
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => Stream.error(
    HttpExceptionWithStatus(404, 'offline in tests', uri: Uri.parse(url)),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not used by images');
}
