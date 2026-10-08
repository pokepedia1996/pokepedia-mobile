import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/catalog_language_provider.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/utils/card_filtering.dart';
import '../../../../shared/widgets/condition_grade_picker.dart';
import '../../../../shared/widgets/language_filter_chip.dart';
import '../../../../shared/widgets/wishlist_heart.dart';
import '../../usecase/market_notifier.dart';

/// Presents a market sheet the way `components/ui/sheet.tsx` does on web —
/// bottom-anchored, rounded, over the bottom nav (the root navigator, since a
/// sheet mounted on the shell branch would be clipped by it) and capped at
/// three quarters of the screen.
Future<void> showListingSheet(BuildContext context, Widget sheet) {
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
class ListingSheet extends StatelessWidget {
  const ListingSheet({required this.title, required this.child, this.footer});

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

/// Web's `TRAINER_SUBTYPE_ORDER` — the subtypes it lists first, spelled as
/// the catalog spells them, and what the section falls back to before the
/// facet counts arrive.
const _trainerSubtypeOrder = ['Item', 'Supporter', 'Stadium', 'Pokémon Tool'];

/// Web's `CATEGORY_LABELS` — the only category whose display name differs
/// from its stored value.
/// The one card type with something nested under it.
const _trainerType = 'Trainer';

/// Ports the mobile form of `StorefrontFilterRail` — the `embedded`,
/// `hideSort` rail web drops into its bottom sheet: section labels over
/// compact checkbox rows, Trainer's subtypes nested under a tri-state
/// parent, the condition grade pills, then the price range.
///
/// Unlike the web rail, which pushes every tick straight into the URL, the
/// sheet edits a draft and commits it on "Terapkan": the feed it filters is
/// behind the sheet, so applying live would just refetch out of sight.
class ListingFilterSheet extends ConsumerStatefulWidget {
  const ListingFilterSheet({
    super.key,
    required this.initial,
    required this.facets,
    required this.onApply,
    this.showWishlist = false,
    this.showHideBulk = false,
    this.showVerified = false,
    this.sortOptions = const [],
    this.initialSort = MarketSort.createdDesc,
  });

  /// The filters in force when the sheet opens; it edits a copy.
  final MarketFilters initial;

  /// Where the option lists and counts come from — the whole market's, or
  /// one store's. Watched, since they arrive a moment after the sheet does.
  final ProviderListenable<AsyncValue<ListingFacets>> facets;

  /// Called with the draft on "Terapkan", and the chosen sort when the sheet
  /// carries one.
  final void Function(MarketFilters filters, MarketSort sort) onApply;

  /// Market-only controls: a storefront is one seller, so "Terverifikasi"
  /// and the bulk switch narrow nothing there, and web leaves them off its
  /// storefront rail.
  final bool showWishlist;
  final bool showHideBulk;
  final bool showVerified;

  /// "Urutkan" as the sheet's first section, for a page with no sort button
  /// of its own. Empty hides it.
  final List<MarketSort> sortOptions;
  final MarketSort initialSort;

  @override
  ConsumerState<ListingFilterSheet> createState() => _ListingFilterSheetState();
}

class _ListingFilterSheetState extends ConsumerState<ListingFilterSheet> {
  late MarketFilters _draft;
  late MarketSort _sort = widget.initialSort;
  late final TextEditingController _minPriceController;
  late final TextEditingController _maxPriceController;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
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

  void _toggleCategory(String category) {
    setState(() {
      final categories = _toggled(_draft.categories, category);
      _draft = _draft.copyWith(
        categories: categories,
        // Dropping Trainer drops the subtypes hanging off it, the way
        // `handleCategoryChange` clears `tsub` on web.
        trainerSubtypes: categories.contains(_trainerType)
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
            ? ({..._draft.categories}..remove(_trainerType))
            : {..._draft.categories, _trainerType},
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
            : {..._draft.categories, _trainerType},
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
    widget.onApply(
      _draft.copyWith(minPrice: () => min, maxPrice: () => max),
      _sort,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Facets say what the tab actually holds. They arrive a moment after the
    // sheet does, so every group falls back to its fixed vocabulary until
    // then rather than flashing empty.
    final facets = ref.watch(widget.facets).valueOrNull ?? ListingFacets.empty;
    // No wishlist to filter by while signed out, so web hides the control
    // rather than offering one that cannot work.
    final signedIn = ref.watch(authProvider).valueOrNull != null;

    final subtypeOptions = _subtypeOptions(facets);
    final trainerSelected = _draft.categories.contains(_trainerType);
    // An empty subtype set means "every Trainer card", so it reads as fully
    // checked; a partial set is the tri-state's mixed mark.
    final trainerMixed =
        trainerSelected &&
        _draft.trainerSubtypes.isNotEmpty &&
        _draft.trainerSubtypes.length != subtypeOptions.length;

    return ListingSheet(
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
          if (widget.sortOptions.isNotEmpty)
            _FilterSection(
              label: 'Urutkan',
              children: [
                for (final sort in widget.sortOptions)
                  _FilterCheckRow(
                    label: sort.labelId,
                    checked: _sort == sort,
                    onTap: () => setState(() => _sort = sort),
                  ),
              ],
            ),
          if (signedIn && widget.showWishlist)
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
          if (widget.showHideBulk)
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
            label: 'Bahasa',
            children: [
              Row(
                children: [
                  for (final language in catalogLanguages) ...[
                    if (language != catalogLanguages.first)
                      const SizedBox(width: 6),
                    Expanded(
                      child: LanguageFilterChip(
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
            label: 'Tipe Kartu',
            children: [
              // Only the types the feed actually holds, in web's order —
              // `sortedCategoryFacets`. Listing a type with nothing behind it
              // offers a filter that can only empty the grid.
              for (final category in _cardTypeOptions(facets)) ...[
                if (category == _trainerType)
                  _FilterCheckRow(
                    label: marketCardTypeLabels[category] ?? category,
                    checked: trainerSelected,
                    mixed: trainerMixed,
                    count: facets.categories.countOf(category),
                    onTap: () =>
                        _toggleTrainerAll(trainerSelected, subtypeOptions),
                  )
                else
                  _FilterCheckRow(
                    label: marketCardTypeLabels[category] ?? category,
                    checked: _draft.categories.contains(category),
                    count: facets.categories.countOf(category),
                    onTap: () => _toggleCategory(category),
                  ),
                if (category == _trainerType)
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
          if (widget.showVerified)
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
  /// Web's `sortedCategoryFacets`: the types the feed holds, in
  /// [marketCardTypes] order, with anything unrecognised kept on the end
  /// rather than dropped — a new catalog category should show up here
  /// without a release.
  List<String> _cardTypeOptions(ListingFacets facets) {
    final present = {for (final item in facets.categories) item.value};
    return [
      for (final type in marketCardTypes)
        if (present.contains(type)) type,
      for (final item in facets.categories)
        if (!marketCardTypes.contains(item.value)) item.value,
    ];
  }

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
            WishlistHeart(active: active, size: 16, color: foreground),
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
