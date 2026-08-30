import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/card_ownership_controller.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/card_condition.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/listing_model.dart';
import '../../../shared/models/pack_model.dart';
import '../../../shared/models/store_model.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/cart_app_bar_button.dart';
import '../../../shared/widgets/condition_badge.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/fly_to_cart.dart';
import '../../../shared/widgets/image_lightbox.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/quantity_selector.dart';
import '../../../shared/widgets/reputation_star.dart';
import '../../../shared/widgets/seller_avatar.dart';
import '../../../shared/widgets/remote_image.dart';
import '../../expansions/presentation/widgets/market_activity_section.dart';
import 'widgets/more_from_seller_section.dart';
import 'widgets/store_share_sheet.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../cart/repository/cart_repository.dart';
import '../../chat/repository/models/chat_models.dart';
import '../../chat/usecase/chat_notifier.dart';
import '../../user/usecase/user_notifier.dart';
import '../../cart/usecase/cart_notifier.dart';
import '../../expansions/presentation/widgets/card_details_section.dart';
import '../../proposals/presentation/widgets/make_offer_sheet.dart';
import '../../proposals/repository/models/listing_offer_model.dart';
import '../../proposals/usecase/proposals_notifier.dart';
import '../../portfolio/usecase/portfolio_notifier.dart';
import '../usecase/market_notifier.dart';

const _monthNamesIdFull = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

String _formatDateId(DateTime date) =>
    '${date.day} ${_monthNamesIdFull[date.month - 1]}';

/// Ports `app/market/[slug]/card/[cardId]/page.tsx` — `PerSellerCardDetail`
/// + `StoreCardDetailView` + `StorePurchasePanel` — a single seller's
/// "product page" for one card, opened when a WTS (ask) listing is tapped
/// (WTB listings just open the regular card page instead, since a
/// wanted-ad has no single seller or condition to show).
///
/// Section order follows `StoreCardDetailView`'s mobile ordering (the
/// `order-*` classes that stack its two desktop columns): breadcrumb, the
/// pack/number row, the artwork column (photos, then "Lihat detail kartu"),
/// the buy block, and finally the card's own info. `MarketActivity`, which
/// the web slots between the buy block and the info, has no mobile port yet.
class StoreCardListingPage extends ConsumerStatefulWidget {
  const StoreCardListingPage({
    super.key,
    required this.storeSlug,
    required this.cardId,
  });

  final String storeSlug;
  final int cardId;

  @override
  ConsumerState<StoreCardListingPage> createState() =>
      _StoreCardListingPageState();
}

class _StoreCardListingPageState extends ConsumerState<StoreCardListingPage> {
  CardCondition? _selectedCondition;
  bool _following = false;
  bool _followSeeded = false;
  bool _wishlistToggling = false;
  int _photoIndex = 0;

  /// The two ends of the add-to-cart flight: the artwork it leaves and the
  /// app bar cart it lands on.
  final _artworkKey = GlobalKey();
  final _cartIconKey = GlobalKey();

