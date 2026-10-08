import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../utils/sealed_image.dart';
import 'shimmer_box.dart';

/// Pokemon-card artwork (245:342 aspect ratio).
///
/// Three states, and they are not the same thing: artwork that is still
/// arriving shimmers, artwork the catalog does not have falls back to the
/// bundled card back, and artwork that failed to load does too. The card
/// back used to stand in for all three, which read as "this card has no art"
/// while it was simply loading — and paid for a decode of the bundled asset
/// on every tile in a grid to say so.
///
/// Sealed-product photos are contained rather than cropped, and drawn from
/// their thumbnail unless [thumbnail] is off — web's `cardTileImage`.
class CardArt extends StatelessWidget {
  const CardArt({
    super.key,
    this.imageUrl,
    this.borderRadius = AppRadius.md,
    this.aspectRatio = 245 / 342,
    this.alignment = Alignment.center,
    this.thumbnail = true,
  });

  final String? imageUrl;
  final double borderRadius;

  /// The window the artwork is drawn in. The card's own 245:342 by default;
  /// a wider one crops, since the fit is `cover`.
  final double aspectRatio;

  /// Which part of the card survives that crop. `Alignment.center` keeps the
  /// middle; a negative y walks up towards the illustration, which is what a
  /// landscape thumbnail wants — the middle of a card is mostly its attack
  /// text.
  final Alignment alignment;

  /// Whether a sealed product loads its thumbnail. Off for a hero drawn
  /// wider than the thumbnail, which web loads at full size too.
  final bool thumbnail;

  @override
  Widget build(BuildContext context) {
    final tile = cardTileImage(imageUrl);
    final url = thumbnail || !tile.contain ? tile.url : imageUrl;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        // borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          color: Theme.of(context).colorScheme.secondary,
          child: url == null
              ? _CardBack(alignment: alignment)
              : LayoutBuilder(
                  builder: (context, constraints) => Image.network(
                    url,
                    fit: tile.contain ? BoxFit.contain : BoxFit.cover,
                    alignment: alignment,
                    // Decoded at the size it is drawn at. A catalog scan is
                    // ~750px wide and a grid tile is ~180: without this each
                    // tile holds the full-resolution bitmap in memory, which
                    // is most of what a long grid costs.
                    cacheWidth: _decodeWidth(context, constraints.maxWidth),
                    loadingBuilder: (context, child, progress) =>
                        progress == null ? child : const ShimmerBox(),
                    errorBuilder: (context, error, stackTrace) =>
                        _CardBack(alignment: alignment),
                  ),
                ),
        ),
      ),
    );
  }

  /// The width to decode at, in device pixels — null when the box has no
  /// bounded width to measure, in which case the full image is the only safe
  /// answer.
  ///
  /// Rounded up to a multiple of [_decodeBucket] because the decoded bitmap
  /// is cached under its size: a tile 186px wide and the same card 190px wide
  /// in another grid are two entries for one picture, decoded twice and held
  /// twice. Two-column and three-column grids land in different buckets, so
  /// the sizes that actually differ still get their own decode.
  static int? _decodeWidth(BuildContext context, double logicalWidth) {
    if (!logicalWidth.isFinite || logicalWidth <= 0) return null;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final pixels = logicalWidth * ratio;
    return (pixels / _decodeBucket).ceil() * _decodeBucket;
  }

  /// Rounding up never costs detail — the bitmap is only ever drawn smaller
  /// than it was decoded.
  static const _decodeBucket = 64;
}

class _CardBack extends StatelessWidget {
  const _CardBack({this.alignment = Alignment.center});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/backcard.webp',
    fit: BoxFit.cover,
    alignment: alignment,
  );
}
