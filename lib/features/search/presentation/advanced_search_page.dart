import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/pokemon_type.dart';
import '../../../shared/utils/card_filtering.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_top_bar.dart';
import '../../expansions/presentation/expansions_page.dart';
import '../../../shared/widgets/card_grid_item.dart';
import '../../../shared/widgets/catalog_language_toggle.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/pokeball_icon.dart';
import '../../../shared/widgets/quantity_selector.dart';
import '../../../shared/widgets/type_icon.dart';
import '../../portfolio/presentation/widgets/portfolio_toggle.dart';
import '../../portfolio/usecase/portfolio_counter.dart';
import '../repository/models/advanced_search_query.dart';
import '../repository/search_repository.dart';
import '../usecase/search_notifier.dart';
import 'widgets/search_filter_controls.dart';

/// Ports `app/advanced-search/advanced-search-client.tsx` — the always-open
/// filter form above the result grid.
///
/// Field order follows the web form exactly: name and illustrator inputs,
/// then Kategori (categories and trainer subtypes share one control there,
/// so they share one here) / Tipe / Kelangkaan / Evolusi / Biaya Serangan /
/// Regulasi, then HP with Mundur and the combined Kelemahan & Resistansi
/// control, then Ekspansi, then Cari and Reset.
///
/// Behaviour matches too: editing a filter doesn't fire a request — the form
/// collects everything and searches on "Cari" — while changing the sort, the
/// ownership filter or the catalog language re-runs a search that already
/// happened. The web's anchored dropdown panels open as bottom sheets here,
/// the touch equivalent of a floating popover; the triggers themselves are
/// the same bordered pill with a count badge and chevron.
class AdvancedSearchPage extends ConsumerStatefulWidget {
  const AdvancedSearchPage({super.key, this.initialQuery});

  /// What the top bar's search field was holding when "Cari semua" was
  /// tapped. The form opens on that query and runs it, rather than making
  /// the user type it a second time.
  final String? initialQuery;

  @override
  ConsumerState<AdvancedSearchPage> createState() => _AdvancedSearchPageState();
}

/// How long the filter panel takes to arrive or leave. Long enough to be
/// read as a movement, short enough that a second tap is never waiting on it.
const _panelDuration = Duration(milliseconds: 220);

/// Identifies the panel among the three things that can occupy the body, so
/// the transition can tell which of them is the one that should travel.
const _panelKey = ValueKey('search-filter-panel');

class _AdvancedSearchPageState extends ConsumerState<AdvancedSearchPage> {
  /// Whether the filter panel is open. It starts closed: the reader arrives
  /// here to browse or to type, and a form covering the screen before either
  /// has happened is a question asked too early.
  bool _filtersOpen = false;

