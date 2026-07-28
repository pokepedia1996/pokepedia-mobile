import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/card_condition.dart';
import '../../../shared/models/listing_model.dart';
import '../../../shared/models/store_model.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/reputation_star.dart';
import '../../../shared/widgets/seller_avatar.dart';
import '../usecase/market_notifier.dart';

const _monthNamesIdFull = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

String _formatDateId(DateTime date) => '${date.day} ${_monthNamesIdFull[date.month - 1]}';

/// Ports `app/market/[slug]/card/[cardId]/page.tsx` — `PerSellerCardDetail`
/// + `StorePurchasePanel` — a single seller's "product page" for one card,
/// opened when a WTS (ask) listing is tapped (WTB listings just open the
/// regular card page instead, since a wanted-ad has no single seller or
/// condition to show). Kept compact: this card's evolution/pokedex info
/// already lives on the regular card detail page, so this page only shows
/// what's specific to buying from *this* seller — their condition picker,
/// price, vacation status, and store/reputation info. Buy/offer/report/
/// admin actions from the web panel are still out of scope (transactions
/// are covered later), same as everywhere else in the market feature.
class StoreCardListingPage extends ConsumerStatefulWidget {
  const StoreCardListingPage({super.key, required this.storeSlug, required this.cardId});

  final String storeSlug;
  final int cardId;

  @override
  ConsumerState<StoreCardListingPage> createState() => _StoreCardListingPageState();
}

class _StoreCardListingPageState extends ConsumerState<StoreCardListingPage> {
  CardCondition? _selectedCondition;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(
      storeCardListingsProvider((storeSlug: widget.storeSlug, cardId: widget.cardId)),
    );

    return Scaffold(
      appBar: AppBar(
        title: async.when(
          data: (data) => Text(data == null || data.listings.isEmpty ? 'Kartu' : data.listings.first.card.name),
          loading: () => const Text('Memuat...'),
          error: (_, __) => const Text('Kartu'),
        ),
      ),
      body: async.when(
        data: (data) {
          if (data == null || data.listings.isEmpty) {
            return EmptyState(
              icon: Icons.storefront_outlined,
              title: 'Listing tidak lagi tersedia',
              description: 'Penjual ini mungkin sudah kehabisan atau menghentikan listing kartu ini.',
              action: OutlinedButton(
                onPressed: () => context.push(Routes.storeDetail(widget.storeSlug)),
                child: const Text('Lihat toko'),
              ),
            );
          }

          final cheapestByCondition = <CardCondition, ListingModel>{};
          for (final listing in data.listings) {
            final existing = cheapestByCondition[listing.condition];
            if (existing == null || listing.price < existing.price) {
              cheapestByCondition[listing.condition] = listing;
            }
          }
          final activeCondition = _selectedCondition ?? data.listings.first.condition;
          final active = cheapestByCondition[activeCondition] ?? data.listings.first;
          final card = active.card;
          final store = data.store;

          return SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 120, child: CardArt(imageUrl: card.imageUrl)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(card.name, style: AppTypography.h3(context.appColors.onSurface)),
                          const SizedBox(height: 4),
                          Text(
                            '${card.expansionCode.toUpperCase()} · No. ${card.collectorNumber}',
                            style: AppTypography.bodySm(context.mutedForeground),
                          ),
                          if (card.rarity != null) ...[
                            const SizedBox(height: 2),
                            Text(card.rarity!, style: AppTypography.bodySm(context.mutedForeground)),
                          ],
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: () => context.push(Routes.cardDetail(card.packSlug, card.id)),
                            child: const Text('Lihat detail kartu'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (store.onVacation) ...[
                  _VacationBanner(store: store),
                  const SizedBox(height: 12),
                ],
                _PurchasePanel(
                  cheapestByCondition: cheapestByCondition,
                  active: active,
                  otherSellersCount: data.otherSellersCount,
                  globalCardHref: Routes.cardDetail(card.packSlug, card.id),
                  onSelectCondition: (c) => setState(() => _selectedCondition = c),
                ),
                const SizedBox(height: 12),
                _SellerCard(
                  store: store,
                  listing: active,
                  positivePct: data.positivePct,
                  feedbackScore: data.feedbackScore,
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const EmptyState(
          icon: Icons.error_outline,
          title: 'Gagal memuat listing',
        ),
      ),
    );
  }
}

class _VacationBanner extends StatelessWidget {
  const _VacationBanner({required this.store});

  final StoreModel store;

  @override
  Widget build(BuildContext context) {
    final until = store.vacationUntil;
    final isHard = store.vacationMode == 'hard';
    final message = store.vacationMessage;
    final text = isHard
        ? 'Toko sedang libur${until != null ? ' hingga ${_formatDateId(until)}' : ''}. Checkout tidak tersedia.'
        : 'Toko libur${until != null ? ' — pengiriman tertunda hingga ${_formatDateId(until)}' : ''}'
              '${message != null && message.isNotEmpty ? '. $message' : '.'}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.beach_access_outlined, size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppTypography.caption(Colors.amber.shade900))),
        ],
      ),
    );
  }
}

