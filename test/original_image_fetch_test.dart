import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pokepedia_mobile/core/utils/image_url.dart';
import 'package:pokepedia_mobile/shared/widgets/app_network_image.dart';

const _scan = 'https://cdn.pokepedia.id/AC3a/006_205.webp';

/// Every picture is the original from the CDN — web's `/api/image-proxy`
/// resized on Vercel, which cost more than the bandwidth it saved.
void main() {
  late BaseCacheManager previous;
  late _FakeCacheManager fake;

  setUp(() {
    previous = appImageCacheManager;
    fake = _FakeCacheManager();
    appImageCacheManager = fake;
  });

  tearDown(() {
    appImageCacheManager = previous;
    PaintingBinding.instance.imageCache.clear();
  });

  for (final size in ImageSize.values) {
    testWidgets('$size fetches the original, never the proxy', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: cachedNetworkImage(_scan, size: size)),
      );
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }

      expect(fake.requested, [_scan]);
    });
  }
}

/// Serves a 1×1 PNG for every URL, and notes what was asked for.
class _FakeCacheManager implements BaseCacheManager {
  final requested = <String>[];

  static final _png = img.encodePng(img.Image(width: 1, height: 1));

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    requested.add(url);
    final file = await MemoryCacheSystem().createFile(
      '${requested.length}.png',
    );
    await file.writeAsBytes(_png);
    yield FileInfo(
      file,
      FileSource.Online,
      DateTime.now().add(const Duration(days: 1)),
      url,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not used by images');
}
