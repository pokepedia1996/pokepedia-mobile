import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/catalog_language_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../features/cart/usecase/cart_notifier.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/utils/card_filtering.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/card_language_badge.dart';
import '../../../shared/widgets/condition_grade_picker.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/listing_card.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/store_card.dart';
import '../usecase/market_notifier.dart';
import 'widgets/proposals_banner.dart';

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
                              prefixIcon: Icon(LucideIcons.search, size: 20),
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
                  // Web puts this above the feed; here it also collapses on
                  // scroll, the same way the logo does, so it doesn't hold
                  // 60-odd pixels of a phone screen hostage while browsing.
                  AnimatedSize(
                    duration: _morphDuration,
                    curve: _morphCurve,
                    alignment: Alignment.topCenter,
                    child: _scrolled
                        ? const SizedBox(width: double.infinity)
                        : const ProposalsBanner(),
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
          icon: const Icon(LucideIcons.shoppingCart),
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
              onPressed: () => _showMarketSheet(context, const _SortSheet()),
              icon: const Icon(LucideIcons.arrowUpDown, size: 16),
              label: Text(
                'Urutkan: ${sort.labelId}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _showMarketSheet(context, const _FilterSheet()),
              style: filters.activeCount > 0
                  ? OutlinedButton.styleFrom(
                      foregroundColor: colors.primary,
                      side: BorderSide(
                        color: colors.primary.withValues(alpha: 0.4),
                      ),
                    )
                  : null,
              icon: const Icon(LucideIcons.listFilter, size: 16),
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

/// Presents a market sheet the way `components/ui/sheet.tsx` does on web —
/// bottom-anchored, rounded, over the bottom nav (the root navigator, since a
/// sheet mounted on the shell branch would be clipped by it) and capped at
/// three quarters of the screen.
Future<void> _showMarketSheet(BuildContext context, Widget sheet) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => sheet,
  );
}

/// The chrome shared by both market sheets — web's bottom `Sheet`: a drag
/// handle, a titled header with a close button, a scrolling body, and an
/// optional pinned footer.
class _MarketSheet extends StatelessWidget {
  const _MarketSheet({required this.title, required this.child, this.footer});

  final String title;
  final Widget child;
  final Widget? footer;

  /// Three quarters of the screen: enough room for the filter sections while
  /// the listings behind stay in view.
  static const _maxHeightFactor = 0.75;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * _maxHeightFactor,
      ),
      child: Padding(
        // Keeps the price fields above the keyboard rather than under it.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: context.mutedForeground.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 10, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: AppTypography.bodySemibold(colors.onSurface),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(LucideIcons.x, size: 16),
                      color: context.mutedForeground,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Tutup',
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: context.borderColor.withValues(alpha: 0.6),
              ),
              Flexible(child: child),
              if (footer != null) footer!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Ports `SortRadioGroup` — label on the left, radio dot on the right.
class _SortSheet extends ConsumerWidget {
  const _SortSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(marketSortProvider);
    return _MarketSheet(
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

/// Web's `TRAINER_SUBTYPE_ORDER` — the subtypes it lists first, spelled as
/// the catalog spells them, and what the section falls back to before the
/// facet counts arrive.
const _trainerSubtypeOrder = ['Item', 'Supporter', 'Stadium', 'Pokémon Tool'];

/// Web's `CATEGORY_LABELS` — the only category whose display name differs
/// from its stored value.
const _categoryLabels = {
  CardCategory.pokemon: 'Pokémon',
  CardCategory.trainer: 'Trainer',
  CardCategory.energy: 'Energy',
};

/// Ports the mobile form of `StorefrontFilterRail` — the `embedded`,
/// `hideSort` rail web drops into its bottom sheet: section labels over
/// compact checkbox rows, Trainer's subtypes nested under a tri-state
/// parent, the condition grade pills, then the price range.
///
/// Unlike the web rail, which pushes every tick straight into the URL, the
/// sheet edits a draft and commits it on "Terapkan": the feed it filters is
/// behind the sheet, so applying live would just refetch out of sight.
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
    // Reset only shows while something is on, and a typed price counts.
    _minPriceController.addListener(_onPriceChanged);
    _maxPriceController.addListener(_onPriceChanged);
  }

  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  void _onPriceChanged() => setState(() {});

  bool get _hasActiveFilters =>
      _draft.activeCount > 0 ||
      _minPriceController.text.isNotEmpty ||
      _maxPriceController.text.isNotEmpty;

