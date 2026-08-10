import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/utils/card_filtering.dart';
import '../../../shared/widgets/app_top_bar.dart';
import '../../../shared/widgets/card_filter_bar.dart';
import '../../../shared/widgets/card_grid_item.dart';
import '../../../shared/widgets/card_list_item.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../usecase/portfolio_notifier.dart';
import 'deck_tab.dart';
import 'inventory_tab.dart';

/// Ports `app/portfolio/collection`, `/deck`, `/inventory` — plus a
/// mobile-only Wishlist tab surfacing `card_wishlists`
/// (`components/card/wishlist-button.tsx`'s data, which the web only shows
/// inline as a heart toggle, not as its own page).
class PortfolioPage extends ConsumerStatefulWidget {
  const PortfolioPage({super.key});

  @override
  ConsumerState<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends ConsumerState<PortfolioPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const AppTopBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Koleksi Kartu',
                  style: AppTypography.h2(context.appColors.onSurface),
                ),
              ),
            ),
            if (user == null)
              Expanded(
                child: EmptyState(
                  icon: Icons.style_outlined,
                  title: 'Masuk untuk melihat koleksimu',
                  description:
                      'Kelola koleksi, deck, inventori, dan wishlist kartu Pokemon-mu.',
                  action: ElevatedButton(
                    onPressed: () => context.push(Routes.login),
                    child: const Text('Masuk'),
                  ),
                ),
              )
            else ...[
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: context.appColors.primary,
                unselectedLabelColor: context.mutedForeground,
                indicatorColor: context.appColors.primary,
                tabs: const [
                  Tab(text: 'Koleksi'),
                  Tab(text: 'Deck'),
                  Tab(text: 'Inventori'),
                  Tab(text: 'Wishlist'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: const [
                    _CollectionTab(),
                    DeckTab(),
                    InventoryTab(),
                    _WishlistTab(),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shared search/filter/sort/grid-list browser for a flat card list — used
/// by both the Koleksi and Wishlist tabs.
class _CardBrowseTab extends ConsumerStatefulWidget {
  const _CardBrowseTab({
    required this.provider,
    required this.emptyIcon,
    required this.emptyTitle,
    this.emptyDescription,
    this.headerBuilder,
  });

  final FutureProvider<List<CardModel>> provider;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyDescription;
  final Widget Function(BuildContext context, List<CardModel> cards)?
  headerBuilder;

  @override
  ConsumerState<_CardBrowseTab> createState() => _CardBrowseTabState();
}

class _CardBrowseTabState extends ConsumerState<_CardBrowseTab> {
  CardFilters _filters = const CardFilters();
  CardSortOption _sortBy = CardSortOption.numberAsc;
  CardViewMode _viewMode = CardViewMode.grid;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(widget.provider);
    return async.when(
      data: (cards) {
        if (cards.isEmpty) {
          return EmptyState(
            icon: widget.emptyIcon,
            title: widget.emptyTitle,
            description: widget.emptyDescription,
          );
        }

        var visible = applyCardFilters(cards, _filters);
        visible = sortCards(visible, _sortBy);

        return CustomScrollView(
          slivers: [
            if (widget.headerBuilder != null)
              SliverToBoxAdapter(child: widget.headerBuilder!(context, cards)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: CardFilterBar(
                  cards: cards,
                  filters: _filters,
                  onFiltersChanged: (f) => setState(() => _filters = f),
                  sortBy: _sortBy,
                  onSortChanged: (s) => setState(() => _sortBy = s),
                  viewMode: _viewMode,
                  onViewModeChanged: (v) => setState(() => _viewMode = v),
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
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                        Routes.cardDetail(card.packSlug, card.id),
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
                          Routes.cardDetail(card.packSlug, card.id),
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
      error: (_, __) => const Center(child: Text('Gagal memuat data')),
    );
  }
}

class _CollectionTab extends StatelessWidget {
  const _CollectionTab();

  @override
  Widget build(BuildContext context) {
    return _CardBrowseTab(
      provider: collectionProvider,
      emptyIcon: Icons.style_outlined,
      emptyTitle: 'Koleksi masih kosong',
      emptyDescription:
          'Tambahkan kartu yang kamu miliki dari halaman ekspansi.',
      headerBuilder: (context, cards) {
        final totalValue = cards.fold<int>(
          0,
          (sum, c) => sum + (c.marketPrice ?? 0) * c.owned,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              _StatChip(label: 'Kartu unik', value: '${cards.length}'),
              const SizedBox(width: 8),
              _StatChip(
                label: 'Estimasi nilai',
                value: formatRupiah(totalValue),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WishlistTab extends StatelessWidget {
  const _WishlistTab();

  @override
  Widget build(BuildContext context) {
    return _CardBrowseTab(
      provider: wishlistProvider,
      emptyIcon: Icons.favorite_border,
      emptyTitle: 'Wishlist masih kosong',
      emptyDescription:
          'Ketuk ikon hati di halaman detail kartu untuk menambahkannya ke sini.',
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTypography.caption(context.mutedForeground)),
            const SizedBox(height: 2),
            Text(
              value,
              style: AppTypography.bodySmSemibold(context.appColors.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
