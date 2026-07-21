import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../models/listing_model.dart';
import 'card_art.dart';
import 'condition_badge.dart';

/// Ports `components/store/storefront-listing-card.tsx` — a marketplace
/// listing tile with ask/bid badge, condition, price and a buy CTA.
class ListingCard extends StatelessWidget {
  const ListingCard({
    super.key,
    required this.listing,
    required this.onTap,
    this.showSeller = true,
  });

  final ListingModel listing;
  final VoidCallback onTap;
  final bool showSeller;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final semantic = context.appSemantic;
    final isBid = listing.side == ListingSide.bid;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CardArt(imageUrl: listing.card.imageUrl),
                Positioned(
                  right: 6,
                  top: 6,
                  child: ConditionBadge(condition: listing.condition),
                ),
                if (listing.isFeatured)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.12),
                        border: Border.all(
                          color: colors.primary.withValues(alpha: 0.3),
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        'Unggulan',
                        style: AppTypography.badge(colors.primary),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              listing.card.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmSemibold(colors.onSurface),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isBid ? semantic.bid : semantic.ask,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isBid ? 'BID (WTB)' : 'ASK (WTS)',
                    style: AppTypography.badge(Colors.white),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${listing.available} ${isBid ? "Dicari" : "Tersedia"}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  formatRupiah(listing.price),
                  style: AppTypography.bodySemibold(colors.onSurface),
                ),
                if (listing.acceptsOffers) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.borderColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('Nego', style: AppTypography.badge(context.mutedForeground)),
                  ),
                ],
                const Spacer(),
                Icon(Icons.visibility_outlined, size: 12, color: context.mutedForeground),
                const SizedBox(width: 2),
                Text('${listing.viewCount}', style: AppTypography.caption(context.mutedForeground)),
              ],
            ),
            if (showSeller) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.storefront_outlined,
                    size: 13,
                    color: context.mutedForeground,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      listing.storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  ),
                  if (listing.isVerified)
                    Icon(Icons.verified, size: 13, color: colors.primary),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
