import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/listing_model.dart';
import '../../../../shared/widgets/condition_badge.dart';
import '../../../../shared/widgets/condition_grade_picker.dart';
import '../../../../shared/widgets/image_lightbox.dart';
import '../../../../shared/widgets/quantity_selector.dart';
import '../../../../shared/widgets/reputation_star.dart';
import '../../../../shared/widgets/seller_avatar.dart';
import '../../../cart/repository/cart_repository.dart';
import '../../../cart/usecase/cart_notifier.dart';
import '../../../proposals/presentation/widgets/make_offer_sheet.dart';
import '../../../proposals/repository/models/listing_offer_model.dart';
import '../../../proposals/usecase/proposals_notifier.dart';
import '../../usecase/expansions_notifier.dart';

/// How many rows are shown before "Muat lebih banyak" — web paginates at
/// the same size, but a phone reads better as one growing list.
const _pageSize = 10;

enum _Sort { priceAsc, priceDesc, createdDesc, createdAsc }

extension on _Sort {
  String get labelId => switch (this) {
    _Sort.priceAsc => 'Termurah',
    _Sort.priceDesc => 'Termahal',
    _Sort.createdDesc => 'Terbaru',
    _Sort.createdAsc => 'Terlama',
  };
}

/// Ports `features/card-detail/components/market/listings-section.tsx` —
/// every open WTS listing for this card, filterable by condition and
/// sortable, each row buyable straight into the cart.
class CardListingsSection extends ConsumerStatefulWidget {
  const CardListingsSection({super.key, required this.cardId});

  final int cardId;

  @override
  ConsumerState<CardListingsSection> createState() =>
      _CardListingsSectionState();
}

class _CardListingsSectionState extends ConsumerState<CardListingsSection> {
  CardCondition? _condition;
  _Sort _sort = _Sort.priceAsc;
  int _visible = _pageSize;