  Set<T> _toggled<T>(Set<T> current, T value) {
    final next = {...current};
    if (!next.add(value)) next.remove(value);
    return next;
  }

  void _toggleCategory(CardCategory category) {
    setState(() {
      final categories = _toggled(_draft.categories, category);
      _draft = _draft.copyWith(
        categories: categories,
        // Dropping Trainer drops the subtypes hanging off it, the way
        // `handleCategoryChange` clears `tsub` on web.
        trainerSubtypes: categories.contains(CardCategory.trainer)
            ? _draft.trainerSubtypes
            : const {},
      );
    });
  }

  /// Trainer's tri-state parent: ticking it takes the category and every
  /// subtype with it, the way web's `toggleTrainerAll` does; clearing it
  /// drops both. It reads as mixed while only some subtypes are on.
  void _toggleTrainerAll(bool selected, List<String> subtypes) {
    setState(() {
      _draft = _draft.copyWith(
        categories: selected
            ? ({..._draft.categories}..remove(CardCategory.trainer))
            : {..._draft.categories, CardCategory.trainer},
        trainerSubtypes: selected ? const {} : subtypes.toSet(),
      );
    });
  }

  /// Picking a subtype implies its category, as `handleTrainerSubtypeChange`
  /// does on web.
  void _toggleTrainerSubtype(String subtype) {
    setState(() {
      final subtypes = _toggled(_draft.trainerSubtypes, subtype);
      _draft = _draft.copyWith(
        trainerSubtypes: subtypes,
        categories: subtypes.isEmpty
            ? _draft.categories
            : {..._draft.categories, CardCategory.trainer},
      );
    });
  }

