/// Sealed-product artwork helpers, ported from `pokepedia-web/lib/sealed/keys.ts`.
///
/// A sealed product's photo is a box or a pack, not a 245:342 card scan, so
/// cropping it to the card window cuts the product in half. Web draws these
/// contained, from a narrower thumbnail, wherever it draws a card tile
/// (`cardTileImage`).
library;

/// `SEALED_KEY_PREFIX` — every sealed image lives under this R2 folder.
const _sealedKeyPrefix = 'sealed';

/// `SEALED_THUMB_WIDTH` — the width the importer writes each thumbnail at.
const sealedThumbWidth = 480;

/// The hosts web's `isAllowedImageUrl` trusts for catalog artwork; a
/// `/sealed/` path anywhere else is not one of ours.
const _catalogImageHosts = {
  'cdn.pokepedia.id',
  'cdn2.pokepedia.id',
  'pub-61ccf1b9e1ab4037b28e968ea11d9d1f.r2.dev',
  'pub-823786ff78eb4cc8944cdb3f627a1b6a.r2.dev',
};

/// Ports `isSealedImageUrl`.
bool isSealedImageUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null || !_catalogImageHosts.contains(uri.host)) return false;
  return uri.path.startsWith('/$_sealedKeyPrefix/');
}

final _masterWebp = RegExp(r'(?<!_\d+)\.webp$');

/// Ports `sealedThumbUrl` — the master's `_480` sibling. A URL that already
/// names a sized variant is left alone.
String sealedThumbUrl(String url) =>
    url.replaceFirst(_masterWebp, '_$sealedThumbWidth.webp');

/// Ports `cardTileImage`: what a tile should load, and whether to contain
/// it rather than crop it to the card window.
({String? url, bool contain}) cardTileImage(String? url) {
  if (url == null || url.isEmpty) return (url: null, contain: false);
  return isSealedImageUrl(url)
      ? (url: sealedThumbUrl(url), contain: true)
      : (url: url, contain: false);
}
