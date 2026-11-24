import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/errors/user_message.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/models/listing_model.dart';
import '../../../shared/models/store_model.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/card_language_badge.dart';
import '../../../shared/widgets/cart_app_bar_button.dart';
import '../../../shared/widgets/condition_badge.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/fly_to_cart.dart';
import '../../../shared/widgets/image_lightbox.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../cart/repository/cart_repository.dart';
import '../../cart/usecase/cart_notifier.dart';
import '../../chat/repository/models/chat_models.dart';
import '../../chat/usecase/chat_notifier.dart';
import '../../proposals/presentation/widgets/make_offer_sheet.dart';
import '../../proposals/usecase/proposals_notifier.dart';
import '../../user/usecase/user_notifier.dart';
import '../repository/models/custom_listing_detail.dart';
import '../usecase/market_notifier.dart';
import 'store_card_listing_page.dart';
import 'widgets/report_listing_sheet.dart';
import 'widgets/store_share_sheet.dart';

/// One custom listing — a seller's own title, photos and description in
/// place of a catalog card, with the cards they tagged on it.
///
/// Mirrors `custom-listing-detail.tsx` on web, in the order its mobile
/// layout stacks: photos, buy block, tagged cards, then the title and the
/// description.
class CustomListingPage extends ConsumerStatefulWidget {
  const CustomListingPage({
    super.key,
    required this.storeSlug,
    required this.listingSlug,
  });

  final String storeSlug;
  final String listingSlug;

  @override
  ConsumerState<CustomListingPage> createState() => _CustomListingPageState();
}

class _CustomListingPageState extends ConsumerState<CustomListingPage> {
  int _photoIndex = 0;
  bool _following = false;
  bool _followSeeded = false;

  /// The two ends of the add-to-cart flight: the photo it leaves and the app
  /// bar cart it lands on.
  final _photoKey = GlobalKey();
  final _cartIconKey = GlobalKey();

