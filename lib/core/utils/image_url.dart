import '../config/app_config.dart';

/// Ports `proxyImageUrl` from `pokepedia-web/lib/utils/index.tsx` — swaps
/// the raw R2 dev-domain hosts for their friendly CDN hostnames. Other
/// origins (e.g. Supabase storage) pass through unchanged.
const _r2Domains = <(String origin, String prefix)>[
  (
    'https://pub-61ccf1b9e1ab4037b28e968ea11d9d1f.r2.dev',
    'https://cdn.pokepedia.id',
  ),
  (
    'https://pub-823786ff78eb4cc8944cdb3f627a1b6a.r2.dev',
    'https://cdn2.pokepedia.id',
  ),
];

String? proxyImageUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  for (final (origin, prefix) in _r2Domains) {
    if (url.startsWith(origin)) {
      return url.replaceFirst(origin, prefix);
    }
  }
  return url;
}

/// How large a remote picture is fetched, relative to what was uploaded.
enum ImageSize {
  /// The original file — heroes, the lightbox, anything drawn wide.
  full,

  /// Roughly half: grids, rows and avatars.
  half,

  /// Roughly a sixth: the cards packed onto a store poster.
  poster,
}

/// The widths `/api/image-proxy` resizes to, by [ImageSize].
///
/// The proxy only accepts web's `THUMBNAIL_WIDTHS` (160, 320, 480) — any
/// other `w` silently serves the full original — so each size takes the
/// smallest of those at or above its share of a catalog scan, which is
/// ~870px wide: half is 435 → 480, a poster's 0.15 is 130 → 160.
const thumbnailWidths = {ImageSize.half: 480, ImageSize.poster: 160};

/// Web's `ALLOWED_IMAGE_ORIGINS` — the proxy answers 403 for anything else,
/// so a picture from elsewhere is fetched as it is.
const _proxyableOrigins = {
  'https://cdn.pokepedia.id',
  'https://cdn2.pokepedia.id',
  'https://tlauakxyrxpwnwgdywum.supabase.co',
  'https://pub-61ccf1b9e1ab4037b28e968ea11d9d1f.r2.dev',
  'https://pub-823786ff78eb4cc8944cdb3f627a1b6a.r2.dev',
  'https://raw.githubusercontent.com',
};

/// The proxy only decodes these (`DECODABLE_CONTENT_TYPES`); a GIF would
/// come back frozen on its first frame, and an SVG is refused.
final _resizableExtension = RegExp(r'\.(webp|jpe?g|png|avif)$');

/// Where to fetch [url] at [size]: web's `/api/image-proxy`, which resizes
/// and re-encodes it as WebP, or [url] itself when there is nothing to gain
/// — [ImageSize.full], a host the proxy refuses, or a format it can't
/// shrink.
///
/// A thumbnail URL can still fail (the proxy is one more hop, behind
/// Vercel's firewall), so it is only ever drawn with [url] as its fallback.
String? thumbnailUrl(String? url, ImageSize size, {String? appUrl}) {
  if (url == null || url.isEmpty) return null;
  final width = thumbnailWidths[size];
  if (width == null) return url;

  final uri = Uri.tryParse(url);
  if (uri == null || !_proxyableOrigins.contains(uri.origin)) return url;
  if (!_resizableExtension.hasMatch(uri.path.toLowerCase())) return url;

  final base = appUrl ?? AppConfig.appUrl;
  return Uri.parse(
    '$base/api/image-proxy',
  ).replace(queryParameters: {'url': url, 'w': '$width'}).toString();
}
