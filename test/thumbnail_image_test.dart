import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pokepedia_mobile/core/utils/image_url.dart';
import 'package:pokepedia_mobile/shared/widgets/app_network_image.dart';

const _app = 'https://www.pokepedia.id';
const _scan = 'https://cdn.pokepedia.id/AC3a/006_205.webp';

String _proxied(String url, int width) =>
    '$_app/api/image-proxy?url=${Uri.encodeQueryComponent(url)}&w=$width';

/// Grids, rows and avatars load a resized copy from web's image proxy rather
/// than the full upload — a catalog scan is ~870px wide and a tile ~180.
void main() {
  group('thumbnailUrl', () {
    test('half and poster ask the proxy for its widths', () {
      expect(
        thumbnailUrl(_scan, ImageSize.half, appUrl: _app),
        _proxied(_scan, 480),
      );
      expect(
        thumbnailUrl(_scan, ImageSize.poster, appUrl: _app),
        _proxied(_scan, 160),
      );
    });

    test('full is the original', () {
      expect(thumbnailUrl(_scan, ImageSize.full, appUrl: _app), _scan);
    });

    test('uploads in Supabase storage are resized too', () {
      const avatar =
          'https://tlauakxyrxpwnwgdywum.supabase.co/storage/v1/object/public/avatars/u/1.jpg?v=3';
      expect(
        thumbnailUrl(avatar, ImageSize.half, appUrl: _app),
        _proxied(avatar, 480),
      );
    });

    test('what the proxy refuses or cannot shrink is left alone', () {
      // A host outside web's allowlist answers 403.
      const elsewhere = 'https://lh3.googleusercontent.com/a/photo.jpg';
      expect(thumbnailUrl(elsewhere, ImageSize.half, appUrl: _app), elsewhere);
      // SVG is refused; a GIF would come back frozen on one frame.
      const symbol = 'https://cdn2.pokepedia.id/set_svg/en/base.svg';
      expect(thumbnailUrl(symbol, ImageSize.half, appUrl: _app), symbol);
      const gif = 'https://cdn.pokepedia.id/promo/banner.gif';
      expect(thumbnailUrl(gif, ImageSize.half, appUrl: _app), gif);
    });

    test('nothing in, nothing out', () {
      expect(thumbnailUrl(null, ImageSize.half, appUrl: _app), isNull);
      expect(thumbnailUrl('', ImageSize.half, appUrl: _app), isNull);
    });
  });

  group('ProxyBreaker', () {
    test('opens after five refusals in a row', () {
      final breaker = ProxyBreaker();
      for (var i = 0; i < 4; i++) {
        breaker.record(const HttpExceptionWithStatus(429, 'challenge'));
      }
      expect(breaker.open, isFalse);
      breaker.record(const HttpExceptionWithStatus(429, 'challenge'));
      expect(breaker.open, isTrue);
    });

    test('a thumbnail that arrives resets the count', () {
      final breaker = ProxyBreaker();
      for (var i = 0; i < 4; i++) {
        breaker.record(const HttpExceptionWithStatus(502, 'down'));
      }
      breaker.record(null);
      for (var i = 0; i < 4; i++) {
        breaker.record(const HttpExceptionWithStatus(502, 'down'));
      }
      expect(breaker.open, isFalse);
    });

    test('being offline is not the proxy refusing', () {
      final breaker = ProxyBreaker();
      for (var i = 0; i < 10; i++) {
        breaker.record(const SocketException('no route to host'));
      }
      expect(breaker.open, isFalse);
    });
  });

  group('a thumbnail that fails', () {
    late BaseCacheManager previous;
    late _FakeCacheManager fake;

    setUp(() {
      previous = appImageCacheManager;
      fake = _FakeCacheManager();
      appImageCacheManager = fake;
      proxyBreaker.reset();
    });

    tearDown(() {
      appImageCacheManager = previous;
      proxyBreaker.reset();
      PaintingBinding.instance.imageCache.clear();
    });

    Future<void> pumpUntilSettled(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    testWidgets('falls back to the original rather than going blank', (
      tester,
    ) async {
      fake.refuseThumbnails = true;
      await tester.pumpWidget(
        MaterialApp(
          home: cachedNetworkImage(
            _scan,
            size: ImageSize.half,
            errorBuilder: (_, __, ___) => const Text('broken'),
          ),
        ),
      );
      await pumpUntilSettled(tester);

      expect(find.text('broken'), findsNothing);
      expect(fake.requested.first, contains('/api/image-proxy'));
      expect(fake.requested, contains(_scan));
    });

    testWidgets('a thumbnail that arrives is all that is fetched', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: cachedNetworkImage(_scan, size: ImageSize.half)),
      );
      await pumpUntilSettled(tester);

      expect(fake.requested, hasLength(1));
      expect(fake.requested.single, contains('/api/image-proxy'));
    });

    testWidgets('once the proxy is written off, originals are fetched direct', (
      tester,
    ) async {
      for (var i = 0; i < 5; i++) {
        proxyBreaker.record(const HttpExceptionWithStatus(429, 'challenge'));
      }
      await tester.pumpWidget(
        MaterialApp(home: cachedNetworkImage(_scan, size: ImageSize.half)),
      );
      await pumpUntilSettled(tester);

      expect(fake.requested, [_scan]);
    });
  });
}

/// Serves a 1×1 PNG for every URL, or a 429 for the proxy's when
/// [refuseThumbnails] — what Vercel's challenge page looks like from here.
class _FakeCacheManager implements BaseCacheManager {
  bool refuseThumbnails = false;
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
    if (refuseThumbnails && url.contains('/api/image-proxy')) {
      throw HttpExceptionWithStatus(429, 'challenge', uri: Uri.parse(url));
    }
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
