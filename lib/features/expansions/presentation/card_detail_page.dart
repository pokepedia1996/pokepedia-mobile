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
import '../../../shared/models/card_model.dart';
import '../../../shared/models/listing_model.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/image_lightbox.dart';
import '../../../shared/widgets/listing_card.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/quantity_selector.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../portfolio/usecase/portfolio_notifier.dart';
import '../usecase/expansions_notifier.dart';
import 'widgets/card_details_section.dart';

/// Ports `app/expansions/[packSlug]/[cardId]/card-detail-page.tsx` +
/// `components/card/card-detail.tsx` (buyer-relevant sections: artwork,
/// Pokemon/Trainer/Energy details from `cards.details`, and the
/// listing/offer tabs). Layout mirrors a standalone card-image header
/// (tap to open the lightbox), then the market section (price/listings),
/// then the full Pokemon info panel at the very end.
class CardDetailPage extends ConsumerStatefulWidget {
  const CardDetailPage({
    super.key,
    required this.packSlug,
    required this.cardId,
  });

  final String packSlug;
  final int cardId;

  @override
  ConsumerState<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends ConsumerState<CardDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _wishlistToggling = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final cardAsync = ref.watch(cardDetailProvider(widget.cardId));
    final listingsAsync = ref.watch(cardListingsProvider(widget.cardId));
    final wishlisted = ref.watch(isWishlistedProvider(widget.cardId));
    final colors = context.appColors;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: TransparentAppBar(
        actions: [
          IconButton(
            icon: _wishlistToggling
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    wishlisted ? Icons.favorite : Icons.favorite_border,
                    color: wishlisted ? colors.primary : null,
                  ),
            onPressed: _wishlistToggling
                ? null
                : () => _toggleWishlist(wishlisted),
          ),
        ],
      ),
      body: cardAsync.when(
        data: (card) {
          if (card == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'Kartu tidak ditemukan',
            );
          }
          return AppBarOverlayBody(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              children: [
                // Artwork, standalone up top — tap to open the lightbox.
                Center(
                  child: GestureDetector(
                    onTap: () => showImageLightbox(
                      context,
                      imageUrl: card.imageUrl,
                      heroTag: 'card-image-${card.id}',
                    ),
                    child: Hero(
                      tag: 'card-image-${card.id}',
                      child: SizedBox(
                        width: 220,
                        child: CardArt(
                          imageUrl: card.imageUrl,
                          borderRadius: AppRadius.lg,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Identity + price header.
                Text(card.name, style: AppTypography.h2(colors.onSurface)),
                const SizedBox(height: 4),
                Text(
                  '${card.collectorNumber} · ${card.expansionCode}',
                  style: AppTypography.bodySm(context.mutedForeground),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (card.rarity != null) CardInfoChip(text: card.rarity!),
                    CardInfoChip(text: card.category.labelId),
                    if (card.regulationMark != null)
                      CardInfoChip(text: 'Reg. ${card.regulationMark}'),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Harga pasar',
                  style: AppTypography.caption(context.mutedForeground),
                ),
                Text(
                  card.marketPrice != null
                      ? formatRupiah(card.marketPrice!)
                      : 'Rp-',
                  style: AppTypography.h3(colors.onSurface),
                ),
                _AddToCollectionSection(cardId: card.id),
                const SizedBox(height: 20),

                // Market section — WTS/WTB listings for this card.
                TabBar(
                  controller: _tabController,
                  labelColor: colors.primary,
                  unselectedLabelColor: context.mutedForeground,
                  indicatorColor: colors.primary,
                  dividerColor: context.borderColor,
                  tabs: const [
                    Tab(text: 'Listing (WTS)'),
                    Tab(text: 'Penawaran (WTB)'),
                  ],
                ),
                const SizedBox(height: 12),
                listingsAsync.when(
                  data: (listings) {
                    final asks = listings
                        .where((l) => l.side == ListingSide.ask)
                        .toList();
                    final bids = listings
                        .where((l) => l.side == ListingSide.bid)
                        .toList();
                    return AnimatedBuilder(
                      animation: _tabController,
                      builder: (context, _) {
                        final list = _tabController.index == 0 ? asks : bids;
                        if (list.isEmpty) {
                          return const EmptyState(
                            icon: Icons.inbox_outlined,
                            title: 'Belum ada listing',
                            description:
                                'Jadilah yang pertama menjual atau menawar kartu ini.',
                          );
                        }
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: list.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.42,
                              ),
                          itemBuilder: (context, i) =>
                              ListingCard(listing: list[i]),
                        );
                      },
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: PikachuLoader(),
                  ),
                  error: (_, __) => const Text('Gagal memuat listing'),
                ),
                const SizedBox(height: 20),

                // Pokemon/Trainer/Energy info, at the very end.
                CardDetailsSection(card: card),
              ],
            ),
          );
        },
        loading: () => const PikachuLoader(),
        error: (_, __) => const EmptyState(
          icon: Icons.error_outline,
          title: 'Gagal memuat kartu',
        ),
      ),
    );
  }
}

/// Ports the `QuantitySelector` + "Tambah/Hapus dari Portofolio" block from
/// `components/card/card-detail.tsx` — local `qty` seeded from the user's
/// current owned count, with the button only shown once `qty` diverges
/// from it (`delta`), same as `useAddToPortfolio`.
class _AddToCollectionSection extends ConsumerStatefulWidget {
  const _AddToCollectionSection({required this.cardId});

  final int cardId;

  @override
  ConsumerState<_AddToCollectionSection> createState() =>
      _AddToCollectionSectionState();
}

class _AddToCollectionSectionState
    extends ConsumerState<_AddToCollectionSection> {
  int _qty = 0;
  int _syncedOwned = 0;
  bool _loading = false;

  Future<void> _submit(int delta) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) {
      context.push(Routes.login);
      return;
    }
    setState(() => _loading = true);
    final error = await ref
        .read(cardOwnershipControllerProvider)
        .adjustQuantity(userId: user.id, cardId: widget.cardId, delta: delta);
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final abs = delta.abs();
    final message = delta > 0
        ? (abs == 1
              ? 'Kartu ditambahkan ke portofolio'
              : '$abs kartu ditambahkan ke portofolio')
        : (abs == 1
              ? 'Kartu dikurangi dari portofolio'
              : '$abs kartu dikurangi dari portofolio');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final owned =
        ref.watch(ownedQuantityProvider(widget.cardId)).valueOrNull ?? 0;
    if (owned != _syncedOwned) {
      _qty = owned;
      _syncedOwned = owned;
    }
    final delta = _qty - owned;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QuantitySelector(
            value: _qty,
            onChanged: (v) => setState(() => _qty = v),
          ),
          if (delta != 0) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : () => _submit(delta),
                style: ElevatedButton.styleFrom(
                  backgroundColor: delta > 0
                      ? context.appSemantic.success
                      : context.appColors.error,
                ),
                child: _loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        delta > 0
                            ? 'Tambah ke Portofolio'
                            : 'Hapus dari Portofolio',
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