  Future<void> _addToCart(
    ListingModel listing,
    int quantity,
    String? imageUrl,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(cartProvider.notifier).add(listing.id, quantity);
    } on CartException catch (e) {
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;

    // Says where the card went, before the snack bar says it in words. Not
    // awaited: the confirmation shouldn't wait on the animation.
    unawaited(
      flyToCart(
        context: context,
        from: _artworkKey,
        to: _cartIconKey,
        child: CardArt(imageUrl: imageUrl, borderRadius: AppRadius.md),
      ),
    );

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Kartu telah ditambahkan ke keranjang'),
        duration: const Duration(seconds: 2),
        // A SnackBar with an action defaults to `persist: true`, which
        // ignores `duration` and waits for a tap — opt back into timing out.
        persist: false,
        action: SnackBarAction(
          label: 'Lihat',
          onPressed: () => context.push(Routes.cart),
        ),
      ),
    );
  }

  /// Whether the viewer is the one selling this.
  ///
  /// Compared against `listings.user_id` rather than the store handle: a
  /// seller can browse their own shop from a second account, and it is the
  /// row's owner the RPCs check.
  bool _isOwnListing(ListingModel listing) {
    final me = ref.read(authProvider).valueOrNull?.id;
    return me != null && me.isNotEmpty && me == listing.sellerId;
  }

  Future<void> _makeOffer(ListingModel listing) async {
    if (_isOwnListing(listing)) {
      // `submit_offer` answers `cannot_offer_on_own_listing`; better to say
      // so here than to spend a round trip finding out.
      _comingSoon('Ini listing kamu sendiri');
      return;
    }
    if (!listing.acceptsOffers) {
      _comingSoon('Penjual tidak menerima penawaran untuk listing ini');
      return;
    }

    final submitted = await showMakeOfferSheet(context, listing: listing);
    if (submitted != true || !mounted) return;
    // The button's own state depends on this: with an offer running it
    // becomes the way back to it rather than a second attempt.
    ref.invalidate(myOffersProvider);
  }

  /// Opens the conversation with this seller, reusing the existing room when
  /// there is one. A room with nobody in it yet isn't created here — the
  /// first message does that, via `ensure_direct_room`.
  Future<void> _contactSeller(StoreModel store, ListingModel listing) async {
    if (ref.read(authProvider).valueOrNull == null) {
      context.push(Routes.login);
      return;
    }
    final sellerId = store.userId;
    if (sellerId == null) {
      _comingSoon('Penjual ini belum bisa dihubungi');
      return;
    }

    final arg = await ref
        .read(chatOpenerProvider)
        .withUser(
          otherUserId: sellerId,
          title: store.storeName,
          listingId: listing.id,
        );
    if (!mounted) return;

    final slug = arg.slug;
    if (slug != null) {
      context.push(Routes.chatThread(slug));
    } else {
      context.push(
        Routes.chatNew,
        extra: ChatTarget(
          otherUserId: sellerId,
          title: store.storeName,
          listingId: listing.id,
        ),
      );
    }
  }

  void _reportListing() => _comingSoon('Fitur laporan segera hadir');

  void _comingSoon(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleWishlist(bool wishlisted) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) {
      context.push(Routes.login);
      return;
    }
    setState(() => _wishlistToggling = true);
    final error = await ref
        .read(cardOwnershipControllerProvider)
        .setWishlisted(widget.cardId, !wishlisted);
    if (!mounted) return;
    setState(() => _wishlistToggling = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  /// Same write as the storefront's own button — `follow_shop` /
  /// `unfollow_shop` — flipped optimistically and put back if it fails.
  Future<void> _toggleFollow(StoreModel store) async {
    if (ref.read(authProvider).valueOrNull == null) {
      context.push(Routes.login);
      return;
    }
    final shopUserId = store.userId;
    if (shopUserId == null) return;

    final next = !_following;
    setState(() => _following = next);

    final error = await ref
        .read(followControllerProvider)
        .setFollowing(shopUserId: shopUserId, following: next);
    if (!mounted) return;
    if (error != null) setState(() => _following = !next);

    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error ??
              (next
                  ? 'Mengikuti ${store.storeName}'
                  : 'Berhenti mengikuti ${store.storeName}'),
        ),
        persist: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(
      storeCardListingsProvider((
        storeSlug: widget.storeSlug,
        cardId: widget.cardId,
      )),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: TransparentAppBar(
        actions: [CartAppBarButton(iconKey: _cartIconKey)],
      ),
      body: async.when(
        data: (data) {
          if (data == null || data.listings.isEmpty) {
            return EmptyState(
              icon: Icons.storefront_outlined,
              title: 'Listing tidak lagi tersedia',
              description:
                  'Penjual ini mungkin sudah kehabisan atau menghentikan listing kartu ini.',
              action: OutlinedButton(
                onPressed: () =>
                    context.push(Routes.storeDetail(widget.storeSlug)),
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
          final activeCondition =
              _selectedCondition ?? data.listings.first.condition;
          final active =
              cheapestByCondition[activeCondition] ?? data.listings.first;
          final card = active.card;
          final store = data.store;
          final wishlisted = ref.watch(isWishlistedProvider(widget.cardId));

          // Seeded once from the server; after that this page owns the flag
          // so the button doesn't snap back while the write is in flight.
          final sellerId = store.userId;
          if (!_followSeeded && sellerId != null) {
            final known = ref
                .watch(isFollowingShopProvider(sellerId))
                .valueOrNull;
            if (known != null) {
              _followSeeded = true;
              _following = known;
            }
          }

          // The seller's own photos of this copy stand in for the catalog
          // artwork, exactly like `heroPhotos`/`heroImage` on the web.
          final photos = active.photoUrls;
          final photoIndex = _photoIndex < photos.length ? _photoIndex : 0;
          final heroImage = photos.isEmpty ? card.imageUrl : photos[photoIndex];

          return AppBarOverlayBody(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                // "Nama toko > Nama kartu — nomor", as sketched. Plain text
                // rather than the breadcrumb that used to sit here: the app
                // bar already carries the way back, so this is context, not
                // navigation.
                _TitleLine(store: store, card: card),
                // const SizedBox(height: 10),
                // _PackRow(pack: pack, card: card),
                const SizedBox(height: 16),

                // Artwork column — photos, then the link back to the
                // catalog page for this card.
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () => showImageLightbox(
                            context,
                            imageUrl: heroImage,
                            heroTag: 'card-image-${card.id}',
                          ),
                          child: Hero(
                            tag: 'card-image-${card.id}',
                            child: Container(
                              key: _artworkKey,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.lg,
                                ),
                                border: Border.all(color: context.borderColor),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: CardArt(
                                imageUrl: heroImage,
                                borderRadius: AppRadius.lg,
                              ),
                            ),
                          ),
                        ),
                        if (photos.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (var i = 0; i < photos.length; i++)
                                  _PhotoThumb(
                                    url: photos[i],
                                    active: i == photoIndex,
                                    onTap: () =>
                                        setState(() => _photoIndex = i),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // "Nama kartu — Nomor — Ekspansi", the heading the sketch
                // puts directly under the image and above the price.
                CardTitleLine(card: card),
                const SizedBox(height: 14),

                // Buy block.
                _PurchasePanel(
                  cheapestByCondition: cheapestByCondition,
                  active: active,
                  store: store,
                  otherSellersCount: data.otherSellersCount,
                  globalCardHref: Routes.cardDetail(card.packSlug, card.id),
                  positivePct: data.positivePct,
                  feedbackScore: data.feedbackScore,
                  following: _following,
                  onSelectCondition: (c) => setState(() {
                    _selectedCondition = c;
                    _photoIndex = 0;
                  }),
                  onAddToCart: (qty) => _addToCart(active, qty, heroImage),
                  onMakeOffer: () => _makeOffer(active),
                  isOwnListing: _isOwnListing(active),
                  myOffer: ref
                      .watch(myOfferOnListingProvider(active.slug))
                      .valueOrNull,
                  onReport: _reportListing,
                  onToggleFollow: () => _toggleFollow(store),
                  onContact: () => _contactSeller(store, active),
                  onShare: () => showStoreShareSheet(context, store: store),
                ),
                const SizedBox(height: 20),

                // "Histori Transaksi" then the price chart — web's
                // `order-3`, directly under the buy block, and the same two
                // widgets the catalog (WTB) card page stacks in the same
                // order. The market data is per card, not per listing, so a
                // buyer comparing this seller's price against the market
                // sees exactly what the WTB page shows.
                SalesHistorySection(cardId: card.id),
                const SizedBox(height: 16),
                MarketActivitySection(cardId: card.id),

                const SizedBox(height: 20),
                Divider(height: 1, color: context.borderColor),
                const SizedBox(height: 16),
                // The card's own info last, like web's `order-4` column —
                // the market history is what a buyer weighs the price
                // against, so it comes first.
                CardDetailsHeader(
                  card: card,
                  trailing: _WishlistButton(
                    wishlisted: wishlisted,
                    toggling: _wishlistToggling,
                    onPressed: () => _toggleWishlist(wishlisted),
                  ),
                ),
                const SizedBox(height: 12),
                CardDetailsSection(card: card),

                MoreFromSellerSection(
                  storeHandle: store.handle,
                  excludeCardId: card.id,
                ),
              ],
            ),
          );
        },
        loading: () => const PikachuLoader(),
        error: (_, __) => const EmptyState(
          icon: Icons.error_outline,
          title: 'Gagal memuat listing',
        ),
      ),
    );
  }
}

