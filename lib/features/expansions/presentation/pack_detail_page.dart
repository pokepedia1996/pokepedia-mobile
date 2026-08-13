import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/models/pack_model.dart';
import '../../../shared/utils/card_filtering.dart';
import '../../../shared/widgets/card_filter_bar.dart';
import '../../../shared/widgets/card_grid_item.dart';
import '../../../shared/widgets/card_list_item.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../usecase/expansions_notifier.dart';
import '../usecase/recently_viewed_provider.dart';

/// Ports `app/expansions/[packSlug]/pack-detail-client.tsx` — the pack
/// header (image, title, meta) plus the search/filter bar and card grid
/// for a single expansion.
class PackDetailPage extends ConsumerStatefulWidget {
  const PackDetailPage({super.key, required this.packSlug});

  final String packSlug;

  @override
  ConsumerState<PackDetailPage> createState() => _PackDetailPageState();
}

class _PackDetailPageState extends ConsumerState<PackDetailPage> {
  CardFilters _filters = const CardFilters();
  CardSortOption _sortBy = CardSortOption.numberAsc;
  CardViewMode _viewMode = CardViewMode.grid;
  OwnershipFilter _ownershipFilter = OwnershipFilter.all;

  @override
  Widget build(BuildContext context) {
    final packAsync = ref.watch(packDetailProvider(widget.packSlug));
    final cardsAsync = ref.watch(packCardsProvider(widget.packSlug));
    final user = ref.watch(authProvider).valueOrNull;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(recentlyViewedSlugsProvider.notifier)
          .markViewed(widget.packSlug);
    });

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: cardsAsync.when(
          data: (cards) {
            final pack = packAsync.valueOrNull;

            var visible = applyCardFilters(cards, _filters);
            if (_ownershipFilter == OwnershipFilter.owned) {
              visible = visible.where((c) => c.owned > 0).toList();
            } else if (_ownershipFilter == OwnershipFilter.notOwned) {
              visible = visible.where((c) => c.owned == 0).toList();
            }
            visible = sortCards(visible, _sortBy);

            final ownedCount = cards.where((c) => c.owned > 0).length;

            return CustomScrollView(
              slivers: [
                if (pack != null)
                  SliverToBoxAdapter(
                    child: _PackHeader(
                      pack: pack,
                      cardCount: cards.length,
                      ownedCount: user != null ? ownedCount : null,
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: CardFilterBar(
                      cards: cards,
                      filters: _filters,
                      onFiltersChanged: (f) => setState(() => _filters = f),
                      sortBy: _sortBy,
                      onSortChanged: (s) => setState(() => _sortBy = s),
                      viewMode: _viewMode,
                      onViewModeChanged: (v) => setState(() => _viewMode = v),
                      ownershipFilter: user != null ? _ownershipFilter : null,
                      onOwnershipChanged: user != null
                          ? (v) => setState(() => _ownershipFilter = v)
                          : null,
                    ),
                  ),
                ),
                if (visible.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    sliver: SliverToBoxAdapter(
                      child: Center(
                        child: Text(
                          'Tidak ada kartu yang sesuai filter.',
                          style: AppTypography.bodySm(context.mutedForeground),
                        ),
                      ),
                    ),
                  )
                else if (_viewMode == CardViewMode.grid)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.62,
                          ),
                      delegate: SliverChildBuilderDelegate((context, i) {
                        final card = visible[i];
                        return CardGridItem(
                          card: card,
                          onTap: () => context.push(
                            Routes.cardDetail(widget.packSlug, card.id),
                          ),
                        );
                      }, childCount: visible.length),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, i) {
                        final card = visible[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: CardListItem(
                            card: card,
                            onTap: () => context.push(
                              Routes.cardDetail(widget.packSlug, card.id),
                            ),
                          ),
                        );
                      }, childCount: visible.length),
                    ),
                  ),
              ],
            );
          },
          loading: () => const PikachuLoader(),
          error: (_, __) => const Center(child: Text('Gagal memuat kartu')),
        ),
      ),
    );
  }
}

class _PackHeader extends StatelessWidget {
  const _PackHeader({
    required this.pack,
    required this.cardCount,
    required this.ownedCount,
  });

  final PackModel pack;
  final int cardCount;

  /// Null when signed out — mirrors the web only appending "Dimiliki: X/Y"
  /// for a logged-in `user`.
  final int? ownedCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: pack.image != null
                ? Image.network(
                    pack.image!,
                    width: double.infinity,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _PackImageFallback(mark: pack.mark),
                  )
                : _PackImageFallback(mark: pack.mark),
          ),
          const SizedBox(height: 16),
          Text(pack.name, style: AppTypography.h1(colors.onSurface)),
          const SizedBox(height: 4),
          Text(
            [
              'Dirilis: ${pack.releaseDate}',
              '$cardCount kartu',
              if (ownedCount != null) 'Dimiliki: $ownedCount / $cardCount',
            ].join(' · '),
            style: AppTypography.caption(context.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _PackImageFallback extends StatelessWidget {
  const _PackImageFallback({required this.mark});

  final String mark;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      height: 120,
      color: colors.secondary,
      alignment: Alignment.center,
      child: Text(mark, style: AppTypography.h1(context.mutedForeground)),
    );
  }
}
