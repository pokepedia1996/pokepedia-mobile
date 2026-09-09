import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/utils/card_filtering.dart';
import '../../../shared/widgets/card_filter_bar.dart';
import '../../../shared/widgets/card_grid_item.dart';
import '../../../shared/widgets/card_list_item.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../usecase/quick_search_notifier.dart';

/// Ports `app/search/page.tsx` — everything matching one query, as a grid.
///
/// The search bar's own dropdown shows the first handful; this is where "Cari
/// semua" lands, and it is a plain results list rather than the filter form
/// at [Routes.search]: the query has already been typed, so the next thing
/// wanted is results, not another form.
class SearchResultsPage extends ConsumerWidget {
  const SearchResultsPage({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final trimmed = query.trim();
    final state = ref.watch(fullSearchProvider(trimmed));
    final notifier = ref.read(fullSearchProvider(trimmed).notifier);
    final signedIn = ref.watch(authProvider).valueOrNull != null;

    // Sorting is the server's (it orders every match, not just this page);
    // the facets narrow what has been fetched, as on the expansion page.
    var visible = applyCardFilters(state.cards, state.filters);
    if (state.ownership == OwnershipFilter.owned) {
      visible = visible.where((c) => c.owned > 0).toList();
    } else if (state.ownership == OwnershipFilter.notOwned) {
      visible = visible.where((c) => c.owned == 0).toList();
    }

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: TransparentAppBar(
        title: Text(
          'Pencarian',
          style: AppTypography.bodySemibold(colors.onSurface),
        ),
      ),
      body: trimmed.length < QuickSearchRepository.minQueryLength
          ? _Placeholder(
              message:
                  'Ketik minimal ${QuickSearchRepository.minQueryLength} '
                  'huruf untuk mencari kartu.',
            )
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Hasil pencarian '$trimmed'",
                          style: AppTypography.h2(colors.onSurface),
                        ),
                        const SizedBox(height: 2),
                        _Subtitle(state: state, query: trimmed),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: CardFilterBar(
                      // Facets derived from the results themselves, and
                      // applied over them — the expansion detail page's
                      // arrangement, so the two card lists filter alike.
                      cards: state.cards,
                      filters: state.filters,
                      onFiltersChanged: notifier.setFilters,
                      ownershipFilter: signedIn ? state.ownership : null,
                      onOwnershipChanged: signedIn
                          ? notifier.setOwnership
                          : null,
                      // Results span every expansion, so this list keeps the
                      // two sorts a single pack has no use for.
                      sortOptions: CardSortOption.values,
                      sortBy: state.sort,
                      onSortChanged: notifier.setSort,
                      viewMode: state.viewMode,
                      onViewModeChanged: notifier.setViewMode,
                      // The query is already in the heading above.
                      showSearch: false,
                    ),
                  ),
                ),
                if (state.loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: PikachuLoader(),
                  )
                else if (state.failed)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _Placeholder(
                      message: 'Gagal memuat hasil pencarian. Coba lagi nanti.',
                      onRetry: notifier.retry,
                    ),
                  )
                else if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: state.cards.isEmpty
                        ? _Placeholder(
                            message:
                                "Tidak ada kartu yang cocok dengan '$trimmed'.",
                          )
                        : _Placeholder(
                            // The query matched; the facets then excluded
                            // everything it matched.
                            message: 'Tidak ada kartu yang sesuai filter.',
                            onRetry: () {
                              notifier.setFilters(const CardFilters());
                              notifier.setOwnership(OwnershipFilter.all);
                            },
                            retryLabel: 'Hapus filter',
                          ),
                  )
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    sliver: state.viewMode == CardViewMode.grid
                        ? SliverGrid(
                            gridDelegate:
                                cardGridDelegate(context),
                            delegate: SliverChildBuilderDelegate((context, i) {
                              final card = visible[i];
                              return CardGridItem(
                                card: card,
                                onTap: () => context.push(
                                  Routes.cardDetail(card.packSlug, card.id),
                                ),
                              );
                            }, childCount: visible.length),
                          )
                        : SliverList(
                            delegate: SliverChildBuilderDelegate((context, i) {
                              final card = visible[i];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: CardListItem(
                                  card: card,
                                  onTap: () => context.push(
                                    Routes.cardDetail(card.packSlug, card.id),
                                  ),
                                ),
                              );
                            }, childCount: visible.length),
                          ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      child: state.hasNext
                          ? SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: state.loadingMore
                                    ? null
                                    : notifier.loadMore,
                                child: Text(
                                  state.loadingMore
                                      ? 'Memuat...'
                                      : 'Muat lebih banyak',
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                'Menampilkan semua ${visible.length} kartu',
                                style: AppTypography.caption(
                                  context.mutedForeground,
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// The count, or the line explaining that these results are for a different
/// spelling than the one typed.
class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.state, required this.query});

  final FullSearchState state;
  final String query;

  @override
  Widget build(BuildContext context) {
    if (state.loading) {
      return Text(
        'Mencari...',
        style: AppTypography.caption(context.mutedForeground),
      );
    }

    final corrected = state.correctedQuery;
    if (corrected != null) {
      return Text.rich(
        TextSpan(
          text: "Tidak ada hasil untuk '$query', menampilkan hasil untuk ",
          style: AppTypography.caption(context.mutedForeground),
          children: [
            TextSpan(
              text: corrected,
              style: AppTypography.captionSemibold(context.appColors.onSurface),
            ),
            if (state.total > 0) TextSpan(text: ' · ${state.total} kartu'),
          ],
        ),
      );
    }

    return Text(
      '${state.total} kartu ditemukan',
      style: AppTypography.caption(context.mutedForeground),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.message,
    this.onRetry,
    this.retryLabel = 'Coba lagi',
  });

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.search,
            size: 44,
            color: context.mutedForeground.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodySm(context.mutedForeground),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ],
      ),
    );
  }
}