  List<ListingModel> _sorted(List<ListingModel> listings) {
    final out = [...listings];
    switch (_sort) {
      case _Sort.priceAsc:
        out.sort(
          (a, b) => a.price != b.price
              ? a.price.compareTo(b.price)
              : a.id.compareTo(b.id),
        );
      case _Sort.priceDesc:
        out.sort(
          (a, b) => a.price != b.price
              ? b.price.compareTo(a.price)
              : a.id.compareTo(b.id),
        );
      case _Sort.createdDesc:
        out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _Sort.createdAsc:
        out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final listingsAsync = ref.watch(cardListingsProvider(widget.cardId));

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: listingsAsync.when(
        data: (all) {
          final asks = all
              .where((l) => l.side == ListingSide.ask)
              .where((l) => _condition == null || l.condition == _condition)
              .toList();
          final sorted = _sorted(asks);
          final shown = sorted.take(_visible).toList();
          final minPrice = asks.isEmpty
              ? null
              : asks.map((l) => l.price).reduce((a, b) => a < b ? a : b);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConditionGradePicker(
                      value: _condition,
                      onChanged: (value) => setState(() {
                        _condition = value;
                        _visible = _pageSize;
                      }),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              text: '${asks.length} Listing',
                              style: AppTypography.bodySmSemibold(
                                colors.onSurface,
                              ),
                              children: [
                                if (minPrice != null) ...[
                                  TextSpan(
                                    text: ' · Mulai ',
                                    style: AppTypography.caption(
                                      context.mutedForeground,
                                    ),
                                  ),
                                  TextSpan(
                                    text: formatRupiah(minPrice),
                                    style: AppTypography.captionSemibold(
                                      colors.onSurface,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (asks.length > 1)
                          PopupMenuButton<_Sort>(
                            initialValue: _sort,
                            position: PopupMenuPosition.under,
                            color: Theme.of(context).cardColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              side: BorderSide(color: context.borderColor),
                            ),
                            onSelected: (value) => setState(() {
                              _sort = value;
                              _visible = _pageSize;
                            }),
                            itemBuilder: (context) => [
                              for (final option in _Sort.values)
                                PopupMenuItem(
                                  value: option,
                                  height: 40,
                                  child: Text(
                                    option.labelId,
                                    style: AppTypography.bodySm(
                                      colors.onSurface,
                                    ),
                                  ),
                                ),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: context.borderColor),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.full,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _sort.labelId,
                                    style: AppTypography.captionSemibold(
                                      context.mutedForeground,
                                    ),
                                  ),
                                  Icon(
                                    Icons.expand_more,
                                    size: 14,
                                    color: context.mutedForeground,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                  child: Text(
                    _condition == null
                        ? 'Belum ada listing untuk kartu ini'
                        : 'Tidak ada listing dengan kondisi ini',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySm(context.mutedForeground),
                  ),
                )
              else ...[
                for (final listing in shown)
                  _ListingRow(key: ValueKey(listing.id), listing: listing),
                if (sorted.length > shown.length)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                    child: TextButton(
                      onPressed: () => setState(() => _visible += _pageSize),
                      child: Text(
                        'Muat lebih banyak (${sorted.length - shown.length})',
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
        loading: () => const _ListingsPlaceholder(),
        error: (_, __) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Gagal memuat listing',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm(context.mutedForeground),
          ),
        ),
      ),
    );
  }
}

class _ListingRow extends ConsumerStatefulWidget {
  const _ListingRow({super.key, required this.listing});

  final ListingModel listing;

  @override
  ConsumerState<_ListingRow> createState() => _ListingRowState();
}

class _ListingRowState extends ConsumerState<_ListingRow> {
  bool get _isMine {
    final me = ref.watch(authProvider).valueOrNull?.id;
    return me != null && me.isNotEmpty && me == widget.listing.sellerId;
  }

  /// The viewer's live offer on this listing, if they already made one.
  ListingOfferModel? get _myOffer =>
      ref.watch(myOfferOnListingProvider(widget.listing.slug)).valueOrNull;

  Future<void> _offer(ListingModel listing) async {
    final submitted = await showMakeOfferSheet(context, listing: listing);
    if (submitted == true && mounted) ref.invalidate(myOffersProvider);
  }

  int _qty = 1;
  bool _adding = false;

  Future<void> _addToCart() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _adding = true);
    try {
      await ref.read(cartProvider.notifier).add(widget.listing.id, _qty);
    } on CartException catch (e) {
      if (!mounted) return;
      setState(() => _adding = false);
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
    setState(() => _adding = false);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Ditambahkan ke keranjang'),
        duration: const Duration(seconds: 2),
        // Without this a SnackBar carrying an action never times out.
        persist: false,
        action: SnackBarAction(
          label: 'Lihat',
          onPressed: () => context.push(Routes.cart),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final colors = context.appColors;
    final soldOut = listing.available <= 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: listing.storeSlug.isEmpty
                    ? null
                    : () => context.push(Routes.storeDetail(listing.storeSlug)),
                child: SellerAvatar(
                  name: listing.storeName,
                  imageUrl: listing.sellerImageUrl,
                  size: 36,
                ),
              ),
              const SizedBox(width: 10),
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
                              colors.onSurface,
                            ),
                          ),
                        ),
                        if (listing.isVerified) ...[
                          const SizedBox(width: 3),
                          Icon(Icons.verified, size: 13, color: colors.primary),
                        ],
                        const SizedBox(width: 6),
                        ConditionBadge(condition: listing.condition),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        ReputationStar(score: listing.sellerFeedbackScore),
                        if (listing.cityName.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.location_on_outlined,
                            size: 12,
                            color: context.mutedForeground,
                          ),
                          const SizedBox(width: 2),
                          Flexible(
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
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatRupiah(listing.price),
                    style: AppTypography.bodySemibold(colors.onSurface),
                  ),
                  Text(
                    '${listing.available} tersedia',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ],
          ),
          if (listing.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: listing.photoUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, i) => InkWell(
                  onTap: () => showImageLightbox(
                    context,
                    imageUrl: listing.photoUrls[i],
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Image.network(
                      listing.photoUrls[i],
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 48,
                        height: 48,
                        color: colors.secondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          // Own listings are excluded from this feed, but a row can survive
          // a sign-in, and `submit_offer` refuses your own listing anyway.
          if (listing.acceptsOffers && !soldOut && !_isMine) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _myOffer != null
                    ? () => context.push(Routes.proposals)
                    : () => _offer(listing),
                icon: Icon(
                  _myOffer != null ? Icons.schedule : Icons.handshake_outlined,
                  size: 16,
                ),
                label: Text(
                  _myOffer != null ? 'Penawaran terkirim' : 'Buat Penawaran',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.appSemantic.success,
                  side: BorderSide(
                    color: context.appSemantic.success.withValues(alpha: 0.5),
                  ),
                  minimumSize: const Size(0, 38),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              QuantitySelector(
                value: _qty,
                min: 1,
                max: listing.available < 1 ? 1 : listing.available,
                onChanged: (v) => setState(() => _qty = v),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _adding || soldOut ? null : _addToCart,
                  icon: _adding
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.shopping_cart_outlined, size: 16),
                  label: Text(
                    soldOut ? 'Habis' : 'Tambah ke Keranjang',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.onSurface,
                    foregroundColor: Theme.of(context).scaffoldBackgroundColor,
                    minimumSize: const Size(0, 38),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ListingsPlaceholder extends StatelessWidget {
  const _ListingsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              height: 56,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: context.appColors.secondary,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
        ],
      ),
    );
  }
}
