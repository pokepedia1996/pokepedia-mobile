import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/card_model.dart';
import '../../../../shared/models/listing_model.dart';
import '../../../../shared/widgets/condition_badge.dart';
import '../../../../shared/widgets/condition_grade_picker.dart';
import '../../../../shared/widgets/image_lightbox.dart';
import '../../../../shared/widgets/quantity_selector.dart';
import '../../../../shared/widgets/seller_rating_badge.dart';
import '../../../../shared/widgets/seller_avatar.dart';
import '../../../cart/repository/cart_repository.dart';
import '../../../cart/usecase/cart_notifier.dart';
import '../../../chat/repository/models/chat_models.dart';
import '../../../chat/usecase/chat_notifier.dart';
import '../../../proposals/presentation/widgets/make_offer_sheet.dart';
import '../../../proposals/repository/models/listing_offer_model.dart';
import '../../../proposals/usecase/proposals_notifier.dart';
import '../../usecase/expansions_notifier.dart';
import '../../../../core/errors/user_message.dart';

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
                    if (!isSealedCardId(widget.cardId)) ...[
                      ConditionGradePicker(
                        value: _condition,
                        onChanged: (value) => setState(() {
                          _condition = value;
                          _visible = _pageSize;
                        }),
                      ),
                      const SizedBox(height: 10),
                    ],
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
                                    LucideIcons.chevronDown,
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.circleAlert,
                size: 28,
                color: context.mutedForeground,
              ),
              const SizedBox(height: 8),
              Text(
                'Gagal memuat listing',
                textAlign: TextAlign.center,
                style: AppTypography.bodySm(context.mutedForeground),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () =>
                    ref.invalidate(cardListingsProvider(widget.cardId)),
                child: const Text('Coba lagi'),
              ),
            ],
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
      messenger.showSnackBar(SnackBar(content: Text(userFacingError(e))));
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

  /// Web's "Chat penjual" button: the listing-scoped room with this seller,
  /// opened the way `StoreCardListingPage._contactSeller` does.
  Future<void> _chat(ListingModel listing) async {
    if (ref.read(authProvider).valueOrNull == null) {
      context.push(Routes.login);
      return;
    }
    if (listing.sellerId.isEmpty) return;
    final arg = await ref
        .read(chatOpenerProvider)
        .withUser(
          otherUserId: listing.sellerId,
          title: listing.storeName,
          listingId: listing.id,
        );
    if (!mounted) return;
    final target = ChatTarget(
      otherUserId: listing.sellerId,
      title: listing.storeName,
      listingId: listing.id,
      listingContext: ChatListingContext(
        listingOrderId: listing.id,
        cardId: listing.card.id,
        priceIdr: listing.price,
        cardName: listing.card.name,
        cardImage: listing.card.imageUrl,
        packSlug: listing.card.packSlug,
        variantKey: listing.variantKey,
        condition: listing.condition.raw,
      ),
    );
    final slug = arg.slug;
    if (slug != null) {
      context.push(
        Routes.chatThread(slug, listingId: listing.id),
        extra: target,
      );
    } else {
      context.push(Routes.chatNew, extra: target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final colors = context.appColors;
    final soldOut = listing.available <= 0;
    final success = context.appSemantic.success;
    // Web's buttons set their label in the heading face (`font-heading`).
    // The button's foreground colour overrides the one this carries.
    final buttonLabel = AppTypography.h3(
      colors.onSurface,
    ).copyWith(fontSize: 14, height: 1.2);
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
              // Web's row (`listings-section.tsx`), but with the rating and
              // the city each on a line of their own and room for a long
              // store name to wrap, so nothing is cut short beside a price.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Text(
                            listing.storeName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySmSemibold(
                              colors.onSurface,
                            ).copyWith(height: 1.3),
                          ),
                        ),
                        if (listing.isVerified) ...[
                          const SizedBox(width: 3),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              LucideIcons.badgeCheck,
                              size: 13,
                              color: colors.primary,
                            ),
                          ),
                        ],
                        if (!listing.card.isSealed) ...[
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: ConditionBadge(
                              condition: listing.condition,
                              colored: true,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    SellerRatingBadge(
                      score: listing.sellerFeedbackScore,
                      rating: listing.sellerRating,
                    ),
                    if (listing.cityName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              LucideIcons.mapPin,
                              size: 12,
                              color: context.mutedForeground,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              listing.cityName,
                              maxLines: 2,
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
              const SizedBox(width: 8),
              // Never cut short: the seller column gives way first, and on a
              // narrow phone a huge price scales down rather than squeezing
              // the seller column below half the row.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.45,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        formatRupiah(listing.price),
                        maxLines: 1,
                        style: AppTypography.bodySemibold(colors.onSurface)
                            .copyWith(
                              fontSize: 18,
                              height: 1.3,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    Text(
                      '${listing.available} tersedia',
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Lined up under the seller's name, past the avatar.
          Padding(
            padding: const EdgeInsets.only(left: 46, top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (!_isMine) ...[
                      _ChatButton(onPressed: () => _chat(listing)),
                      const SizedBox(width: 8),
                    ],
                    QuantitySelector(
                      value: _qty,
                      min: 1,
                      max: listing.available < 1 ? 1 : listing.available,
                      onChanged: (v) => setState(() => _qty = v),
                    ),
                  ],
                ),
                if (listing.photoUrls.isNotEmpty) ...[
                  const SizedBox(height: 10),
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
                        borderRadius: BorderRadius.circular(10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
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
              ],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _adding || soldOut ? null : _addToCart,
            icon: _adding
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).scaffoldBackgroundColor,
                    ),
                  )
                : const Icon(LucideIcons.shoppingCart, size: 14),
            label: Text(soldOut ? 'Habis' : 'Keranjang'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.onSurface,
              foregroundColor: Theme.of(context).scaffoldBackgroundColor,
              minimumSize: const Size.fromHeight(40),
              shape: buttonShape,
              textStyle: buttonLabel,
            ),
          ),
          // Own listings are excluded from this feed, but a row can survive
          // a sign-in, and `submit_offer` refuses your own listing anyway.
          if (listing.acceptsOffers && !soldOut && !_isMine) ...[
            const SizedBox(height: 6),
            ElevatedButton.icon(
              onPressed: _myOffer != null
                  ? () => context.push(Routes.proposals)
                  : () => _offer(listing),
              icon: Icon(
                _myOffer != null ? LucideIcons.clock : LucideIcons.handCoins,
                size: 14,
              ),
              label: Text(_myOffer != null ? 'Penawaran terkirim' : 'Tawar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: success,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(40),
                shape: buttonShape,
                textStyle: buttonLabel,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Web's square "Chat penjual" button beside the stepper: a 36px outlined
/// tile, the same height as the stepper's boxes plus their border.
class _ChatButton extends StatelessWidget {
  const _ChatButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.md);
    return Tooltip(
      message: 'Chat penjual',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: context.borderColor),
            ),
            child: Icon(
              LucideIcons.messageCircle,
              size: 16,
              color: context.appColors.onSurface,
            ),
          ),
        ),
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
