import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../models/store_model.dart';
import 'reputation_star.dart';
import 'seller_avatar.dart';

/// Ports `features/market/feed/components/store-card.tsx` — a directory tile
/// for a seller storefront: logo, name with its verified mark and reputation
/// star, tagline, then listings, positive share and city.
class StoreCard extends StatelessWidget {
  const StoreCard({super.key, required this.store, required this.onTap});

  final StoreModel store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SellerAvatar(
                  imageUrl: store.imageUrl,
                  name: store.storeName,
                  size: 48,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              store.storeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodySemibold(
                                colors.onSurface,
                              ),
                            ),
                          ),
                          if (store.isVerified) ...[
                            const SizedBox(width: 4),
                            Icon(
                              LucideIcons.badgeCheck,
                              size: 15,
                              color: colors.primary,
                            ),
                          ],
                          if (store.feedbackScore != null) ...[
                            const SizedBox(width: 6),
                            ReputationStar(
                              score: store.feedbackScore!,
                              size: 13,
                            ),
                          ],
                        ],
                      ),
                      if (store.tagline.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          store.tagline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Wraps rather than overflowing, as web's `flex-wrap
            // justify-between` does: listings, positive share and a city like
            // "Kota Administrasi Jakarta Selatan" don't fit one line on a
            // narrow phone.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.shoppingBag,
                      size: 14,
                      color: context.mutedForeground,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${store.activeListingCount} listing',
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  ],
                ),
                if (store.positivePct != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.thumbsUp,
                        size: 14,
                        color: context.mutedForeground,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        // Web's `toFixed(pct % 1 === 0 ? 0 : 1)`.
                        '${store.positivePct! % 1 == 0 ? store.positivePct!.toStringAsFixed(0) : store.positivePct!.toStringAsFixed(1)}%',
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                    ],
                  ),
                if (store.cityName.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.mapPin,
                        size: 14,
                        color: context.mutedForeground,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          store.cityName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
