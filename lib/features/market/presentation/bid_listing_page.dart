import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/listing_model.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/condition_badge.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/image_lightbox.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/reputation_star.dart';
import '../../../shared/widgets/seller_avatar.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../expansions/presentation/widgets/card_details_section.dart';
import '../../expansions/presentation/widgets/market_activity_section.dart';
import '../../expansions/presentation/widgets/bid_proposal_sheet.dart';
import '../../expansions/presentation/widgets/place_order_sheet.dart';
import '../../expansions/usecase/expansions_notifier.dart';
import '../../expansions/utils/untradeable_expansions.dart';
import '../usecase/market_notifier.dart';

/// The WTB half of [StoreCardListingPage] — one buyer's wanted-ad for one
/// card, opened when a BID tile in the marketplace is tapped. Until this
/// existed those tiles fell through to the catalog card page, which says
/// nothing about the bid that was tapped.
///
/// Same shape as the WTS page — context line, artwork, title, the panel,
/// then the card's market history and its own details — with the parts a
/// wanted-ad doesn't have left out: there are no seller photos of a copy
/// nobody owns yet, no condition picker (a bid names one condition), and no
/// cart — a bid is not something to buy. What the panel offers instead are
/// the two ways to answer one: put your own bid on the book beside it, or
/// sell into this one.
class BidListingPage extends ConsumerWidget {
  const BidListingPage({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(bidListingProvider(slug));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: async.when(
        data: (data) {
          if (data == null) {
            return EmptyState(
              icon: LucideIcons.handCoins,
              title: 'Bid tidak lagi tersedia',
              description:
                  'Pembeli mungkin sudah membatalkan atau memenuhi permintaan '
                  'kartu ini.',
              action: OutlinedButton(
                onPressed: () => context.push(Routes.market),
                child: const Text('Lihat market'),
              ),
            );
          }

          final listing = data.listing;
          final card = data.card;

          return AppBarOverlayBody(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                // _TitleLine(listing: listing, card: card),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    // The catalog artwork, not a photo: nobody is selling a
                    // copy here, so there is none to photograph.
                    child: GestureDetector(
                      onTap: () => showImageLightbox(
                        context,
                        imageUrl: card.imageUrl,
                        heroTag: 'card-image-${card.id}',
                      ),
                      child: Hero(
                        tag: 'card-image-${card.id}',
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            border: Border.all(color: context.borderColor),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: CardArt(
                            imageUrl: card.imageUrl,
                            borderRadius: AppRadius.lg,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                CardTitleLine(card: card),
                const SizedBox(height: 14),

                _BidPanel(
                  listing: listing,
                  card: card,
                  positivePct: data.positivePct,
                  feedbackScore: data.feedbackScore,
                ),
                const SizedBox(height: 20),

                // The same two market sections the WTS page stacks, in the
                // same order: what a bid is worth answering is a question
                // about the card's market, not about the bid.
                SalesHistorySection(cardId: card.id),
                const SizedBox(height: 16),
                MarketActivitySection(cardId: card.id),

                const SizedBox(height: 20),
                Divider(height: 1, color: context.borderColor),
                const SizedBox(height: 16),
                CardDetailsHeader(card: card),
                const SizedBox(height: 12),
                CardDetailsSection(card: card),
              ],
            ),
          );
        },
        loading: () => const PikachuLoader(),
        error: (_, __) => const EmptyState(
          icon: LucideIcons.circleAlert,
          title: 'Gagal memuat bid',
        ),
      ),
    );
  }
}

/// What the bid is, the two things there are to do about it, and who placed
/// it — in that order.
class _BidPanel extends ConsumerWidget {
  const _BidPanel({
    required this.listing,
    required this.card,
    required this.positivePct,
    required this.feedbackScore,
  });

  final ListingModel listing;
  final CardModel card;
  final double? positivePct;
  final int feedbackScore;

  /// Whether the viewer is the one who placed this bid.
  ///
  /// Compared against `listings.user_id` rather than the store handle, for
  /// the same reason the WTS page does: a second account can browse it, and
  /// it is the row's owner every RPC checks.
  bool _isOwnBid(WidgetRef ref) {
    final me = ref.read(authProvider).valueOrNull?.id;
    return me != null && me.isNotEmpty && me == listing.sellerId;
  }