  bool _isOwn(ListingModel listing) {
    final me = ref.read(authProvider).valueOrNull?.id;
    return me != null && me.isNotEmpty && me == listing.sellerId;
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), persist: false));
  }

  Future<void> _addToCart(
    ListingModel listing,
    int quantity,
    String? imageUrl,
  ) async {
    try {
      await ref.read(cartProvider.notifier).add(listing.id, quantity);
    } on CartException catch (e) {
      if (mounted) _say(userFacingError(e));
      return;
    }
    if (!mounted) return;

    unawaited(
      flyToCart(
        context: context,
        from: _photoKey,
        to: _cartIconKey,
        child: CardArt(imageUrl: imageUrl, borderRadius: AppRadius.md),
      ),
    );

    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Listing telah ditambahkan ke keranjang'),
        duration: const Duration(seconds: 2),
        persist: false,
        action: SnackBarAction(
          label: 'Lihat',
          onPressed: () => context.push(Routes.cart),
        ),
      ),
    );
  }

  Future<void> _makeOffer(ListingModel listing) async {
    if (_isOwn(listing)) {
      _say('Ini listing kamu sendiri');
      return;
    }
    if (!listing.acceptsOffers) {
      _say('Penjual tidak menerima penawaran untuk listing ini');
      return;
    }
    final submitted = await showMakeOfferSheet(context, listing: listing);
    if (submitted != true || !mounted) return;
    ref.invalidate(myOffersProvider);
  }

  Future<void> _contactSeller(StoreModel store, ListingModel listing) async {
    if (ref.read(authProvider).valueOrNull == null) {
      context.push(Routes.login);
      return;
    }
    final sellerId = store.userId;
    if (sellerId == null) {
      _say('Penjual ini belum bisa dihubungi');
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

    // No card behind a custom listing: the thread pins its title and photo.
    final target = ChatTarget(
      otherUserId: sellerId,
      title: store.storeName,
      listingId: listing.id,
      listingContext: ChatListingContext(
        listingOrderId: listing.id,
        cardId: null,
        priceIdr: listing.price,
        cardName: listing.card.name,
        cardImage: listing.card.imageUrl,
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

  Future<void> _reportListing(ListingModel listing) async {
    if (ref.read(authProvider).valueOrNull == null) {
      context.push(Routes.login);
      return;
    }
    final sent = await showReportListingSheet(
      context,
      listingId: listing.id,
      cardName: listing.card.name,
    );
    if (!sent || !mounted) return;
    _say('Laporan terkirim, terima kasih');
  }

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
    _say(
      error ??
          (next
              ? 'Mengikuti ${store.storeName}'
              : 'Berhenti mengikuti ${store.storeName}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final key = (storeSlug: widget.storeSlug, slug: widget.listingSlug);
    final async = ref.watch(customListingProvider(key));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: TransparentAppBar(
        actions: [CartAppBarButton(iconKey: _cartIconKey)],
      ),
      body: async.when(
        data: (data) {
          if (data == null) {
            return EmptyState(
              icon: LucideIcons.store,
              title: 'Listing tidak lagi tersedia',
              description:
                  'Penjual mungkin sudah menutup listing ini atau menghapusnya.',
              action: OutlinedButton(
                onPressed: () =>
                    context.push(Routes.storeDetail(widget.storeSlug)),
                child: const Text('Lihat toko'),
              ),
            );
          }
          return _content(data);
        },
        loading: () => const PikachuLoader(),
        error: (_, __) => EmptyState(
          icon: LucideIcons.circleAlert,
          title: 'Gagal memuat listing',
          action: OutlinedButton(
            onPressed: () => ref.invalidate(customListingProvider(key)),
            child: const Text('Coba lagi'),
          ),
        ),
      ),
    );
  }

  Widget _content(CustomListingData data) {
    final detail = data.detail;
    final listing = data.listing;
    final store = data.store;
    final own = _isOwn(listing);

    final sellerId = store.userId;
    if (!_followSeeded && sellerId != null) {
      final known = ref.watch(isFollowingShopProvider(sellerId)).valueOrNull;
      if (known != null) {
        _followSeeded = true;
        _following = known;
      }
    }

    final photos = detail.photoUrls;
    final photoIndex = _photoIndex < photos.length ? _photoIndex : 0;
    final heroImage = photos.isEmpty ? null : photos[photoIndex];

    return AppBarOverlayBody(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const SizedBox(height: 16),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: _Gallery(
                photos: photos,
                activeIndex: photoIndex,
                heroKey: _photoKey,
                onSelect: (i) => setState(() => _photoIndex = i),
                onOpen: () => showImageLightbox(context, imageUrl: heroImage),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (!detail.isLive) ...[
            _NotLiveNotice(status: detail.status),
            const SizedBox(height: 14),
          ],
          PurchasePanel(
            cheapestByCondition: const {},
            active: listing,
            store: store,
            otherSellersCount: 0,
            globalCardHref: '',
            positivePct: store.positivePct,
            feedbackScore: store.feedbackScore ?? 0,
            following: _following,
            onSelectCondition: (_) {},
            onAddToCart: (qty) => _addToCart(listing, qty, heroImage),
            onMakeOffer: () => _makeOffer(listing),
            isOwnListing: own,
            myOffer: ref
                .watch(myOfferOnListingProvider(listing.slug))
                .valueOrNull,
            onReport: () => _reportListing(listing),
            onToggleFollow: () => _toggleFollow(store),
            onContact: () => _contactSeller(store, listing),
            onShare: () => showStoreShareSheet(context, store: store),
          ),
          if (detail.tags.isNotEmpty) ...[
            const SizedBox(height: 20),
            _TaggedCards(tags: detail.tags),
          ],
          const SizedBox(height: 20),
          Divider(height: 1, color: context.borderColor),
          const SizedBox(height: 16),
          _Info(detail: detail),
        ],
      ),
    );
  }
}

/// The seller's photos: the one on show at the 4:5 the app crops them to,
/// and a strip to switch between them.
class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.photos,
    required this.activeIndex,
    required this.heroKey,
    required this.onSelect,
    required this.onOpen,
  });

  final List<String> photos;
  final int activeIndex;
  final GlobalKey heroKey;
  final ValueChanged<int> onSelect;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: photos.isEmpty ? null : onOpen,
          child: Container(
            key: heroKey,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: context.borderColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: CardArt(
              imageUrl: photos.isEmpty ? null : photos[activeIndex],
              aspectRatio: 4 / 5,
              borderRadius: AppRadius.lg,
            ),
          ),
        ),
        if (photos.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < photos.length; i++)
                InkWell(
                  onTap: () => onSelect(i),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: colors.secondary,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: i == activeIndex
                            ? colors.primary
                            : context.borderColor,
                        width: i == activeIndex ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CardArt(
                      imageUrl: photos[i],
                      aspectRatio: 1,
                      borderRadius: AppRadius.md,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Shown to the owner of a listing that is not for sale right now.
class _NotLiveNotice extends StatelessWidget {
  const _NotLiveNotice({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Text(
        status == 'draft'
            ? 'Draft: listing ini belum tayang di market.'
            : 'Listing ini sedang tidak aktif dan tidak tampil di market.',
        style: AppTypography.caption(context.mutedForeground),
      ),
    );
  }
}

/// "Kartu di listing ini": the catalog cards the seller tagged, each opening
/// its catalog page.
class _TaggedCards extends StatelessWidget {
  const _TaggedCards({required this.tags});

  final List<CustomTaggedCard> tags;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kartu di listing ini',
            style: AppTypography.h3(colors.onSurface),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < tags.length; i++) ...[
            if (i > 0) Divider(height: 1, color: context.borderColor),
            _TaggedCardRow(tag: tags[i]),
          ],
        ],
      ),
    );
  }
}

class _TaggedCardRow extends StatelessWidget {
  const _TaggedCardRow({required this.tag});

  final CustomTaggedCard tag;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final packSlug = tag.packSlug;
    return InkWell(
      onTap: packSlug == null
          ? null
          : () => context.push(Routes.cardDetail(packSlug, tag.cardId)),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: CardArt(
                imageUrl: tag.imageUrl,
                borderRadius: AppRadius.sm,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tag.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      CardLanguageBadge(language: tag.language),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          [
                            if (tag.expansionCode.isNotEmpty)
                              tag.expansionCode.toUpperCase(),
                            if (tag.collectorNumber.isNotEmpty)
                              tag.collectorNumber,
                            '×${tag.quantity}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ConditionBadge(condition: tag.condition, dense: true),
          ],
        ),
      ),
    );
  }
}

/// The title, the Custom marker and the description.
class _Info extends StatelessWidget {
  const _Info({required this.detail});

  final CustomListingDetail detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(detail.title, style: AppTypography.h2(colors.onSurface)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: colors.secondary,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text('Custom', style: AppTypography.caption(colors.onSurface)),
        ),
        if (detail.hasDescription) ...[
          const SizedBox(height: 16),
          Text(
            'Deskripsi',
            style: AppTypography.bodySmSemibold(colors.onSurface),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.secondary,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: context.borderColor),
            ),
            child: Text(
              detail.description!,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
          ),
        ],
      ],
    );
  }
}
