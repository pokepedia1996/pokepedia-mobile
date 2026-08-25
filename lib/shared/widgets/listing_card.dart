import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/routes.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/card_ownership_controller.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../features/portfolio/usecase/portfolio_notifier.dart';
import '../models/listing_model.dart';
import 'card_art.dart';
import 'card_language_badge.dart';
import 'condition_badge.dart';
import 'reputation_star.dart';
import 'seller_avatar.dart';

/// Ports `features/market/ui/storefront-listing-card.tsx` — a marketplace
/// listing tile with a wishlist badge, condition, language/variant, price,
/// relative time, and seller footer. Every call site here passes a `buyable
/// = false` context (transactions are covered later), so the quantity
/// selector / "Tambah ke Keranjang" button web shows for buyable listings
/// is intentionally omitted, mirroring how the web marketplace grid itself
/// renders this component with `buyable={false}`.
class ListingCard extends ConsumerStatefulWidget {
  const ListingCard({
    super.key,
    required this.listing,
    this.onTap,
    this.showSeller = true,
  });

  final ListingModel listing;

  /// Overrides the tap destination. When omitted, mirrors web's
  /// `linkHref` fallback: a WTB (bid) listing opens the regular card page,
  /// a WTS (ask) listing opens the seller-scoped "product" page — since
  /// only that seller's copy, condition, and price are relevant there.
  final VoidCallback? onTap;
  final bool showSeller;

  @override
  ConsumerState<ListingCard> createState() => _ListingCardState();
}

class _ListingCardState extends ConsumerState<ListingCard> {
  bool _wishlistToggling = false;

  Future<void> _toggleWishlist(bool wishlisted) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) {
      context.push(Routes.login);
      return;
    }
    setState(() => _wishlistToggling = true);
    await ref
        .read(cardOwnershipControllerProvider)
        .setWishlisted(widget.listing.card.id, !wishlisted);
    if (!mounted) return;
    setState(() => _wishlistToggling = false);
  }

  void _handleTap(BuildContext context) {
    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }
    final listing = widget.listing;
    if (listing.side == ListingSide.bid || listing.storeSlug.isEmpty) {
      context.push(Routes.cardDetail(listing.card.packSlug, listing.card.id));
    } else {
      context.push(Routes.storeCardDetail(listing.storeSlug, listing.card.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final colors = context.appColors;
    final semantic = context.appSemantic;
    final isBid = listing.side == ListingSide.bid;
    final wishlisted = ref.watch(isWishlistedProvider(listing.card.id));

    return InkWell(
      onTap: () => _handleTap(context),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.max,
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
                Positioned(
                  left: 6,
                  top: listing.isFeatured ? 34 : 6,
                  child: _WishlistBadge(
                    wishlisted: wishlisted,
                    loading: _wishlistToggling,
                    onTap: _wishlistToggling
                        ? null
                        : () => _toggleWishlist(wishlisted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                CardLanguageBadge(language: listing.card.language),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    listing.card.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                ),

                const SizedBox(width: 6),
                Text(
                  listing.card.collectorNumber,
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
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
                    Text(
                      '${listing.available} ${isBid ? "Dicari" : "Tersedia"}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  ],
                ),

                _buildSetSymbol(context, listing),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  formatRupiah(listing.price),
                  style: AppTypography.bodySemibold(colors.onSurface),
                ),
                const Spacer(),
                Text(
                  formatRelativeId(listing.createdAt),
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
            if (listing.acceptsOffers) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.mutedForeground.withValues(alpha: 0.06),
                  border: Border.all(color: context.borderColor),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  'dengan penawaran',
                  style: AppTypography.badge(context.mutedForeground),
                ),
              ),
            ],
            if (widget.showSeller && listing.storeSlug.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: context.borderColor)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SellerAvatar(
                          name: listing.storeName,
                          imageUrl: listing.sellerImageUrl,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            listing.storeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.captionSemibold(
                              colors.onSurface,
                            ),
                          ),
                        ),
                        if (listing.isVerified) ...[
                          const SizedBox(width: 2),
                          Icon(Icons.verified, size: 13, color: colors.primary),
                        ],
                        const SizedBox(width: 4),
                        ReputationStar(score: listing.sellerFeedbackScore),
                      ],
                    ),
                    if (listing.cityName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 11,
                            color: context.mutedForeground,
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              listing.cityName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption(
                                context.mutedForeground,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSetSymbol(BuildContext context, ListingModel listing) {
    final url = listing.expansionSetSymbolUrl;
    if (url != null && url.isNotEmpty) {
      return SvgPicture.network(
        url,
        height: 20,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            _expansionCodeText(context, listing),
      );
    }
    return _expansionCodeText(context, listing);
  }

  Widget _expansionCodeText(BuildContext context, ListingModel listing) {
    if (listing.card.expansionCode.isEmpty) return const SizedBox.shrink();
    return Text(
      listing.card.expansionCode.toUpperCase(),
      style: AppTypography.caption(context.mutedForeground),
    );
  }
}

class _WishlistBadge extends StatelessWidget {
  const _WishlistBadge({
    required this.wishlisted,
    required this.loading,
    required this.onTap,
  });

  final bool wishlisted;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: wishlisted
              ? Colors.red
              : Theme.of(context).cardColor.withValues(alpha: 0.9),
          border: wishlisted ? null : Border.all(color: context.borderColor),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: loading
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: wishlisted ? Colors.white : context.mutedForeground,
                ),
              )
            : Icon(
                wishlisted ? Icons.favorite : Icons.favorite_border,
                size: 16,
                color: wishlisted ? Colors.white : context.mutedForeground,
              ),
      ),
    );
  }
}

