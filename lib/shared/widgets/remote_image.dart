import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Whether [url] points at vector art.
///
/// Reads the *path* rather than the whole string, so a signed or
/// cache-busted URL (`…/symbol.svg?v=2`) still resolves correctly.
bool isSvgUrl(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
  return path.endsWith('.svg');
}

/// A network image that copes with the catalog holding both raster and
/// vector art.
///
/// Expansion set symbols are served as `.svg`
/// (`.../set_svg/en/ancient-origins.svg`), and `Image.network` can't decode
/// SVG — it fails silently into its `errorBuilder`, which is why every set
/// symbol in the app rendered as nothing at all. Pack art and series
/// wordmarks are `.webp` and decode normally, so the two can't share one
/// widget without choosing per URL.
///
/// The choice is made on the path's extension rather than a content-type
/// probe: it costs no extra request, and the catalog's URLs are generated
/// with real extensions.
class RemoteImage extends StatelessWidget {
  const RemoteImage({
    super.key,
    required this.url,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
    this.fallback,
  });

  final String url;
  final double? height;
  final double? width;
  final BoxFit fit;

  /// Shown when the image can't be fetched or decoded. Defaults to nothing,
  /// matching how these are used — decorative marks beside a name that
  /// reads fine on its own.
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final empty = fallback ?? const SizedBox.shrink();

    if (isSvgUrl(url)) {
      return SvgPicture.network(
        url,
        height: height,
        width: width,
        fit: fit,
        // Reserves the same box while fetching, so a row of symbols doesn't
        // reflow as they arrive one by one.
        placeholderBuilder: (_) => SizedBox(height: height, width: width),
      );
    }

    return Image.network(
      url,
      height: height,
      width: width,
      fit: fit,
      errorBuilder: (_, __, ___) => empty,
    );
  }
}
