import 'package:flutter/material.dart';

/// The heart every wishlist control draws: solid when the card is on the
/// list, hollow when it isn't.
///
/// Material's pair rather than the icon set the rest of the app uses:
/// lucide is a stroke set with no filled heart, so the "on" state used to be
/// the same outline in a different colour — which reads as a highlight
/// rather than as a state. Web fills its heart by setting `fill` on the same
/// SVG path; an icon font can't be filled, and Material's two glyphs are at
/// least the same silhouette as each other, so the toggle doesn't change
/// shape as it flips.
class WishlistHeart extends StatelessWidget {
  const WishlistHeart({
    super.key,
    required this.active,
    this.size = 16,
    this.color,
  });

  final bool active;
  final double size;

  /// Null takes the ambient icon colour, as an [Icon] would.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Icon(
      active ? Icons.favorite : Icons.favorite_border,
      size: size,
      color: color,
    );
  }
}