class _PurchasePanel extends StatelessWidget {
  const _PurchasePanel({
    required this.cheapestByCondition,
    required this.active,
    required this.otherSellersCount,
    required this.globalCardHref,
    required this.onSelectCondition,
  });

  final Map<CardCondition, ListingModel> cheapestByCondition;
  final ListingModel active;
  final int otherSellersCount;
  final String globalCardHref;
  final void Function(CardCondition) onSelectCondition;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final semantic = context.appSemantic;
    final isBid = active.side == ListingSide.bid;

    // Group available conditions by grading company, mirroring
    // `CONDITION_COMPANIES` — "Raw" (NM/LP/MP/HP) plus PSA/BGS/CGC/EGS.
    final byCompany = <String, List<CardCondition>>{};
    for (final condition in cheapestByCondition.keys) {
      byCompany.putIfAbsent(condition.gradingCompany ?? 'Raw', () => []).add(condition);
    }
    const companyOrder = ['Raw', 'PSA', 'BGS', 'CGC', 'EGS'];

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cheapestByCondition.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  for (final company in companyOrder)
                    if (byCompany[company] != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(company, style: AppTypography.captionSemibold(context.mutedForeground)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final condition in byCompany[company]!)
                                _ConditionPill(
                                  condition: condition,
                                  active: condition == active.condition,
                                  onTap: () => onSelectCondition(condition),
                                ),
                            ],
                          ),
                        ],
                      ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isBid ? semantic.bid : semantic.ask,
                              borderRadius: BorderRadius.circular(AppRadius.full),
                            ),
                            child: Text(
                              active.condition.label,
                              style: AppTypography.badge(Colors.white),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${active.available} tersedia',
                            style: AppTypography.caption(context.mutedForeground),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatRupiah(active.price),
                        style: AppTypography.h2(colors.onSurface),
                      ),
                      if (otherSellersCount > 0) ...[
                        const SizedBox(height: 2),
                        InkWell(
                          onTap: () => context.push(globalCardHref),
                          child: Text(
                            'Lihat $otherSellersCount listing lain →',
                            style: AppTypography.captionSemibold(colors.primary),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (active.acceptsOffers)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.mutedForeground.withValues(alpha: 0.06),
                  border: Border.all(color: context.borderColor),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text('dengan penawaran', style: AppTypography.badge(context.mutedForeground)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConditionPill extends StatelessWidget {
  const _ConditionPill({required this.condition, required this.active, required this.onTap});

  final CardCondition condition;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? colors.primary : Colors.transparent,
          border: Border.all(color: active ? colors.primary : context.borderColor),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Text(
          condition.short,
          style: AppTypography.captionSemibold(active ? colors.onPrimary : context.mutedForeground),
        ),
      ),
    );
  }
}

class _SellerCard extends StatelessWidget {
  const _SellerCard({
    required this.store,
    required this.listing,
    required this.positivePct,
    required this.feedbackScore,
  });

  final StoreModel store;
  final ListingModel listing;
  final double? positivePct;
  final int feedbackScore;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final storeSlug = store.handle;
    return InkWell(
      onTap: () => context.push(Routes.storeDetail(storeSlug)),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          children: [
            SellerAvatar(name: listing.storeName, imageUrl: listing.sellerImageUrl, size: 40),
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
                          style: AppTypography.bodySmSemibold(colors.primary),
                        ),
                      ),
                      if (listing.isVerified) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified, size: 14, color: colors.primary),
                      ],
                      const SizedBox(width: 6),
                      ReputationStar(score: feedbackScore, size: 13),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    positivePct == null
                        ? 'Penjual baru'
                        : '${positivePct!.toStringAsFixed(positivePct! % 1 == 0 ? 0 : 1)}% positif'
                              ' · ${store.followersCount} pengikut',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                  if (listing.cityName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 11, color: context.mutedForeground),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            listing.cityName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption(context.mutedForeground),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.mutedForeground),
          ],
        ),
      ),
    );
  }
}
