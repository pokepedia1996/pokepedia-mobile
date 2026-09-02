import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/card_ownership_controller.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/image_lightbox.dart';
import '../../../shared/widgets/pack_header_row.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/quantity_selector.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../usecase/expansions_notifier.dart';
import 'widgets/card_details_section.dart';
import 'widgets/related_cards_section.dart';
import 'widgets/card_listings_section.dart';
import 'widgets/card_market_header.dart';
import 'widgets/market_activity_section.dart';
import 'widgets/order_book_widget.dart';

/// Ports `app/expansions/[packSlug]/[cardId]/card-detail-page.tsx` +
/// `components/card/card-detail.tsx` in the shape the web renders below its
/// `lg` breakpoint: breadcrumb, the pack/number header row, the artwork
/// column (portfolio quantity, prev/next card), then `CardMobilePanels` —
/// the price header over a Market / Histori Data tab pair — and finally the
/// card's own info column.
///
/// Editing (the admin `editMode` field pencils, upload/attack/ability
/// modals) has no mobile counterpart and is left out.
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

class _CardDetailPageState extends ConsumerState<CardDetailPage> {
  @override
  Widget build(BuildContext context) {
    final cardAsync = ref.watch(cardDetailProvider(widget.cardId));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: cardAsync.when(
        data: (card) {
          if (card == null) {
            return const EmptyState(
              icon: LucideIcons.searchX,
              title: 'Kartu tidak ditemukan',
            );
          }

          return AppBarOverlayBody(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                // PackHeaderRow(pack: pack, card: card),
                // const SizedBox(height: 12),

                // Artwork column — tap the art for the lightbox, then the
                // portfolio quantity and the neighbouring cards.
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Artwork(card: card),
                        const SizedBox(height: 12),
                        _AddToCollectionSection(cardId: card.id),
                        const SizedBox(height: 12),
                        // Same heading the WTS listing page puts under its
                        // artwork, so a card is named identically wherever
                        // it's opened from.
                      ],
                    ),
                  ),
                ),
                CardTitleLine(card: card),
                const SizedBox(height: 14),

                CardMarketHeader(card: card),
                const SizedBox(height: 12),
                // No tabs: every market block is stacked, in the order a
                // buyer works through them — what's on sale now, what it has
                // actually sold for, how that has moved, and the book behind
                // those prices.
                CardListingsSection(cardId: card.id),
                const SizedBox(height: 16),
                SalesHistorySection(cardId: card.id),
                const SizedBox(height: 16),
                MarketActivitySection(cardId: card.id),
                const SizedBox(height: 16),
                OrderBookWidget(card: card),

                const SizedBox(height: 20),
                Divider(color: context.borderColor, height: 1),
                const SizedBox(height: 16),
                // The collapsible details card the WTS listing page uses,
                // rather than the flat panel this page had: the same card
                // shouldn't read two different ways.
                CardDetailsHeader(
                  card: card,
                  trailing: WishlistButton(cardId: card.id),
                ),
                const SizedBox(height: 12),
                CardDetailsSection(card: card),
                // Web closes the page with this rail, below the info column.
                RelatedCardsSection(card: card),
              ],
            ),
          );
        },
        loading: () => const PikachuLoader(),
        error: (_, __) => const EmptyState(
          icon: LucideIcons.circleAlert,
          title: 'Gagal memuat kartu',
        ),
      ),
    );
  }
}

/// The card image with web's `OwnedBadge` corner marker, opening the
/// lightbox on tap.
class _Artwork extends ConsumerWidget {
  const _Artwork({required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owned = ref.watch(ownedQuantityProvider(card.id)).valueOrNull ?? 0;

    return GestureDetector(
      onTap: () => showImageLightbox(
        context,
        imageUrl: card.imageUrl,
        heroTag: 'card-image-${card.id}',
      ),
      child: Stack(
        children: [
          Hero(
            tag: 'card-image-${card.id}',
            child: CardArt(imageUrl: card.imageUrl, borderRadius: AppRadius.lg),
          ),
          if (owned > 0)
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.appSemantic.success,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.check,
                      size: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 3),
                    Text('$owned', style: AppTypography.badge(Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ports the prev/next card links under the artwork — the neighbours by
/// collector number within the same expansion.
class _AdjacentCardsNav extends ConsumerWidget {
  const _AdjacentCardsNav({required this.packSlug, required this.cardId});

  final String packSlug;
  final int cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(packCardsProvider(packSlug)).valueOrNull;
    if (cards == null) return const SizedBox.shrink();
    final index = cards.indexWhere((c) => c.id == cardId);
    if (index < 0) return const SizedBox.shrink();

    final previous = index > 0 ? cards[index - 1] : null;
    final next = index < cards.length - 1 ? cards[index + 1] : null;
    if (previous == null && next == null) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: previous == null
              ? const SizedBox.shrink()
              : _NavChip(card: previous, isNext: false),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: next == null
              ? const SizedBox.shrink()
              : _NavChip(card: next, isNext: true),
        ),
      ],
    );
  }
}

class _NavChip extends StatelessWidget {
  const _NavChip({required this.card, required this.isNext});

  final CardModel card;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final label = Flexible(
      child: Text(
        card.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.caption(context.mutedForeground),
      ),
    );
    final chevron = Icon(
      isNext ? LucideIcons.chevronRight : LucideIcons.chevronLeft,
      size: 16,
      color: context.mutedForeground,
    );

    return InkWell(
      // Replaces rather than pushes: paging through an expansion shouldn't
      // stack a route per card behind the back button.
      onTap: () => context.replace(Routes.cardDetail(card.packSlug, card.id)),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: context.borderColor),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          mainAxisAlignment: isNext
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: isNext ? [label, chevron] : [chevron, label],
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

    return Column(
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
    );
  }
}
