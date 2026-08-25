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
import '../../../shared/widgets/condition_badge.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/image_lightbox.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/quantity_selector.dart';
import '../../../shared/widgets/reputation_star.dart';
import '../../../shared/widgets/seller_avatar.dart';
import '../../../shared/widgets/remote_image.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../cart/repository/cart_repository.dart';
import '../../cart/usecase/cart_notifier.dart';
import '../../expansions/presentation/widgets/card_details_section.dart';
import '../../expansions/usecase/expansions_notifier.dart';
import '../../proposals/presentation/widgets/make_offer_sheet.dart';
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
  bool _wishlistToggling = false;
  int _photoIndex = 0;

  Future<void> _addToCart(ListingModel listing, int quantity) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(cartProvider.notifier).add(listing.id, quantity);
    } on CartException catch (e) {
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
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

  Future<void> _makeOffer(ListingModel listing) async {
    if (!listing.acceptsOffers) {
      _comingSoon('Penjual tidak menerima penawaran untuk listing ini');
      return;
    }
    await showMakeOfferSheet(context, listing: listing);
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

  void _toggleFollow(String storeName) {
    setState(() => _following = !_following);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _following ? 'Mengikuti $storeName' : 'Berhenti mengikuti $storeName',
        ),
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
      appBar: const TransparentAppBar(),
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
          final pack = ref.watch(packDetailProvider(card.packSlug)).valueOrNull;
          final wishlisted = ref.watch(isWishlistedProvider(widget.cardId));

          // The seller's own photos of this copy stand in for the catalog
          // artwork, exactly like `heroPhotos`/`heroImage` on the web.
          final photos = active.photoUrls;
          final photoIndex = _photoIndex < photos.length ? _photoIndex : 0;
          final heroImage = photos.isEmpty
              ? card.imageUrl
              : photos[photoIndex];

          return AppBarOverlayBody(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _PackRow(pack: pack, card: card),
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
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => context.push(
                              Routes.cardDetail(card.packSlug, card.id),
                            ),
                            icon: const Icon(Icons.visibility_outlined, size: 15),
                            label: const Text('Lihat detail kartu'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

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
                  onAddToCart: (qty) => _addToCart(active, qty),
                  onMakeOffer: () => _makeOffer(active),
                  onReport: _reportListing,
                  onToggleFollow: () => _toggleFollow(store.storeName),
                  onContact: () => context.push(Routes.chatThread(store.handle)),
                ),
                const SizedBox(height: 20),

                // The card's own info, below the buy block like the web's
                // `order-4` column.
                _CardHeader(
                  card: card,
                  wishlisted: wishlisted,
                  toggling: _wishlistToggling,
                  onToggleWishlist: () => _toggleWishlist(wishlisted),
                ),
                const SizedBox(height: 12),
                CardDetailsSection(card: card),
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

/// The expansion row above the artwork: pack image + name on the left, set
/// symbol and collector number on the right.
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
    required this.onReport,
    required this.onToggleFollow,
    required this.onContact,
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
  final void Function(int quantity) onAddToCart;
  final VoidCallback onMakeOffer;
  final VoidCallback onReport;
  final VoidCallback onToggleFollow;
  final VoidCallback onContact;

  @override
  State<_PurchasePanel> createState() => _PurchasePanelState();
}

class _PurchasePanelState extends State<_PurchasePanel> {
  int _qty = 1;

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
                          if (widget.otherSellersCount > 0)
                            InkWell(
                              onTap: () => context.push(widget.globalCardHref),
                              child: Text(
                                'Lihat ${widget.otherSellersCount} listing lain →',
                                style: AppTypography.captionSemibold(
                                  colors.primary,
                                ),
                              ),
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
                if (store.onVacation) ...[
                  const SizedBox(height: 12),
                  _VacationNotice(store: store),
                ],
                if (active.acceptsOffers && active.available > 0) ...[
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: widget.onMakeOffer,
                    icon: const Icon(Icons.handshake_outlined, size: 15),
                    label: const Text('Buat Penawaran'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.appSemantic.success,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: active.available <= 0 || vacationHard
                      ? null
                      : () => widget.onAddToCart(_qty),
                  icon: const Icon(Icons.shopping_cart_outlined, size: 15),
                  label: const Text('Tambah ke Keranjang'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.onSurface,
                    foregroundColor: colors.surface,
                  ),
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
  });

  final StoreModel store;
  final ListingModel listing;
  final double? positivePct;
  final int feedbackScore;
  final bool following;
  final VoidCallback onToggleFollow;
  final VoidCallback onContact;

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
            ],
          ),
        ],
      ),
    );
  }
}

/// Card name, wishlist toggle and the identity chips — the top of the web's
/// info column, which sits below the buy block on narrow screens.
class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.card,
    required this.wishlisted,
    required this.toggling,
    required this.onToggleWishlist,
  });

  final CardModel card;
  final bool wishlisted;
  final bool toggling;
  final VoidCallback onToggleWishlist;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(card.name, style: AppTypography.h1(colors.onSurface)),
            ),
            const SizedBox(width: 8),
            _WishlistButton(
              wishlisted: wishlisted,
              toggling: toggling,
              onPressed: onToggleWishlist,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Divider(height: 1, color: context.borderColor),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            CardInfoChip(text: card.language.labelId),
            CardInfoChip(text: card.category.labelId),
            if (card.rarity != null) CardInfoChip(text: card.rarity!),
            CardInfoChip(
              text: '${card.expansionCode.toUpperCase()} · ${card.collectorNumber}',
            ),
          ],
        ),
      ],
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
        : Icon(
            wishlisted ? Icons.favorite : Icons.favorite_border,
            size: 15,
          );
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