/// The store-and-card line above the artwork.
class _TitleLine extends ConsumerWidget {
  const _TitleLine({required this.store, required this.card});

  final StoreModel store;
  final CardModel card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The same "Nama - Nomor - Ekspansi (KODE)" the card pages use, behind
    // the store this copy belongs to.
    return Text(
      '${store.storeName} › ${card.name} - ${card.collectorNumber} - '
      '${expansionLabelOf(ref, card)}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.caption(context.mutedForeground),
    );
  }
}

class _PackRow extends StatelessWidget {
  const _PackRow({required this.pack, required this.card});

  final PackModel? pack;
  final CardModel card;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => context.push(Routes.packDetail(card.packSlug)),
            child: Row(
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: pack?.image != null
                      ? Image.network(
                          pack!.image!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              _PackFallback(pack: pack),
                        )
                      : _PackFallback(pack: pack),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    pack?.name ?? card.expansionCode.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm(colors.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (pack?.setSymbolUrl != null)
          RemoteImage(url: pack!.setSymbolUrl!, height: 24)
        else if (pack != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: context.borderColor),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              pack!.mark,
              style: AppTypography.caption(context.mutedForeground),
            ),
          ),
        const SizedBox(width: 6),
        Text(
          card.collectorNumber,
          style: AppTypography.caption(context.mutedForeground),
        ),
      ],
    );
  }
}

