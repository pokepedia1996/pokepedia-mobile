import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';

/// The order thumbnail web draws: a **square** crop of the card art, focused
/// near the top, ringed by a border.
///
/// Not [CardArt], which frames a card at its real 245:342 portrait. Web's
/// order surfaces use `size-16 object-cover object-[center_15%]` throughout,
/// so a card in an order reads as a square tile rather than a full card —
/// which is why the two clients' order lists looked so different.
class OrderThumbnail extends StatelessWidget {
  const OrderThumbnail({
    super.key,
    required this.imageUrl,
    this.size = 64,
    this.radius = AppRadius.md,
  });

  final String? imageUrl;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final placeholder = Icon(
      LucideIcons.image,
      size: size * 0.3,
      color: context.mutedForeground,
    );

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.appColors.secondary,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: context.borderColor),
      ),
      child: url == null || url.isEmpty
          ? placeholder
          : Image.network(
              url,
              fit: BoxFit.cover,
              // `object-[center_15%]`: the focal point sits 15% down, which
              // keeps a card's art and name in frame instead of its middle.
              alignment: const Alignment(0, -0.7),
              errorBuilder: (_, __, ___) => placeholder,
            ),
    );
  }
}

/// The stacked thumbnails a multi-item package shows: the first card, the
/// second peeking out from the bottom-right corner, and a `+N` count.
class OrderThumbnailStack extends StatelessWidget {
  const OrderThumbnailStack({
    super.key,
    required this.imageUrl,
    required this.secondImageUrl,
    required this.extraCount,
  });

  final String? imageUrl;
  final String? secondImageUrl;
  final int extraCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          OrderThumbnail(imageUrl: imageUrl),
          if (extraCount >= 1 && secondImageUrl != null)
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  // The `ring-2 ring-card` that lifts it off the first.
                  border: Border.all(
                    color: Theme.of(context).cardColor,
                    width: 2,
                  ),
                ),
                child: OrderThumbnail(
                  imageUrl: secondImageUrl,
                  size: 32,
                  radius: AppRadius.xs,
                ),
              ),
            ),
          if (extraCount >= 1)
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.onSurface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '+$extraCount',
                  style: AppTypography.badge(colors.surface),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The bordered expansion-code chip beside a card's name — web's
/// `rounded border border-border bg-muted/40 px-1.5 py-0.5 uppercase`.
class ExpansionChip extends StatelessWidget {
  const ExpansionChip({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: context.appColors.secondary.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: context.borderColor),
      ),
      child: Text(
        code.toUpperCase(),
        style: AppTypography.badge(context.mutedForeground),
      ),
    );
  }
}
