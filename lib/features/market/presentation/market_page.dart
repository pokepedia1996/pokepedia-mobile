import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../features/cart/usecase/cart_notifier.dart';
import '../../../shared/models/card_condition.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/listing_card.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/store_card.dart';
import '../usecase/market_notifier.dart';

/// Ports `app/market/page.tsx` — marketplace bucket tabs
/// (Semua/Listing/Buylist/Toko), search, and the listing sort/filter rail
/// (`storefront-filter-rail.tsx`), collapsed into two buttons that open
/// bottom sheets instead of a side rail, matching how the mobile app has
/// simplified every other filter surface (advanced search, portfolio).
class MarketPage extends ConsumerStatefulWidget {
  const MarketPage({super.key});

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
      // No AppBar: the title row has to collapse and hand its cart button
      // down to the search row, which an AppBar can't do. `top: true` puts
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
                  // The web morph keeps this 8px gap above the header in
                  // both states; only the gap below the title row animates.
                  const SizedBox(height: 8),
                  // Title row — collapses to nothing on scroll. `heightFactor`
                  // rather than an animated height so the row is clipped as
                  // it shrinks instead of overflowing its own box.
                  ClipRect(
                    child: AnimatedAlign(
                      alignment: Alignment.topCenter,
                      heightFactor: _scrolled ? 0 : 1,
                      duration: _morphDuration,
                      curve: _morphCurve,
                      child: AnimatedSlide(
                        // The timeline's `y: -4` on a 48px row.
                        offset: _scrolled
                            ? const Offset(0, -4 / 48)
                            : Offset.zero,
                        duration: _morphDuration,
                        curve: _morphCurve,
                        child: AnimatedOpacity(
                          opacity: _scrolled ? 0 : 1,
                          duration: _morphDuration,
                          curve: _morphCurve,
                          child: SizedBox(
                            height: 48,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Market',
                                      style: AppTypography.h2(colors.onSurface),
                                    ),
                                  ),
                                  const _CartButton(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Search row. Its top gap closes as the title row leaves,
                  // matching the web's `marginTop: 8 -> 0`.
                  AnimatedPadding(
                    duration: _morphDuration,
                    curve: _morphCurve,
                    padding: EdgeInsets.fromLTRB(16, _scrolled ? 0 : 8, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onChanged: (v) =>
                                ref.read(marketQueryProvider.notifier).state =
                                    v,
                            decoration: const InputDecoration(
                              hintText: 'Cari kartu atau toko...',
                              prefixIcon: Icon(Icons.search, size: 20),
                            ),
                          ),
                        ),
                        // The cart that slides in beside the search once the
                        // title row's copy is gone. `widthFactor` animates
                        // the web's `width: 0 -> auto`, and `IgnorePointer`
                        // stands in for `pointerEvents: none` so the
                        // zero-width button can't be tapped.
                        IgnorePointer(
                          ignoring: !_scrolled,
                          child: ClipRect(
                            child: AnimatedAlign(
                              alignment: Alignment.centerRight,
                              widthFactor: _scrolled ? 1 : 0,
                              duration: _morphDuration,
                              curve: _morphCurve,
                              child: AnimatedOpacity(
                                opacity: _scrolled ? 1 : 0,
                                duration: _morphDuration,
                                curve: _morphCurve,
                                child: const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: _CartButton(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TabBar(
                    controller: _tabController,
                    labelColor: colors.primary,
                    unselectedLabelColor: context.mutedForeground,
                    indicatorColor: colors.primary,
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: 'Semua'),
                      Tab(text: 'Listing'),
                      Tab(text: 'Buylist'),
                      Tab(text: 'Toko'),
                    ],
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

/// The web mobile header renders `<CartIcon />` twice — once in the title
/// row, once beside the search — and morphs between the two copies. This is
/// that icon, badge included.
class _CartButton extends ConsumerWidget {
  const _CartButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final cartCount = ref.watch(cartProvider).length;

    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.shopping_cart_outlined),
          onPressed: () => context.push(Routes.cart),
        ),
        if (cartCount > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$cartCount',
                style: AppTypography.badge(
                  colors.onPrimary,
                ).copyWith(fontSize: 9),
              ),
            ),
          ),
      ],
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
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => const _SortSheet(),
              ),
              icon: const Icon(Icons.swap_vert, size: 16),
              label: Text(
                'Urutkan: ${sort.labelId}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => const _FilterSheet(),
              ),
              style: filters.activeCount > 0
                  ? OutlinedButton.styleFrom(
                      foregroundColor: colors.primary,
                      side: BorderSide(
                        color: colors.primary.withValues(alpha: 0.4),
                      ),
                    )
                  : null,
              icon: const Icon(Icons.filter_list, size: 16),
              label: Text(
                filters.activeCount > 0
                    ? 'Filter (${filters.activeCount})'
                    : 'Filter',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortSheet extends ConsumerWidget {
  const _SortSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(marketSortProvider);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Urutkan',
                style: AppTypography.h3(context.appColors.onSurface),
              ),
            ),
          ),
          Divider(height: 1, color: context.borderColor),
          RadioGroup<MarketSort>(
            groupValue: current,
            onChanged: (v) {
              if (v == null) return;
              ref.read(marketSortProvider.notifier).state = v;
              Navigator.of(context).pop();
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in MarketSort.values)
                  RadioListTile<MarketSort>(
                    value: option,
                    title: Text(option.labelId),
                    dense: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late MarketFilters _draft;
  late final TextEditingController _minPriceController;
  late final TextEditingController _maxPriceController;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(marketFiltersProvider);
    _minPriceController = TextEditingController(
      text: _draft.minPrice?.toString() ?? '',
    );
    _maxPriceController = TextEditingController(
      text: _draft.maxPrice?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  Set<T> _toggled<T>(Set<T> current, T value) {
    final next = {...current};
    if (!next.add(value)) next.remove(value);
    return next;
  }

  void _apply() {
    final min = int.tryParse(_minPriceController.text.trim());
    final max = int.tryParse(_maxPriceController.text.trim());
    ref.read(marketFiltersProvider.notifier).state = _draft.copyWith(
      minPrice: () => min,
      maxPrice: () => max,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filter',
                      style: AppTypography.h3(colors.onSurface),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _draft = const MarketFilters();
                      _minPriceController.clear();
                      _maxPriceController.clear();
                    }),
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: context.borderColor),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                children: [
                  Text(
                    'Harga',
                    style: AppTypography.captionSemibold(colors.onSurface),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minPriceController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: 'Min'),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('—'),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _maxPriceController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: 'Maks'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _draft.verifiedOnly,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(verifiedOnly: v),
                    ),
                    title: const Text('Hanya toko terverifikasi'),
                    dense: true,
                  ),
                  const SizedBox(height: 8),
                  _FilterSection(
                    label: 'Kondisi',
                    children: [
                      for (final condition in rawConditions)
                        CheckboxListTile(
                          value: _draft.conditions.contains(condition),
                          onChanged: (_) => setState(
                            () => _draft = _draft.copyWith(
                              conditions: _toggled(
                                _draft.conditions,
                                condition,
                              ),
                            ),
                          ),
                          title: Text(condition.label),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                        ),
                    ],
                  ),
                  _FilterSection(
                    label: 'Kategori',
                    children: [
                      for (final category in CardCategory.values)
                        CheckboxListTile(
                          value: _draft.categories.contains(category),
                          onChanged: (_) => setState(
                            () => _draft = _draft.copyWith(
                              categories: _toggled(_draft.categories, category),
                            ),
                          ),
                          title: Text(category.labelId),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                        ),
                    ],
                  ),
                  _FilterSection(
                    label: 'Subtipe Trainer',
                    children: [
                      for (final subtype in TrainerSubtype.values)
                        CheckboxListTile(
                          value: _draft.trainerSubtypes.contains(subtype),
                          onChanged: (_) => setState(
                            () => _draft = _draft.copyWith(
                              trainerSubtypes: _toggled(
                                _draft.trainerSubtypes,
                                subtype,
                              ),
                            ),
                          ),
                          title: Text(subtype.labelId),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                        ),
                    ],
                  ),
                  _FilterSection(
                    label: 'Kelangkaan',
                    children: [
                      for (final rarity in marketPopularRarities)
                        CheckboxListTile(
                          value: _draft.rarities.contains(rarity),
                          onChanged: (_) => setState(
                            () => _draft = _draft.copyWith(
                              rarities: _toggled(_draft.rarities, rarity),
                            ),
                          ),
                          title: Text(rarity),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _apply,
                  child: const Text('Terapkan'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.captionSemibold(context.appColors.onSurface),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _ListingGrid extends ConsumerWidget {
  const _ListingGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(marketListingsProvider);
    return async.when(
      data: (listings) {
        if (listings.isEmpty) {
          return const EmptyState(
            icon: Icons.storefront_outlined,
            title: 'Tidak ada listing',
          );
        }
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            AppBottomNav.reservedSpace(context) + 12,
          ),
          itemCount: listings.length,

          gridDelegate: listingGridDelegate(context, showSeller: true),
          itemBuilder: (context, i) => ListingCard(listing: listings[i]),
        );
      },
      loading: () => const PikachuLoader(),
      error: (_, __) => const Center(child: Text('Gagal memuat listing')),
    );
  }
}

class _StoreDirectory extends ConsumerWidget {
  const _StoreDirectory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(marketStoresProvider);
    return async.when(
      data: (stores) {
        if (stores.isEmpty) {
          return const EmptyState(
            icon: Icons.store_mall_directory_outlined,
            title: 'Toko tidak ditemukan',
          );
        }
        return ListView.separated(
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
