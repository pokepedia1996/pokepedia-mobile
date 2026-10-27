import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../core/utils/image_url.dart';

/// Where remote pictures are kept on disk between fetches.
///
/// `Image.network` has no disk cache — its `HttpClient` ignores the CDN's
/// `Cache-Control` — so every picture was downloaded again on each launch,
/// and again whenever the in-memory `ImageCache` evicted its bitmap while
/// scrolling a long grid. This keeps the encoded bytes instead, so a miss in
/// memory is a file read rather than a download.
///
/// Bounded both ways: the least recently used file goes once there are
/// [_maxFiles], and anything unused for [_stalePeriod] is dropped — the
/// CDN's own `s-maxage` is a week, so art replaced in place is picked up
/// within two. The files live in the OS cache directory, which the system
/// may clear under storage pressure and the user can clear from settings.
BaseCacheManager get appImageCacheManager => _manager ??= CacheManager(
  Config(
    'pokepediaImages',
    stalePeriod: _stalePeriod,
    maxNrOfCacheObjects: _maxFiles,
  ),
);

/// Swaps the store out. Tests have no platform directory or SQLite to put
/// the real one in, so `flutter_test_config.dart` hands it an offline one.
@visibleForTesting
set appImageCacheManager(BaseCacheManager manager) => _manager = manager;

BaseCacheManager? _manager;

const _stalePeriod = Duration(days: 14);
const _maxFiles = 1000;

/// The provider for a remote picture, backed by [appImageCacheManager].
///
/// For the places that take an `ImageProvider` rather than an `Image` — a
/// `CircleAvatar`'s `backgroundImage`, a `precacheImage` — so they share
/// one cache entry with the `Image` that later draws the same URL.
///
/// At a [size] below [ImageSize.full] it fetches the resized copy from
/// [thumbnailUrl], and falls back to [url] itself if that fails.
ImageProvider cachedImageProvider(
  String url, {
  double scale = 1.0,
  ImageSize size = ImageSize.full,
}) {
  final thumbnail = thumbnailUrl(url, size);
  if (thumbnail == null || thumbnail == url) return _cached(url, scale);
  return _ThumbnailImageProvider(thumbnail, url, scale);
}

CachedNetworkImageProvider _cached(String url, double scale) =>
    CachedNetworkImageProvider(
      url,
      scale: scale,
      cacheManager: appImageCacheManager,
    );

/// `Image.network`, kept on disk by [appImageCacheManager].
///
/// Takes exactly `Image.network`'s arguments, and returns a plain [Image],
/// so a call site swaps over without changing shape — `loadingBuilder`,
/// `errorBuilder` and `cacheWidth` behave as they did, and code that walks
/// the tree for `Image` widgets (the poster's wait-for-art) still finds it.
/// [size] picks a thumbnail, as [cachedImageProvider] does.
Image cachedNetworkImage(
  String src, {
  Key? key,
  double scale = 1.0,
  ImageSize size = ImageSize.full,
  ImageFrameBuilder? frameBuilder,
  ImageLoadingBuilder? loadingBuilder,
  ImageErrorWidgetBuilder? errorBuilder,
  String? semanticLabel,
  bool excludeFromSemantics = false,
  double? width,
  double? height,
  Color? color,
  Animation<double>? opacity,
  BlendMode? colorBlendMode,
  BoxFit? fit,
  AlignmentGeometry alignment = Alignment.center,
  ImageRepeat repeat = ImageRepeat.noRepeat,
  Rect? centerSlice,
  bool matchTextDirection = false,
  bool gaplessPlayback = false,
  FilterQuality filterQuality = FilterQuality.medium,
  bool isAntiAlias = false,
  int? cacheWidth,
  int? cacheHeight,
}) {
  return Image(
    key: key,
    image: ResizeImage.resizeIfNeeded(
      cacheWidth,
      cacheHeight,
      cachedImageProvider(src, scale: scale, size: size),
    ),
    frameBuilder: frameBuilder,
    loadingBuilder: loadingBuilder,
    errorBuilder: errorBuilder,
    semanticLabel: semanticLabel,
    excludeFromSemantics: excludeFromSemantics,
    width: width,
    height: height,
    color: color,
    opacity: opacity,
    colorBlendMode: colorBlendMode,
    fit: fit,
    alignment: alignment,
    repeat: repeat,
    centerSlice: centerSlice,
    matchTextDirection: matchTextDirection,
    gaplessPlayback: gaplessPlayback,
    filterQuality: filterQuality,
    isAntiAlias: isAntiAlias,
  );
}

