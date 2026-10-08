import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/widgets/app_search_field.dart';
import '../../../shared/widgets/app_top_bar.dart';
import '../../../app/tab_reselect.dart';
import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/listing_card.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/store_card.dart';
import '../usecase/market_notifier.dart';
import 'widgets/listing_filter_sheet.dart';

/// Ports `app/market/page.tsx` — marketplace bucket tabs
/// (Semua/Listing/Buylist/Toko), search, and the listing sort/filter rail
/// (`storefront-filter-rail.tsx`), collapsed into two buttons that open
/// bottom sheets instead of a side rail, matching how the mobile app has
/// simplified every other filter surface (advanced search, portfolio).
/// Where Market sits in the nav, so the grids can tell its re-tap from
/// another tab's. Read off the nav's own list rather than written as a
/// literal, which would go stale the next time a tab moves.
final _marketTabIndex = AppBottomNav.tabPaths.indexOf(Routes.market);

class MarketPage extends ConsumerStatefulWidget {
  const MarketPage({super.key, this.initialQuery, this.initialTab});

  /// A query the page was opened on — quick search's "di Market" scope.
  ///
  /// Applied once, like the seller page's `?tab=`: after arrival the search
  /// box owns the query, and a link that kept reasserting it would fight
  /// whatever the reader typed next.
  final String? initialQuery;

  /// Which tab to land on. `stores` is the one quick search sends "Cari
  /// toko" to; anything else leaves the page on its usual tab.
  final String? initialTab;