class _PackFallback extends StatelessWidget {
  const _PackFallback({required this.pack});

  final PackModel? pack;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.appColors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      alignment: Alignment.center,
      child: Text(
        pack?.name.characters.firstOrNull ?? '?',
        style: AppTypography.bodySmSemibold(context.mutedForeground),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({
    required this.url,
    required this.active,
    required this.onTap,
  });

  final String url;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: colors.secondary,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: active ? colors.primary : context.borderColor,
            width: active ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Ports `store-purchase-panel.tsx` — one bordered card holding the
/// condition picker, the price/quantity row, the buy actions, the seller
/// strip and the report row, each separated by a hairline.
class _PurchasePanel extends StatefulWidget {
  const _PurchasePanel({
    required this.cheapestByCondition,
    required this.active,
    required this.store,
    required this.otherSellersCount,
    required this.globalCardHref,
    required this.positivePct,
    required this.feedbackScore,
    required this.following,
    required this.onSelectCondition,
    required this.onAddToCart,
    required this.onMakeOffer,
    required this.isOwnListing,
    required this.myOffer,
    required this.onReport,
    required this.onToggleFollow,
    required this.onContact,
    required this.onShare,
  });

  final Map<CardCondition, ListingModel> cheapestByCondition;
  final ListingModel active;
  final StoreModel store;
  final int otherSellersCount;
  final String globalCardHref;
  final double? positivePct;
  final int feedbackScore;
  final bool following;
  final void Function(CardCondition) onSelectCondition;
  final Future<void> Function(int quantity) onAddToCart;
  final VoidCallback onMakeOffer;

  /// Whether the viewer is the seller. `submit_offer` and the cart both
  /// refuse your own listing, so the panel offers the one thing that works.
  final bool isOwnListing;

  /// The viewer's offer already running on this listing, if any.
  final ListingOfferModel? myOffer;
  final VoidCallback onReport;
  final VoidCallback onToggleFollow;
  final VoidCallback onContact;
  final VoidCallback onShare;

  @override
  State<_PurchasePanel> createState() => _PurchasePanelState();
}

class _PurchasePanelState extends State<_PurchasePanel> {
  int _qty = 1;
  bool _adding = false;

  /// The offer half of the action row, or null when there is nothing to
  /// offer on.
  ///
  /// Three outcomes, and only one of them is a button that submits:
  ///  * your own listing has nothing to negotiate — web swaps in a link to
  ///    manage it, and so does this;
  ///  * an offer already running means `submit_offer` would refuse a second
  ///    (`offer_already_pending`), so the button leads to the one you have;
  ///  * otherwise, Tawar.
  Widget? get _offerSlot {
    final listing = widget.active;

    if (widget.isOwnListing) {
      return OutlinedButton.icon(
        onPressed: () => context.push(Routes.sellerProducts),
        icon: const Icon(Icons.edit_outlined, size: 15),
        label: const Text(
          'Kelola listing',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
      );
    }

    final mine = widget.myOffer;
    if (mine != null) {
      return OutlinedButton.icon(
        onPressed: () => context.push(Routes.proposals),
        icon: const Icon(Icons.schedule, size: 15),
        label: Text(
          mine.status == OfferStatus.accepted
              ? 'Penawaran diterima'
              : 'Penawaran ${formatRupiah(mine.currentPrice)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
      );
    }

    if (!listing.acceptsOffers || listing.available <= 0) return null;

    return ElevatedButton.icon(
      onPressed: widget.onMakeOffer,
      icon: const Icon(Icons.handshake_outlined, size: 15),
      label: const Text('Tawar', maxLines: 1, overflow: TextOverflow.ellipsis),
      style: ElevatedButton.styleFrom(
        backgroundColor: context.appSemantic.success,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(44),
      ),
    );
  }

  /// Holds the button until the row is really in the cart — a second tap
  /// while the first is in flight would add the quantity twice.
  Future<void> _add() async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      await widget.onAddToCart(_qty);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  int get _maxQty => widget.active.available.clamp(0, 99);

  @override
  void didUpdateWidget(covariant _PurchasePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active.id != widget.active.id) {
      _qty = _qty.clamp(1, _maxQty == 0 ? 1 : _maxQty);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final store = widget.store;
    final colors = context.appColors;
    final vacationHard = store.vacationMode == 'hard';

    // Grades grouped by company, in `CONDITION_COMPANIES` order.
    final byCompany = <String, List<CardCondition>>{};
    for (final condition in widget.cheapestByCondition.keys) {
      byCompany.putIfAbsent(condition.companyLabel, () => []).add(condition);
    }
    for (final grades in byCompany.values) {
      grades.sort(
        (a, b) => CardCondition.values
            .indexOf(a)
            .compareTo(CardCondition.values.indexOf(b)),
      );
    }

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
          if (widget.cheapestByCondition.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  for (final company in conditionCompanies)
                    if (byCompany[company] != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            company,
                            style: AppTypography.captionSemibold(
                              context.mutedForeground,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final condition in byCompany[company]!)
                                _ConditionPill(
                                  condition: condition,
                                  active: condition == active.condition,
                                  onTap: () =>
                                      widget.onSelectCondition(condition),
                                ),
                            ],
                          ),
                        ],
                      ),
                ],
              ),
            ),

