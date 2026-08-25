import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/listing_model.dart';
import '../../../../shared/widgets/card_art.dart';
import '../../../../shared/widgets/condition_badge.dart';
import '../../usecase/market_notifier.dart';

/// "Lebih banyak dari penjual" — the rest of this seller's shelf, so a buyer
/// who came for one card can fill a single order rather than paying shipping
/// twice.
class MoreFromSellerSection extends ConsumerWidget {
  const MoreFromSellerSection({
    super.key,
    required this.storeHandle,
    required this.excludeCardId,
    this.limit = 12,
  });

  final String storeHandle;

  /// The card being viewed — showing it back to the buyer would just be a
  /// link to the page they're on.
  final int excludeCardId;

  final int limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final async = ref.watch(storeListingsProvider(storeHandle));
    final all = async.valueOrNull ?? const <ListingModel>[];

    final others = all
        .where(
          (l) =>
              l.card.id != excludeCardId &&
              // Only what's for sale: a buyer on this page is buying, and a
              // bid is the seller wanting to buy from them.
              l.side == ListingSide.ask &&
              l.status == ListingStatus.open &&
              l.available > 0,
        )
        .take(limit)
        .toList();

    // Nothing to show and nothing to explain — a seller with one card isn't
    // a problem to report.
    if (others.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Divider(height: 1, color: context.borderColor),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Lebih banyak dari penjual',
                style: AppTypography.h3(colors.onSurface),
              ),
            ),
            InkWell(
              onTap: () => context.push(Routes.storeDetail(storeHandle)),
              child: Text(
                'Lihat toko',
                style: AppTypography.captionSemibold(colors.primary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // A scrolling Row rather than a horizontal ListView: a ListView needs
        // its cross-axis extent up front, and any height hardcoded here
        // breaks the moment a name wraps or the reader scales their font.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              for (final listing in others)
                _SellerListingThumb(listing: listing, storeHandle: storeHandle),
            ],
          ),
        ),
      ],
    );
  }
}

class _SellerListingThumb extends StatelessWidget {
  const _SellerListingThumb({
    required this.listing,
    required this.storeHandle,
  });

  final ListingModel listing;
  final String storeHandle;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SizedBox(
      width: 116,
      child: InkWell(
        onTap: () => context.push(
          Routes.storeCardDetail(storeHandle, listing.card.id),
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardArt(
                imageUrl: listing.card.imageUrl,
                borderRadius: AppRadius.md,
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.card.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.captionSemibold(colors.onSurface),
                    ),
                    const SizedBox(height: 4),
                    ConditionBadge(condition: listing.condition, dense: true),
                    const SizedBox(height: 4),
                    Text(
                      formatRupiah(listing.price),
                      style: AppTypography.bodySmSemibold(colors.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