/// A thumbnail from `/api/image-proxy`, standing on the original.
///
/// The proxy is one hop more than the CDN, and it sits behind Vercel's
/// firewall, which answers a challenge page to clients it distrusts — so a
/// thumbnail that fails is fetched again as the original rather than left
/// blank. Both go through [appImageCacheManager], each under its own URL.
///
/// Built on the inner providers' `loadImage` rather than `resolve`, so a
/// `ResizeImage` around this still decodes whichever arrives at its
/// `cacheWidth`.
class _ThumbnailImageProvider extends ImageProvider<_ThumbnailImageProvider> {
  const _ThumbnailImageProvider(this.thumbnail, this.original, this.scale);

  final String thumbnail;
  final String original;
  final double scale;

  @override
  Future<_ThumbnailImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _ThumbnailImageProvider key,
    ImageDecoderCallback decode,
  ) {
    ImageStreamCompleter load(String url) {
      final provider = _cached(url, scale);
      return provider.loadImage(provider, decode);
    }

    if (proxyBreaker.open) return load(original);
    return _FallbackCompleter(
      primary: load(thumbnail),
      fallback: () => load(original),
      onPrimarySettled: proxyBreaker.record,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _ThumbnailImageProvider &&
      other.thumbnail == thumbnail &&
      other.original == original &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(thumbnail, original, scale);
}

/// Stops asking the proxy once it has refused [_threshold] thumbnails in a
/// row.
///
/// Each refusal costs a wasted request before the fallback, so while the
/// proxy is down — Vercel's attack-challenge mode answers every request
/// with a 429 page — the app goes straight to the originals for the rest of
/// the session instead of paying that on every picture. Only an answer from
/// the server counts: a phone that is merely offline fails the original
/// just the same, and must not switch thumbnails off for when it is back.
@visibleForTesting
final proxyBreaker = ProxyBreaker();

@visibleForTesting
class ProxyBreaker {
  static const _threshold = 5;

  int _refusals = 0;

  bool get open => _refusals >= _threshold;

  /// Called with null when a thumbnail arrived, or with what it failed on.
  void record(Object? error) {
    if (open) return;
    if (error == null) {
      _refusals = 0;
    } else if (error is HttpExceptionWithStatus) {
      _refusals++;
    }
  }

  void reset() => _refusals = 0;
}

/// Follows [primary]; if it fails, follows the completer [fallback] makes
/// instead, and reports that one's outcome. [onPrimarySettled] hears once,
/// with whichever came first from [primary]: its first frame or its error.
class _FallbackCompleter extends ImageStreamCompleter {
  _FallbackCompleter({
    required ImageStreamCompleter primary,
    required ImageStreamCompleter Function() fallback,
    required void Function(Object? error) onPrimarySettled,
  }) {
    var settled = false;
    _follow(
      primary,
      onImage: () {
        if (settled) return;
        settled = true;
        onPrimarySettled(null);
      },
      onError: (error, stack) {
        if (!settled) onPrimarySettled(error);
        settled = true;
        _follow(
          fallback(),
          onImage: () {},
          onError: (error, stack) =>
              reportError(exception: error, stack: stack),
        );
      },
    );
  }

  /// Only once this is disposed, not whenever its last listener goes: the
  /// image cache holds a pending load alive across a rebuild that drops and
  /// re-adds the `Image`, and letting go of the source then would leave that
  /// load with nothing to finish it.
  @override
  void onDisposed() {
    _unfollow();
    super.onDisposed();
  }

  ImageStreamCompleter? _source;
  ImageStreamListener? _listener;

  void _follow(
    ImageStreamCompleter source, {
    required VoidCallback onImage,
    required void Function(Object error, StackTrace? stack) onError,
  }) {
    _unfollow();
    final listener = ImageStreamListener(
      (image, synchronousCall) {
        onImage();
        setImage(image);
      },
      onChunk: reportImageChunkEvent,
      onError: onError,
    );
    _source = source;
    _listener = listener;
    source.addListener(listener);
  }

  void _unfollow() {
    final listener = _listener;
    if (listener != null) _source?.removeListener(listener);
    _source = null;
    _listener = null;
  }
}