          // Price, quantity and the buy actions.
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ConditionBadge(condition: active.condition),
                              const SizedBox(width: 8),
                              Text(
                                '${active.available} tersedia',
                                style: AppTypography.caption(
                                  context.mutedForeground,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatRupiah(active.price),
                            style: AppTypography.h2(colors.onSurface),
                          ),
                        ],
                      ),
                    ),
                    if (active.available > 0)
                      QuantitySelector(
                        value: _qty,
                        min: 1,
                        max: _maxQty,
                        onChanged: (v) => setState(() => _qty = v),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _OtherListingsCta(
                  count: widget.otherSellersCount,
                  href: widget.globalCardHref,
                ),
                if (store.onVacation) ...[
                  const SizedBox(height: 12),
                  _VacationNotice(store: store),
                ],
                const SizedBox(height: 12),
                // Offer and cart share a row. Both are fixed-height and
                // single-line so the pair stays level whichever label is
                // showing; "Tawar" rather than web's "Buat Penawaran"
                // because half a phone's width can't hold the long form
                // without ellipsing it.
                Row(
                  spacing: 10,
                  children: [
                    if (_offerSlot != null) Expanded(child: _offerSlot!),
                    // `add_to_cart` refuses your own listing, so on it the
                    // manage link stands alone rather than beside a button
                    // that always fails.
                    if (!widget.isOwnListing)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed:
                              active.available <= 0 || vacationHard || _adding
                              ? null
                              : _add,
                          icon: _adding
                              ? SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.surface,
                                  ),
                                )
                              : const Icon(
                                  Icons.shopping_cart_outlined,
                                  size: 15,
                                ),
                          label: Text(
                            _adding ? 'Menambahkan...' : 'Keranjang',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.onSurface,
                            foregroundColor: colors.surface,
                            minimumSize: const Size.fromHeight(44),
                            // A button disabled because it is *working* keeps
                            // its fill, just dimmed — the default disabled grey
                            // would read as "unavailable" and hide the white
                            // spinner.
                            disabledBackgroundColor: _adding
                                ? colors.onSurface.withValues(alpha: 0.75)
                                : null,
                            disabledForegroundColor: _adding
                                ? colors.surface
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          Divider(height: 1, color: context.borderColor),
          _SellerStrip(
            store: store,
            listing: active,
            positivePct: widget.positivePct,
            feedbackScore: widget.feedbackScore,
            following: widget.following,
            onToggleFollow: widget.onToggleFollow,
            onContact: widget.onContact,
            onShare: widget.onShare,
          ),
          Divider(height: 1, color: context.borderColor),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: widget.onReport,
              icon: const Icon(Icons.flag_outlined, size: 15),
              label: const Text('Laporkan'),
              style: TextButton.styleFrom(
                foregroundColor: context.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The seller's vacation notice, in the slot `store-purchase-panel.tsx`
/// keeps for it between the price row and the buy buttons.
/// "Lihat listing lain" — the way off this seller's page to every seller's
/// price for the same card, under the price it is meant to be compared with.
class _OtherListingsCta extends StatelessWidget {
  const _OtherListingsCta({required this.count, required this.href});

  /// How many listings for this card belong to *other* sellers.
  final int count;
  final String href;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return InkWell(
      onTap: () => context.push(href),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),

        child: Row(
          children: [
            Icon(Icons.storefront_outlined, size: 16, color: colors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                // When nobody else lists the card the page is still worth
                // the trip — it carries the order book and the WTB side —
                // but naming a count of zero listings would be a promise of
                // nothing.
                count > 0
                    ? 'Lihat $count listing lain'
                    : 'Lihat semua listing kartu ini',
                style: AppTypography.bodySmSemibold(colors.primary),
              ),
            ),
            Icon(Icons.arrow_forward, size: 15, color: colors.primary),
          ],
        ),
      ),
    );
  }
}

