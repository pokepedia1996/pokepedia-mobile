import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/cart_app_bar_button.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/image_lightbox.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../usecase/expansions_notifier.dart';
import 'widgets/add_to_portfolio_panel.dart';
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
      appBar: const TransparentAppBar(actions: [CartAppBarButton()]),
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
                _Breadcrumb(card: card),
                const SizedBox(height: 12),

                // Artwork column — tap the art for the lightbox, then the
                // portfolio quantity and the neighbouring cards.
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _Artwork(card: card),
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
                const SizedBox(height: 14),
                // Adding a copy is a decision about the price above it, so
                // the panel sits under the price rather than under the
                // artwork where a bare stepper used to.
                AddToPortfolioPanel(card: card),
                const SizedBox(height: 16),
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
                CardDetailsHeader(card: card),
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

/// "Ekspansi › Nama kartu › Nomor" above the artwork.
///
/// Ports `components/ui/breadcrumb.tsx` as the card page uses it: chevrons
/// between, the trail muted and the card itself in plain foreground, and the
/// whole thing scrolls sideways rather than wrapping — a long expansion name
/// beside a long card name doesn't fit a phone, and a breadcrumb that wraps
/// to two lines stops reading as one.
class _Breadcrumb extends ConsumerWidget {
  const _Breadcrumb({required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final muted = context.mutedForeground;
    final pack = ref
        .watch(
          packForCardProvider((
            slug: card.packSlug,
            language: card.language.raw,
          )),
        )
        .valueOrNull;
    // The code until the pack's name arrives, rather than a blank segment.
    final expansion = (pack?.name.isNotEmpty ?? false)
        ? pack!.name
        : card.expansionCode.toUpperCase();

    Widget chevron() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Icon(LucideIcons.chevronRight, size: 13, color: muted),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // The one segment that goes anywhere: back to the expansion this
          // card belongs to.
          InkWell(
            onTap: () => context.push(Routes.packDetail(card.packSlug)),
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
              child: Text(expansion, style: AppTypography.caption(muted)),
            ),
          ),
          chevron(),
          Text(card.name, style: AppTypography.caption(colors.onSurface)),
          chevron(),
          Text(
            card.collectorNumber,
            style: AppTypography.captionSemibold(colors.onSurface),
          ),
        ],
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