  @override
  ConsumerState<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends ConsumerState<MarketPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _buckets = [
    MarketBucket.all,
    MarketBucket.listing,
    MarketBucket.buylist,
    MarketBucket.toko,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _buckets.length, vsync: this);
    final query = widget.initialQuery?.trim();
    final wantsStores = widget.initialTab == 'stores';
    if ((query != null && query.isNotEmpty) || wantsStores) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (query != null && query.isNotEmpty) {
          ref.read(marketQueryProvider.notifier).state = query;
        }
        // The directory is the last tab; the three before it are listings.
        if (wantsStores) _tabController.index = _buckets.length - 1;
      });
    }
    _tabController.addListener(() {
      final next = _buckets[_tabController.index];
      if (ref.read(bucketProvider) != next) {
        ref.read(bucketProvider.notifier).state = next;
      }
    });
  }

  /// Web's navbar morph fires at `window.scrollY > 100`
  /// (`NavbarMain` in `components/layout/navbar.tsx`). Position-based, not
  /// direction-based, so the header state matches the scroll offset exactly
  /// the way it does on web.
  static const _morphThreshold = 100.0;

  /// `MobileScrollMorph`'s GSAP timeline runs 0.4s at power2.inOut; this is
  /// deliberately quicker, since a phone scroll reaches the threshold faster
  /// than a desktop one and the header should be settled by the time the
  /// first row of results is in view. `easeOutCubic` puts most of the travel
  /// up front so the shorter duration reads as snap rather than a rush.
  static const _morphDuration = Duration(milliseconds: 180);
  static const _morphCurve = Curves.easeOutCubic;

  /// True past the threshold: the title row folds away and the cart button
  /// moves down beside the search field.
  bool _scrolled = false;

  bool _onScroll(ScrollNotification notification) {
    // The TabBarView's own horizontal paging bubbles up here too.
    if (notification.metrics.axis != Axis.vertical) return false;

    final scrolled = notification.metrics.pixels > _morphThreshold;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    return false;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bucket = ref.watch(bucketProvider);
    final colors = context.appColors;

    return Scaffold(
      // No AppBar: the shared top bar's logo row collapses and hands its
      // cart button down to the search row, which an AppBar can't do. `top: true` puts
      // the header below the status bar now that the AppBar isn't supplying
      // that inset; `bottom: false` still lets the grid run under the
      // floating nav pill.
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Sticky header: search, bucket tabs and the sort/filter row
            // stay put while the results scroll underneath, mirroring the
            // web's `sticky top-0 border-b border-border/50 bg-card/95`
            // treatment. An opaque background is what makes it read as
            // sticky — without it the grid shows through as it passes by.
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(
                  bottom: BorderSide(
                    // `dividerColor` is where the theme puts the web's
                    // `--border` token.
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Beranda's bar: logo and cart above the search field,
                  // folding to the field alone on scroll, with the scanner in
                  // the field. Market keeps its own field in it, since typing
                  // here narrows the feed below rather than opening quick
                  // search's suggestions over it.
                  AppTopBar(
                    searchField: AppSearchField(
                      hintText: 'Cari kartu atau toko...',
                      onChanged: (v) =>
                          ref.read(marketQueryProvider.notifier).state = v,
                      onScan: () => context.push(Routes.scan),
                    ),
                  ),
                  // The bucket tabs fold away once the grid is moving, the
                  // same collapse the title row does: past the first screen
                  // the choice is already made and the rail is just holding
                  // pixels. Scrolling back up brings it straight back.
                  AnimatedSize(
                    duration: _morphDuration,
                    curve: _morphCurve,
                    alignment: Alignment.topCenter,
                    child: _scrolled
                        ? const SizedBox(width: double.infinity)
                        : TabBar(
                            controller: _tabController,
                            labelColor: colors.primary,
                            unselectedLabelColor: context.mutedForeground,
                            indicatorColor: colors.primary,
                            indicatorSize: TabBarIndicatorSize.tab,
                            dividerColor: Colors.transparent,
                            tabs: const [
                              Tab(text: 'Semua'),
                              Tab(text: 'Selling'),
                              Tab(text: 'Buying'),
                              Tab(text: 'Toko'),
                            ],
                          ),
                  ),
                  if (bucket != MarketBucket.toko) const _SortFilterBar(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: TabBarView(
                  controller: _tabController,
                  children: const [
                    _ListingGrid(),
                    _ListingGrid(),
                    _ListingGrid(),
                    _StoreDirectory(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The web filter rail's `SortRadioGroup` + `StorefrontFilterRail`,
/// collapsed into two buttons that open bottom sheets.
class _SortFilterBar extends ConsumerWidget {
  const _SortFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(marketSortProvider);
    final filters = ref.watch(marketFiltersProvider);
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),

      // Sized to their labels and pushed left, rather than each taking half
      // the screen: two controls that read as chips, not as a pair of
      // full-width actions competing with the grid below them.
      child: Row(
        children: [
          const Spacer(),

          OutlinedButton.icon(
            onPressed: () => showListingSheet(context, const _SortSheet()),
            style: _railButton(),
            icon: const Icon(LucideIcons.arrowUpDown, size: 15),
            label: Text(
              sort.labelId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => showListingSheet(
              context,
              ListingFilterSheet(
                initial: ref.read(marketFiltersProvider),
                facets: marketFacetsProvider,
                showWishlist: true,
                showHideBulk: true,
                showVerified: true,
                onApply: (filters, _) =>
                    ref.read(marketFiltersProvider.notifier).state = filters,
              ),
            ),
            style: filters.activeCount > 0
                ? _railButton().copyWith(
                    foregroundColor: WidgetStatePropertyAll(colors.primary),
                    side: WidgetStatePropertyAll(
                      BorderSide(color: colors.primary.withValues(alpha: 0.4)),
                    ),
                  )
                : _railButton(),
            icon: const Icon(LucideIcons.listFilter, size: 15),
            label: Text(
              filters.activeCount > 0
                  ? 'Filter (${filters.activeCount})'
                  : 'Filter',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The rail chips are shorter and tighter than a standard button — they
/// label the grid rather than act on it.
ButtonStyle _railButton() => OutlinedButton.styleFrom(
  minimumSize: const Size(0, 34),
  padding: const EdgeInsets.symmetric(horizontal: 12),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  visualDensity: VisualDensity.compact,
);

/// Ports `SortRadioGroup` — label on the left, radio dot on the right.
class _SortSheet extends ConsumerWidget {
  const _SortSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(marketSortProvider);
    return ListingSheet(
      title: 'Urutkan',
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          for (final option in MarketSort.values)
            _SortRow(
              label: option.labelId,
              checked: option == current,
              onTap: () {
                ref.read(marketSortProvider.notifier).state = option;
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}

class _SortRow extends StatelessWidget {
  const _SortRow({
    required this.label,
    required this.checked,
    required this.onTap,
  });

  final String label;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: checked
                    ? AppTypography.bodySmSemibold(colors.onSurface)
                    : AppTypography.bodySm(context.mutedForeground),
              ),
            ),
            Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: checked ? colors.primary : context.borderColor,
                ),
              ),
              child: checked
                  ? Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ListingGrid extends ConsumerStatefulWidget {
  const _ListingGrid();

  @override
  ConsumerState<_ListingGrid> createState() => _ListingGridState();
}

class _ListingGridState extends ConsumerState<_ListingGrid> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Tapping Market while already on Market: back to the top, and re-read.
    // Listened to here rather than on the page because this is what owns the
    // scroll position — the page has three of these and a directory, and
    // only the one on screen has anywhere to scroll to.
    ref.listen(tabReselectProvider, (_, signal) {
      if (signal.index != _marketTabIndex) return;
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
      ref.read(marketListingsProvider.notifier).retry();
    });

    final state = ref.watch(marketListingsProvider);

    if (state.loading) return const PikachuLoader();
    if (state.error) {
      return EmptyState(
        icon: LucideIcons.circleAlert,
        title: 'Gagal memuat listing',
        action: OutlinedButton(
          onPressed: () => ref.read(marketListingsProvider.notifier).retry(),
          child: const Text('Coba lagi'),
        ),
      );
    }
    if (state.listings.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.store,
        title: 'Tidak ada listing',
      );
    }

    final listings = state.listings;

    return NotificationListener<ScrollNotification>(
      // Fires well before the last row, as web's sentinel does with its
      // 200px rootMargin — the next page should already be arriving by the
      // time the user gets there.
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.axis != Axis.vertical) return false;
        if (metrics.extentAfter < 600) {
          ref.read(marketListingsProvider.notifier).loadMore();
        }
        return false;
      },
      // A sliver grid with a footer rather than one more grid cell: as a
      // cell the spinner sat in the first column, off to the left. Below the
      // grid it spans the full width and centres properly.
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverGrid(
              gridDelegate: listingGridDelegate(context, showSeller: true),
              delegate: SliverChildBuilderDelegate(
                (context, i) => ListingCard(listing: listings[i]),
                childCount: listings.length,
              ),
            ),
          ),
          if (state.hasNext)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(height: AppBottomNav.reservedSpace(context) + 12),
          ),
        ],
      ),
    );
  }
}

class _StoreDirectory extends ConsumerStatefulWidget {
  const _StoreDirectory();

  @override
  ConsumerState<_StoreDirectory> createState() => _StoreDirectoryState();
}

class _StoreDirectoryState extends ConsumerState<_StoreDirectory> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tabReselectProvider, (_, signal) {
      if (signal.index != _marketTabIndex) return;
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
      ref.invalidate(marketStoresProvider);
    });

    final async = ref.watch(marketStoresProvider);
    return async.when(
      data: (stores) {
        if (stores.isEmpty) {
          return const EmptyState(
            icon: LucideIcons.store,
            title: 'Toko tidak ditemukan',
          );
        }
        return ListView.separated(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            AppBottomNav.reservedSpace(context) + 12,
          ),
          itemCount: stores.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final store = stores[i];
            return StoreCard(
              store: store,
              onTap: () => context.push(Routes.storeDetail(store.handle)),
            );
          },
        );
      },
      loading: () => const PikachuLoader(),
      error: (_, __) => const Center(child: Text('Gagal memuat toko')),
    );
  }
}
