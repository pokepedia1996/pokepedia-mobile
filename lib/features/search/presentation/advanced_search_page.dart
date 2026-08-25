import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/pokemon_type.dart';
import '../../../shared/utils/card_filtering.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/card_grid_item.dart';
import '../../../shared/widgets/catalog_language_toggle.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/pokeball_icon.dart';
import '../../../shared/widgets/type_icon.dart';
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
class AdvancedSearchPage extends ConsumerWidget {
  const AdvancedSearchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchNotifierProvider);
    final notifier = ref.read(searchNotifierProvider.notifier);
    final optionsAsync = ref.watch(searchFilterOptionsProvider);
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pencarian Detail',
                                style: AppTypography.h2(colors.onSurface),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Cari kartu berdasarkan berbagai kriteria',
                                style: AppTypography.bodySm(
                                  context.mutedForeground,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        const CatalogLanguageToggle(),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _FilterForm(
                      state: state,
                      notifier: notifier,
                      optionsAsync: optionsAsync,
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
            if (state.hasSearched && !state.loading && state.results.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: _ResultsHeader(state: state, notifier: notifier),
                ),
              ),
            ..._results(context, state, notifier),
          ],
        ),
      ),
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
          icon: Icons.search,
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
          icon: Icons.search_off,
          message: 'Tidak ada kartu yang cocok dengan filter.',
        ),
      ];
    }

    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          AppBottomNav.reservedSpace(context) + 12,
        ),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.62,
          ),
          delegate: SliverChildBuilderDelegate((context, i) {
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
            );
          }, childCount: state.results.length + (state.hasNext ? 1 : 0)),
        ),
      ),
    ];
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

/// The bordered form card — web's `<form>`, field for field, but collapsed
/// to just the card-name field until the user opens the advanced section.
/// The web shows everything at once because it has the width for it; on a
/// phone the full form pushes the results off-screen.
class _FilterForm extends StatefulWidget {
  const _FilterForm({
    required this.state,
    required this.notifier,
    required this.optionsAsync,
  });

  final SearchState state;
  final SearchNotifier notifier;
  final AsyncValue<SearchFilterOptions> optionsAsync;

  @override
  State<_FilterForm> createState() => _FilterFormState();
}

class _FilterFormState extends State<_FilterForm> {
  bool _expanded = false;

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
                Icons.brush_outlined,
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
                  icon: const Icon(Icons.refresh, size: 14),
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
                icon: const Icon(Icons.search, size: 16),
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

    return Row(
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
      onChanged: (value) {
        widget.onChanged(value);
        // Rebuild so the clear button appears with the first character.
        setState(() {});
      },
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        hintText: widget.hint,
        isDense: true,
        prefixIcon: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
          child: widget.prefix,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 16),
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
