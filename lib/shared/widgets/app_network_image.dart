import 'package:cached_network_image/cached_network_image.dart';
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
/// [size] is accepted but does not change the fetch: every picture is the
/// original — see [ImageSize].
ImageProvider cachedImageProvider(
  String url, {
  double scale = 1.0,
  ImageSize size = ImageSize.full,
}) => CachedNetworkImageProvider(
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
/// [size] is passed through to [cachedImageProvider].
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