  Future<void> _placeBid(BuildContext context, WidgetRef ref) async {
    if (ref.read(authProvider).valueOrNull == null) {
      context.push(Routes.login);
      return;
    }

    // Prefilled with the bid on screen: someone opening this page and
    // reaching for the button is reacting to that number, whether they mean
    // to match it or to outbid it.
    final placed = await showPlaceOrderSheet(
      context,
      card: card,
      side: 'bid',
      bestPrice: listing.price,
    );
    if (placed != true) return;

    ref.invalidate(orderBookProvider);
    ref.invalidate(bidListingProvider(listing.slug));
  }

  /// Sell into this bid: a proposal to this one buyer, not the broadcast to
  /// a whole price level the order book sends. The condition is the bid's
  /// own — `submit_bid_proposal` rejects anything else — so the sheet shows
  /// it rather than asking.
  Future<void> _fulfilBid(BuildContext context, WidgetRef ref) async {
    if (ref.read(authProvider).valueOrNull == null) {
      context.push(Routes.login);
      return;
    }

    final sent = await showBidProposalSheet(
      context,
      card: card,
      price: listing.price,
      condition: listing.condition,
      variantKey: listing.variantKey,
      target: (
        slug: listing.slug,
        available: listing.available,
        buyerName: listing.storeName,
      ),
    );
    if (sent == null || !context.mounted) return;

    ref.invalidate(orderBookProvider);
    ref.invalidate(bidListingProvider(listing.slug));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Proposal terkirim ke ${listing.storeName}!'),
          persist: false,
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final semantic = context.appSemantic;
    final ownBid = _isOwnBid(ref);
    final untradeable = isUntradeableExpansion(card.expansionCode);
    // Every copy the buyer asked for is already spoken for, so there is
    // nothing left to sell them — but the card is still biddable.
    final soldOut = listing.available <= 0;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: semantic.bid,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'BID (WTB)',
                        style: AppTypography.badge(Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConditionBadge(
                      condition: listing.condition,
                      full: true,
                      colored: true,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  formatRupiah(listing.price),
                  style: AppTypography.h2(colors.onSurface).copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${listing.available} dicari · dipasang '
                  '${formatRelativeId(listing.createdAt)}',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: ownBid || untradeable || soldOut
                            ? null
                            : () => _fulfilBid(context, ref),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: semantic.success,
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text(
                          'Penuhi Bid',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Divider(height: 1, color: context.borderColor),
          _BuyerStrip(
            listing: listing,
            positivePct: positivePct,
            feedbackScore: feedbackScore,
          ),
        ],
      ),
    );
  }
}

/// Who placed the bid. Identity only — the WTS strip's contact, follow and
/// share buttons belong to a shop, and this page is deliberately one action
/// wide.
class _BuyerStrip extends StatelessWidget {
  const _BuyerStrip({
    required this.listing,
    required this.positivePct,
    required this.feedbackScore,
  });

  final ListingModel listing;
  final double? positivePct;
  final int feedbackScore;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // A buyer who has never sold has no storefront to open.
    final hasStore = listing.storeSlug.isNotEmpty;

    return InkWell(
      onTap: hasStore
          ? () => context.push(Routes.storeDetail(listing.storeSlug))
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            SellerAvatar(
              name: listing.storeName,
              imageUrl: listing.sellerImageUrl,
              size: 36,
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
                          listing.storeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmSemibold(
                            hasStore ? colors.primary : colors.onSurface,
                          ),
                        ),
                      ),
                      if (listing.isVerified) ...[
                        const SizedBox(width: 4),
                        Icon(
                          LucideIcons.badgeCheck,
                          size: 14,
                          color: colors.primary,
                        ),
                      ],
                      const SizedBox(width: 6),
                      ReputationStar(score: feedbackScore, size: 13),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    positivePct == null
                        ? 'Pembeli baru'
                        : '${positivePct!.toStringAsFixed(positivePct! % 1 == 0 ? 0 : 1)}% positif',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                  if (listing.cityName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.mapPin,
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
            if (hasStore)
              Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: context.mutedForeground,
              ),
          ],
        ),
      ),
    );
  }
}