class _VacationNotice extends StatelessWidget {
  const _VacationNotice({required this.store});

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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Text(text, style: AppTypography.caption(Colors.amber.shade900)),
    );
  }
}

class _ConditionPill extends StatelessWidget {
  const _ConditionPill({
    required this.condition,
    required this.active,
    required this.onTap,
  });

  final CardCondition condition;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? colors.primary : Colors.transparent,
          border: Border.all(
            color: active ? colors.primary : context.borderColor,
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Text(
          condition.gradeLabel,
          style: AppTypography.captionSemibold(
            active ? colors.onPrimary : context.mutedForeground,
          ),
        ),
      ),
    );
  }
}

/// The seller strip inside the purchase panel — avatar, name + reputation,
/// feedback line and city, then the follow/contact buttons.
class _SellerStrip extends StatelessWidget {
  const _SellerStrip({
    required this.store,
    required this.listing,
    required this.positivePct,
    required this.feedbackScore,
    required this.following,
    required this.onToggleFollow,
    required this.onContact,
    required this.onShare,
  });

  final StoreModel store;
  final ListingModel listing;
  final double? positivePct;
  final int feedbackScore;
  final bool following;
  final VoidCallback onToggleFollow;
  final VoidCallback onContact;

  /// Opens the store share sheet — the poster the seller hands out.
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => context.push(Routes.storeDetail(store.handle)),
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
                                colors.primary,
                              ),
                            ),
                          ),
                          if (listing.isVerified) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.verified,
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
                            ? 'Penjual baru · Lihat barang lain'
                            : '${positivePct!.toStringAsFixed(positivePct! % 1 == 0 ? 0 : 1)}% positif'
                                  ' · Lihat barang lain',
                        style: AppTypography.caption(context.mutedForeground),
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
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onContact,
                  icon: const Icon(Icons.chat_bubble_outline, size: 15),
                  label: const Text('Hubungi'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: following
                    ? ElevatedButton.icon(
                        onPressed: onToggleFollow,
                        icon: const Icon(Icons.check, size: 15),
                        label: const Text('Mengikuti'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: onToggleFollow,
                        icon: const Icon(Icons.person_add_alt, size: 15),
                        label: const Text('Ikuti'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.ios_share, size: 15),
                  label: const Text('Bagikan'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
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

class _WishlistButton extends StatelessWidget {
  const _WishlistButton({
    required this.wishlisted,
    required this.toggling,
    required this.onPressed,
  });

  final bool wishlisted;
  final bool toggling;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = toggling
        ? const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(wishlisted ? Icons.favorite : Icons.favorite_border, size: 15);
    final label = Text(wishlisted ? 'Tersimpan' : 'Wishlist');
    return wishlisted
        ? ElevatedButton.icon(
            onPressed: toggling ? null : onPressed,
            icon: icon,
            label: label,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          )
        : OutlinedButton.icon(
            onPressed: toggling ? null : onPressed,
            icon: icon,
            label: label,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          );
  }
}