  @override
  void initState() {
    super.initState();
    // A `/search?q=` link fills the panel's name field and runs it — the
    // advanced search's own input, now that the bar above is quick search.
    final seed = widget.initialQuery?.trim();
    if (seed == null || seed.isEmpty) return;
    // After the frame: the notifier is read by a tree that is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(searchNotifierProvider.notifier);
      notifier.setQuery(seed);
      notifier.search();
    });
  }

  /// Whether the screen is answering a question rather than offering the
  /// catalog: anything set in the panel, its name field included — a search
  /// for "every Kelangkaan: SAR" carries no text at all.
  bool _isSearching(SearchState state) => state.hasAnyFilter;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchNotifierProvider);
    final notifier = ref.read(searchNotifierProvider.notifier);
    final optionsAsync = ref.watch(searchFilterOptionsProvider);
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppTopBar(
              // Beranda's quick search, suggestions and all — not wired to
              // the filters below. The two used to share one query, so typing
              // up here rewrote the panel's "Cari nama kartu" and a filtered
              // search could not be told apart from a typed one. The panel's
              // own name field is the advanced search's text input.
              trailing: _FilterToggle(
                open: _filtersOpen,
                duration: _panelDuration,
                // The dot is the panel's own answer to "is anything on?",
                // which matters most when the panel is shut and its contents
                // are the reason the grid looks the way it does.
                active: state.hasAnyFilter,
                onTap: () => setState(() => _filtersOpen = !_filtersOpen),
              ),
            ),
            Expanded(
              // The panel used to appear and vanish between frames, which
              // read as the page having been replaced rather than as
              // something having opened over it. It drops in from under the
              // button that opens it and lifts back out the same way, so the
              // two are visibly the same object.
              child: AnimatedSwitcher(
                duration: _panelDuration,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  // Only the panel travels. Sliding the catalog underneath it
                  // as well would read as two pages passing each other.
                  final incoming = child.key == _panelKey;
                  return FadeTransition(
                    opacity: animation,
                    child: incoming
                        ? SlideTransition(
                            position: Tween(
                              begin: const Offset(0, -0.04),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          )
                        : child,
                  );
                },
                layoutBuilder: (current, previous) => Stack(
                  // Top-aligned: centred, the shorter of the two crossfading
                  // children drifts vertically while it goes.
                  alignment: Alignment.topCenter,
                  children: [...previous, if (current != null) current],
                ),
                child: _filtersOpen
                    ? _FilterPanel(
                        key: _panelKey,
                        state: state,
                        notifier: notifier,
                        optionsAsync: optionsAsync,
                        onClose: () => setState(() => _filtersOpen = false),
                        onApplied: () => setState(() => _filtersOpen = false),
                      )
                    : _isSearching(state)
                    ? KeyedSubtree(
                        key: const ValueKey('results'),
                        child: _resultsView(context, state, notifier),
                      )
                    : const ExpansionsBrowser(key: ValueKey('expansions')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The results, in place of the expansions rather than under them. Showing
  /// both would leave the answer below a screenful of catalog the reader has
  /// just said they are not looking at.
  Widget _resultsView(
    BuildContext context,
    SearchState state,
    SearchNotifier notifier,
  ) {
    return CustomScrollView(
      slivers: [
        if (state.hasSearched && !state.loading && state.results.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: _ResultsHeader(state: state, notifier: notifier),
            ),
          ),
        ..._results(context, state, notifier),
      ],
    );
  }

  List<Widget> _results(
    BuildContext context,
    SearchState state,
    SearchNotifier notifier,
  ) {
    if (!state.hasSearched) {
      return [
        _placeholder(
          context,
          icon: LucideIcons.search,
          message: 'Atur filter lalu tekan Cari untuk menemukan kartu.',
        ),
      ];
    }
    if (state.loading) {
      return const [
        SliverFillRemaining(hasScrollBody: false, child: PikachuLoader()),
      ];
    }
    if (state.results.isEmpty) {
      return [
        _placeholder(
          context,
          icon: LucideIcons.searchX,
          message: 'Tidak ada kartu yang cocok dengan filter.',
        ),
      ];
    }
    final signedIn = ref.watch(authProvider).valueOrNull != null;

    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          AppBottomNav.reservedSpace(context) + 12,
        ),
        sliver: SliverCardGrid(
          extraChrome: signedIn ? cardGridItemFooterChrome : 0,
          hasVariant: (i) =>
              i < state.results.length && state.results[i].variantLabel != null,
          itemCount: state.results.length + (state.hasNext ? 1 : 0),
          itemBuilder: (context, i) {
            if (i >= state.results.length) {
              return LoadMoreTile(
                loading: state.loadingMore,
                onTap: notifier.loadMore,
              );
            }
            final card = state.results[i];
            return CardGridItem(
              card: card,
              onTap: () =>
                  context.push(Routes.cardDetail(card.packSlug, card.id)),
              // The expansion page's counter, counting into the portfolio
              // the header's switcher names. Signed out there is nowhere to
              // put a copy.
              footer: signedIn
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: QuantitySelector(
                        value: card.owned,
                        size: QuantitySelectorSize.sm,
                        onChanged: (next) => _setQuantity(notifier, card, next),
                      ),
                    )
                  : null,
            );
          },
        ),
      ),
    ];
  }

  /// One tap on a result's counter. The tile moves first and is put back if
  /// the save fails, so a quick second tap counts from the number on screen.
  Future<void> _setQuantity(
    SearchNotifier notifier,
    CardModel card,
    int next,
  ) async {
    notifier.setOwned(card.id, next);
    final error = await setPortfolioQuantity(ref, card, next);
    if (error == null || !mounted) return;
    notifier.setOwned(card.id, card.owned);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(error), persist: false));
  }

  Widget _placeholder(
    BuildContext context, {
    required IconData icon,
    required String message,
  }) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 44,
              color: context.mutedForeground.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterToggle extends StatelessWidget {
  const _FilterToggle({
    required this.open,
    required this.active,
    required this.onTap,
    this.duration = _panelDuration,
  });

  final bool open;
  final bool active;
  final VoidCallback onTap;

  /// Matched to the panel's own, so the button finishes turning into a close
  /// button exactly as the panel finishes arriving.
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      button: true,
      label: open ? 'Tutup filter pencarian' : 'Buka filter pencarian',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: open ? colors.onSurface : colors.primary,
                shape: BoxShape.circle,
              ),
              // The sliders become a cross by turning into it, which is what
              // says the button is still the same control in another state
              // rather than a different button that has appeared.
              child: AnimatedSwitcher(
                duration: duration,
                transitionBuilder: (child, animation) => RotationTransition(
                  turns: Tween(begin: 0.6, end: 1.0).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  open ? LucideIcons.x : LucideIcons.slidersHorizontal,
                  key: ValueKey(open),
                  size: 20,
                  // Paired with the fill rather than fixed white: open, the
                  // circle is `onSurface`, which dark mode turns near-white,
                  // and a white cross on it disappeared.
                  color: open ? colors.surface : colors.onPrimary,
                ),
              ),
            ),
            if (active && !open)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: context.appSemantic.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surface, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Filter Pencarian" — the advanced form, in the page rather than over it.