  void _reset() {
    setState(() {
      _draft = const MarketFilters();
      _minPriceController.clear();
      _maxPriceController.clear();
    });
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
    // Facets say what the tab actually holds. They arrive a moment after the
    // sheet does, so every group falls back to its fixed vocabulary until
    // then rather than flashing empty.
    final facets =
        ref.watch(marketFacetsProvider).valueOrNull ?? ListingFacets.empty;
    // No wishlist to filter by while signed out, so web hides the control
    // rather than offering one that cannot work.
    final signedIn = ref.watch(authProvider).valueOrNull != null;

    final subtypeOptions = _subtypeOptions(facets);
    final trainerSelected = _draft.categories.contains(CardCategory.trainer);
    // An empty subtype set means "every Trainer card", so it reads as fully
    // checked; a partial set is the tri-state's mixed mark.
    final trainerMixed =
        trainerSelected &&
        _draft.trainerSubtypes.isNotEmpty &&
        _draft.trainerSubtypes.length != subtypeOptions.length;

    return _MarketSheet(
      title: 'Filter',
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _apply,
            child: const Text('Terapkan'),
          ),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        children: [
          if (_hasActiveFilters)
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: _reset,
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    'Reset',
                    style: AppTypography.caption(
                      context.mutedForeground,
                    ).copyWith(decoration: TextDecoration.underline),
                  ),
                ),
              ),
            ),
          if (signedIn)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _WishlistToggle(
                active: _draft.wishlistOnly,
                onTap: () => setState(
                  () => _draft = _draft.copyWith(
                    wishlistOnly: !_draft.wishlistOnly,
                  ),
                ),
              ),
            ),
          _FilterSection(
            label: 'Tipe Toko',
            children: [
              _FilterCheckRow(
                label: 'Terverifikasi',
                checked: _draft.verifiedOnly,
                icon: LucideIcons.badgeCheck,
                onTap: () => setState(
                  () => _draft = _draft.copyWith(
                    verifiedOnly: !_draft.verifiedOnly,
                  ),
                ),
              ),
            ],
          ),
          _FilterSection(
            label: 'Feeds',
            children: [
              _FilterCheckRow(
                label: 'Exclude bulk (C/U/R)',
                checked: _draft.hideBulk,
                onTap: () => setState(
                  () => _draft = _draft.copyWith(hideBulk: !_draft.hideBulk),
                ),
              ),
            ],
          ),
          _FilterSection(
            label: 'Tipe Kartu',
            children: [
              for (final category in CardCategory.values) ...[
                if (category == CardCategory.trainer)
                  _FilterCheckRow(
                    label: _categoryLabels[category]!,
                    checked: trainerSelected,
                    mixed: trainerMixed,
                    count: facets.categories.countOf(category.raw),
                    onTap: () =>
                        _toggleTrainerAll(trainerSelected, subtypeOptions),
                  )
                else
                  _FilterCheckRow(
                    label: _categoryLabels[category]!,
                    checked: _draft.categories.contains(category),
                    count: facets.categories.countOf(category.raw),
                    onTap: () => _toggleCategory(category),
                  ),
                if (category == CardCategory.trainer)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                    child: Container(
                      padding: const EdgeInsets.only(left: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: context.borderColor),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final subtype in subtypeOptions)
                            _FilterCheckRow(
                              label: subtype,
                              checked: _draft.trainerSubtypes.contains(subtype),
                              count: facets.trainerSubtypes.countOf(subtype),
                              onTap: () => _toggleTrainerSubtype(subtype),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
          _FilterSection(
            label: 'Bahasa',
            children: [
              Row(
                children: [
                  for (final language in catalogLanguages) ...[
                    if (language != catalogLanguages.first)
                      const SizedBox(width: 6),
                    Expanded(
                      child: _LanguageChip(
                        language: language,
                        active: _draft.languages.contains(language),
                        onTap: () => setState(
                          () => _draft = _draft.copyWith(
                            languages: _toggled(_draft.languages, language),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          _FacetCheckGroup(
            label: 'Rarity',
            options: _rarityOptions(facets),
            preview: _rarityPreview(facets),
            selected: _draft.rarities,
            onToggle: (rarity) => setState(
              () => _draft = _draft.copyWith(
                rarities: _toggled(_draft.rarities, rarity),
              ),
            ),
          ),
          _FilterSection(
            label: 'Kondisi',
            children: [
              ConditionGradePicker.multi(
                selected: _draft.conditions,
                facetCounts: facets.conditions.countsByValue,
                onToggled: (condition) => setState(
                  () => _draft = _draft.copyWith(
                    conditions: _toggled(_draft.conditions, condition),
                  ),
                ),
              ),
            ],
          ),
          // Web hides Lokasi when every listing sits in one city — a filter
          // that cannot narrow anything.
          if (facets.cities.length > 1)
            _FacetCheckGroup(
              label: 'Lokasi',
              options: facets.cities,
              preview: facets.cities.take(marketFacetPreviewCount).toList(),
              selected: _draft.cities,
              onToggle: (city) => setState(
                () => _draft = _draft.copyWith(
                  cities: _toggled(_draft.cities, city),
                ),
              ),
            ),
          _FilterSection(
            label: 'Harga (IDR)',
            children: [
              _PriceField(controller: _minPriceController, hint: 'Rp Terendah'),
              const SizedBox(height: 8),
              _PriceField(
                controller: _maxPriceController,
                hint: 'Rp Tertinggi',
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The Trainer subtypes the feed holds, in web's `TRAINER_SUBTYPE_ORDER`
  /// with anything unlisted after it. Facet values are the strings the cards
  /// were catalogued with ("Pokémon Tool", accent and all), so filtering by
  /// them is what actually matches rows.
  List<String> _subtypeOptions(ListingFacets facets) {
    if (facets.trainerSubtypes.isEmpty) return _trainerSubtypeOrder;
    final values = facets.trainerSubtypes.map((f) => f.value).toList();
    return [
      for (final known in _trainerSubtypeOrder)
        if (values.contains(known)) known,
      ...values.where((v) => !_trainerSubtypeOrder.contains(v)),
    ];
  }

  /// Every rarity on the tab, ranked as web ranks them; the popular shortlist
  /// stands in until the counts land.
  List<FacetItem> _rarityOptions(ListingFacets facets) {
    if (facets.rarities.isEmpty) {
      return [
        for (final rarity in marketPopularRarities)
          FacetItem(value: rarity, count: 0),
      ];
    }
    return [...facets.rarities]
      ..sort((a, b) => rarityRank(a.value).compareTo(rarityRank(b.value)));
  }

  /// What the group shows collapsed: the popular rarities it has, else the
  /// first few by rank — `popularRarityPreview` on web.
  List<FacetItem> _rarityPreview(ListingFacets facets) {
    final options = _rarityOptions(facets);
    final popular = [
      for (final rarity in marketPopularRarities)
        ...options.where((o) => o.value == rarity),
    ];
    return popular.isNotEmpty
        ? popular
        : options.take(marketFacetPreviewCount).toList();
  }
}

/// A labelled block in the rail — `typo-caption` label over its controls,
/// with the rail's `space-y-5` gap between blocks.
class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              label,
              style: AppTypography.captionSemibold(context.appColors.onSurface),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// Web's `CheckboxFilterGroup` — a facet's options with their counts, cut to
/// a preview with a "Lihat selengkapnya" toggle when there are more.
class _FacetCheckGroup extends StatefulWidget {
  const _FacetCheckGroup({
    required this.label,
    required this.options,
    required this.preview,
    required this.selected,
    required this.onToggle,
  });

  final String label;
  final List<FacetItem> options;
  final List<FacetItem> preview;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  State<_FacetCheckGroup> createState() => _FacetCheckGroupState();
}

class _FacetCheckGroupState extends State<_FacetCheckGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.options.isEmpty) return const SizedBox.shrink();

    final hasMore = widget.options.length > widget.preview.length;
    // A selected option hidden inside the collapsed tail would look like it
    // had been dropped, so the group opens itself around it.
    final visible = _expanded || !hasMore
        ? widget.options
        : [
            ...widget.preview,
            ...widget.options.where(
              (o) =>
                  widget.selected.contains(o.value) &&
                  !widget.preview.any((p) => p.value == o.value),
            ),
          ];

    return _FilterSection(
      label: widget.label,
      children: [
        for (final option in visible)
          _FilterCheckRow(
            label: option.value,
            checked: widget.selected.contains(option.value),
            count: option.count > 0 ? option.count : null,
            onTap: () => widget.onToggle(option.value),
          ),
        if (hasMore)
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 12,
                    color: context.appColors.primary,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    _expanded ? 'Lebih sedikit' : 'Lihat selengkapnya',
                    style: AppTypography.caption(context.appColors.primary),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One checkbox row of the rail: a small box, an optional leading icon, the
/// label — solid once ticked — and the facet count trailing it.
class _FilterCheckRow extends StatelessWidget {
  const _FilterCheckRow({
    required this.label,
    required this.checked,
    required this.onTap,
    this.icon,
    this.count,
    this.mixed = false,
  });

  final String label;
  final bool checked;
  final VoidCallback onTap;
  final IconData? icon;

  /// How many listings carry this option, when the facets know.
  final int? count;

  /// Web's `TriStateCheckbox` — some, but not all, of the row's children are
  /// selected.
  final bool mixed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: mixed ? null : checked,
                tristate: mixed,
                onChanged: (_) => onTap(),
                activeColor: colors.primary,
                side: BorderSide(color: context.borderColor, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 10),
            if (icon != null) ...[
              Icon(icon, size: 14, color: colors.primary),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                label,
                style: checked || mixed
                    ? AppTypography.captionSemibold(colors.onSurface)
                    : AppTypography.caption(context.mutedForeground),
              ),
            ),
            if (count != null)
              Text(
                '$count',
                style: AppTypography.caption(
                  context.mutedForeground.withValues(alpha: 0.6),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Web's "Hanya wishlist" pill above the rail — a filled toggle rather than a
/// checkbox, since it is the one filter people flip on and off repeatedly.
class _WishlistToggle extends StatelessWidget {
  const _WishlistToggle({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = active ? colors.onPrimary : context.mutedForeground;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? colors.primary : colors.secondary,
          border: Border.all(
            color: active ? colors.primary : context.borderColor,
          ),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.heart, size: 16, color: foreground),
            const SizedBox(width: 6),
            Text(
              'Hanya wishlist',
              style: AppTypography.captionSemibold(foreground),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the three catalog languages in the Bahasa row — the flag the rest
/// of the app marks prints with, over web's outlined toggle.
class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
    required this.language,
    required this.active,
    required this.onTap,
  });

  final CardLanguage language;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? colors.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border.all(
            color: active ? colors.primary : context.borderColor,
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CardLanguageBadge(language: language, size: 14),
            const SizedBox(width: 6),
            Text(
              language.shortLabel,
              style: active
                  ? AppTypography.captionSemibold(colors.onSurface)
                  : AppTypography.caption(context.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceField extends StatelessWidget {
  const _PriceField({required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: AppTypography.bodySm(context.appColors.onSurface),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTypography.bodySm(context.mutedForeground),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
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
            icon: LucideIcons.store,
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
            icon: LucideIcons.store,
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