///
/// It takes the body's whole height while open, so the form is read on its
/// own instead of through a gap above the catalog. Closing it is the only
/// way back, which is why the toggle turns into an X and the header carries
/// one too.
class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    super.key,
    required this.state,
    required this.notifier,
    required this.optionsAsync,
    required this.onClose,
    required this.onApplied,
  });

  final SearchState state;
  final SearchNotifier notifier;
  final AsyncValue<SearchFilterOptions> optionsAsync;
  final VoidCallback onClose;
  final VoidCallback onApplied;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Filter Pencarian',
                    style: AppTypography.h3(colors.onSurface),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 18),
                  tooltip: 'Tutup',
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                AppBottomNav.reservedSpace(context) + 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        'Bahasa',
                        style: AppTypography.bodySmSemibold(colors.onSurface),
                      ),
                      const Spacer(),
                      const CatalogLanguageToggle(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _FilterForm(
                    state: state,
                    notifier: notifier,
                    optionsAsync: optionsAsync,
                    onSubmitted: onApplied,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bordered form card — web's `<form>`, field for field, but collapsed
/// to just the card-name field until the user opens the advanced section.
/// The web shows everything at once because it has the width for it; on a
/// phone the full form pushes the results off-screen.
class _FilterForm extends StatefulWidget {
  const _FilterForm({
    required this.state,
    required this.notifier,
    required this.optionsAsync,
    this.onSubmitted,
  });

  final SearchState state;
  final SearchNotifier notifier;
  final AsyncValue<SearchFilterOptions> optionsAsync;

  /// Fired once a search has actually been dispatched, so the panel that
  /// hosts the form can get out of the way of its own results.
  final VoidCallback? onSubmitted;

  @override
  State<_FilterForm> createState() => _FilterFormState();
}

class _FilterFormState extends State<_FilterForm> {
  /// Open from the start when the form is the whole screen.
  ///
  /// The collapse exists because this form used to sit above the results and
  /// would push them off the page. In the panel it *is* the page, so folding
  /// most of it away leaves a mostly empty screen and one more tap between
  /// the reader and the filter they came to set.
  late bool _expanded = widget.onSubmitted != null;

  SearchState get state => widget.state;
  SearchNotifier get notifier => widget.notifier;
  AsyncValue<SearchFilterOptions> get optionsAsync => widget.optionsAsync;

  @override
  Widget build(BuildContext context) {
    final query = state.query;
    // Never render an empty facet just because the server payload is
    // missing — same fallback chain `CardFilterBar` uses on the web.
    final options = resolveFilterOptions(
      fromServer: optionsAsync.valueOrNull,
      fromResults: state.results,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: context.borderColor),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SearchTextField(
            value: query.name,
            hint: 'Cari nama kartu...',
            prefix: const PokeballIcon(size: 18),
            onChanged: notifier.setQuery,
            onSubmitted: (_) => _submit(context),
          ),
          const SizedBox(height: 8),
          if (widget.onSubmitted == null)
            AdvancedFilterToggle(
              expanded: _expanded,
              activeCount: query.advancedCount,
              onToggle: () => setState(() => _expanded = !_expanded),
            ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            SearchTextField(
              value: query.illustrator,
              hint: 'Cari ilustrator...',
              prefix: Icon(
                LucideIcons.brush,
                size: 18,
                color: context.mutedForeground,
              ),
              onChanged: notifier.setIllustrator,
              onSubmitted: (_) => _submit(context),
            ),
            const SizedBox(height: 10),
            // The enum-backed facets always have entries, so a failed options
            // request is only worth mentioning when it left a facet empty.
            if (_missingFacets(options).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Consumer(
                  builder: (context, ref, _) => OptionsErrorRow(
                    message:
                        '${_missingFacets(options).join(' dan ')} belum tersedia '
                        '— daftarnya disiapkan di server.',
                    onRetry: () => ref.invalidate(searchFilterOptionsProvider),
                  ),
                ),
              ),
            _Grid(
              children: [
                FilterDropdownButton(
                  label: 'Kategori',
                  selectedCount:
                      query.filters.categories.length +
                      query.filters.trainerSubtypes.length,
                  options: [
                    for (final category in options.categories)
                      FilterOption(
                        label: category.labelId,
                        selected: query.filters.categories.contains(category),
                        onToggle: () => notifier.toggleCategory(category),
                      ),
                    for (final subtype in options.trainerSubtypes)
                      FilterOption(
                        label: subtype.labelId,
                        selected: query.filters.trainerSubtypes.contains(
                          subtype,
                        ),
                        onToggle: () => notifier.toggleTrainerSubtype(subtype),
                      ),
                  ],
                ),
                FilterDropdownButton(
                  label: 'Tipe',
                  selectedCount: query.filters.types.length,
                  options: [
                    for (final type in options.types)
                      FilterOption(
                        label: type.labelId,
                        leading: TypeIcon(type: type, size: 16),
                        selected: query.filters.types.contains(type),
                        onToggle: () => notifier.toggleType(type),
                      ),
                  ],
                ),
                FilterDropdownButton(
                  label: 'Kelangkaan',
                  selectedCount: query.filters.rarities.length,
                  options: [
                    for (final rarity in options.rarities)
                      FilterOption(
                        // `__none__` is how the RPC reports "no rarity mark".
                        label: rarity == '__none__' ? 'Tanpa tanda' : rarity,
                        selected: query.filters.rarities.contains(rarity),
                        onToggle: () => notifier.toggleRarity(rarity),
                      ),
                  ],
                ),
                FilterDropdownButton(
                  label: 'Evolusi',
                  selectedCount: query.filters.evolutionStages.length,
                  options: [
                    for (final stage in options.evolutionStages)
                      FilterOption(
                        label: stage.labelId,
                        selected: query.filters.evolutionStages.contains(stage),
                        onToggle: () => notifier.toggleEvolutionStage(stage),
                      ),
                  ],
                ),
                RangeControl(
                  label: 'Biaya Serangan',
                  min: 0,
                  max: 5,
                  valueMin: query.attackCostMin,
                  valueMax: query.attackCostMax,
                  onChanged: notifier.setAttackCostRange,
                ),
                FilterDropdownButton(
                  label: 'Regulasi',
                  selectedCount: query.filters.regulationMarks.length,
                  options: [
                    for (final mark in options.regulationMarks)
                      FilterOption(
                        label: mark,
                        selected: query.filters.regulationMarks.contains(mark),
                        onToggle: () => notifier.toggleRegulationMark(mark),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            HpRangeField(
              min: query.hpMin,
              max: query.hpMax,
              onChanged: notifier.setHpRange,
            ),
            const SizedBox(height: 8),
            _Grid(
              children: [
                RangeControl(
                  label: 'Mundur',
                  min: 0,
                  max: 5,
                  valueMin: query.retreatMin,
                  valueMax: query.retreatMax,
                  onChanged: notifier.setRetreatRange,
                ),
                TypeWeaknessResistanceControl(
                  types: options.types,
                  selectedWeakness: query.weaknessTypes,
                  selectedResistance: query.resistanceTypes,
                  onToggleWeakness: notifier.toggleWeaknessType,
                  onToggleResistance: notifier.toggleResistanceType,
                ),
              ],
            ),
            if (options.expansions.isNotEmpty) ...[
              const SizedBox(height: 8),
              ExpansionFilterControl(
                expansions: options.expansions,
                selected: query.packMarks,
                onToggle: notifier.togglePackMark,
                onToggleSeries: notifier.togglePackMarks,
              ),
            ],
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (state.hasAnyFilter) ...[
                OutlinedButton.icon(
                  onPressed: notifier.reset,
                  icon: const Icon(LucideIcons.refreshCw, size: 14),
                  label: const Text('Reset'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.appColors.error,
                    side: BorderSide(
                      color: context.appColors.error.withValues(alpha: 0.5),
                    ),
                    minimumSize: const Size(0, 38),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              ElevatedButton.icon(
                onPressed: !state.hasAnyFilter || state.loading
                    ? null
                    : () => _submit(context),
                icon: const Icon(LucideIcons.search, size: 16),
                label: const Text('Cari'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 38)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Facets with no fixed vocabulary, so an empty list is a real gap the
  /// user can see rather than something the fallback covers.
  List<String> _missingFacets(SearchFilterOptions options) {
    return [
      if (options.rarities.isEmpty) 'Kelangkaan',
      if (options.regulationMarks.isEmpty) 'Regulasi',
    ];
  }

  void _submit(BuildContext context) {
    if (!state.hasAnyFilter || state.loading) return;
    FocusScope.of(context).unfocus();
    notifier.search();
    widget.onSubmitted?.call();
  }
}

/// Two per row — the web grid is three columns wide, which would truncate
/// labels like "Biaya Serangan" at phone width.
class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final width = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

/// "N kartu ditemukan" with the ownership and sort controls.
class _ResultsHeader extends ConsumerWidget {
  const _ResultsHeader({required this.state, required this.notifier});

  final SearchState state;
  final SearchNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ownership asks the server "do I own this", so it needs a session.
    final signedIn = ref.watch(authProvider).valueOrNull != null;
    final found = state.total > 0 ? state.total : state.results.length;

    final row = Row(
      children: [
        Expanded(
          child: Text(
            '$found kartu ditemukan',
            style: AppTypography.caption(context.mutedForeground),
          ),
        ),
        if (signedIn) ...[
          SingleSelectButton<OwnershipFilter>(
            label: state.query.ownership == OwnershipFilter.all
                ? 'Koleksi'
                : state.query.ownership.labelId,
            active: state.query.ownership != OwnershipFilter.all,
            value: state.query.ownership,
            options: OwnershipFilter.values,
            labelOf: (v) => v.labelId,
            onSelected: notifier.setOwnership,
          ),
          const SizedBox(width: 8),
        ],
        SingleSelectButton<SearchSort>(
          label: state.query.sort.labelId,
          active: false,
          value: state.query.sort,
          options: SearchSort.values,
          labelOf: (v) => v.labelId,
          onSelected: notifier.setSort,
        ),
      ],
    );
    if (!signedIn) return row;

    // Which shelf the counters and the "Koleksi" filter answer for — the
    // expansion page's switcher, in the same place relative to its grid.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [const PortfolioToggle(), const SizedBox(height: 8), row],
    );
  }
}

/// Clearable text field matching web's `IconInput` in its search variant.
class SearchTextField extends StatefulWidget {
  const SearchTextField({
    super.key,
    required this.value,
    required this.hint,
    required this.prefix,
    required this.onChanged,
    this.onSubmitted,
  });

  final String value;
  final String hint;
  final Widget prefix;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<SearchTextField> createState() => _SearchTextFieldState();
}

class _SearchTextFieldState extends State<SearchTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(SearchTextField old) {
    super.didUpdateWidget(old);
    // Keeps the field in step when Reset clears the whole form.
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      // `typo-body-sm` with `py-2.5`, as web's `IconInput variant="search"`
      // is styled. Left on the shared form decoration these two stood 48
      // tall against the filter row's 37 — the theme's padding and default
      // 16pt text are sized for a form field, not for the search box sitting
      // directly above a row of filter chips.
      style: AppTypography.bodySm(context.appColors.onSurface),
      onChanged: (value) {
        widget.onChanged(value);
        // Rebuild so the clear button appears with the first character.
        setState(() {});
      },
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: AppTypography.bodySm(context.mutedForeground),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        prefixIcon: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
          child: widget.prefix,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.x, size: 16),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                  setState(() {});
                },
              ),
      ),
    );
  }
}

/// Inline HP min/max pair — the web renders this as one bordered group with
/// an "HP" chip on the left rather than a dropdown.
class HpRangeField extends StatelessWidget {
  const HpRangeField({
    super.key,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int? min;
  final int? max;
  final void Function(int? min, int? max) onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final active = min != null || max != null;

    return Container(
      decoration: BoxDecoration(
        color: active
            ? colors.primary.withValues(alpha: 0.08)
            : Theme.of(context).cardColor,
        border: Border.all(
          color: active
              ? colors.primary.withValues(alpha: 0.4)
              : context.borderColor,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            color: colors.secondary,
            child: Text(
              'HP',
              style: AppTypography.captionSemibold(context.mutedForeground),
            ),
          ),
          Expanded(
            child: _BareNumberField(
              hint: 'Min: 30',
              value: min,
              onChanged: (v) => onChanged(v, max),
            ),
          ),
          Text('-', style: AppTypography.caption(context.mutedForeground)),
          Expanded(
            child: _BareNumberField(
              hint: 'Max: 370',
              value: max,
              onChanged: (v) => onChanged(min, v),
            ),
          ),
        ],
      ),
    );
  }
}

class _BareNumberField extends StatefulWidget {
  const _BareNumberField({
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String hint;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  State<_BareNumberField> createState() => _BareNumberFieldState();
}

class _BareNumberFieldState extends State<_BareNumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value?.toString() ?? '',
  );

  @override
  void didUpdateWidget(_BareNumberField old) {
    super.didUpdateWidget(old);
    final incoming = widget.value?.toString() ?? '';
    if (widget.value != old.value && incoming != _controller.text) {
      _controller.text = incoming;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: AppTypography.caption(context.appColors.onSurface),
      onChanged: (value) =>
          widget.onChanged(value.isEmpty ? null : int.tryParse(value)),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: AppTypography.caption(context.mutedForeground),
        filled: false,
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 11),
      ),
    );
  }
}
