import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../models/card_model.dart';
import '../models/pokemon_type.dart';
import '../utils/card_filtering.dart';
import 'type_icon.dart';

/// Ports `components/card/card-filters.tsx` + `SortDropdown` +
/// `ViewToggle` — the search box, facet filter chips, sort picker and
/// grid/list toggle shown above a card grid.
class CardFilterBar extends StatefulWidget {
  const CardFilterBar({
    super.key,
    required this.cards,
    required this.filters,
    required this.onFiltersChanged,
    required this.sortBy,
    required this.onSortChanged,
    required this.viewMode,
    required this.onViewModeChanged,
    this.ownershipFilter,
    this.onOwnershipChanged,
  });

  final List<CardModel> cards;
  final CardFilters filters;
  final ValueChanged<CardFilters> onFiltersChanged;
  final CardSortOption sortBy;
  final ValueChanged<CardSortOption> onSortChanged;
  final CardViewMode viewMode;
  final ValueChanged<CardViewMode> onViewModeChanged;

  /// Only shown when non-null — mirrors the web only rendering the
  /// "Koleksi" facet for signed-in users.
  final OwnershipFilter? ownershipFilter;
  final ValueChanged<OwnershipFilter>? onOwnershipChanged;

  @override
  State<CardFilterBar> createState() => _CardFilterBarState();
}

class _CardFilterBarState extends State<CardFilterBar> {
  bool _panelOpen = false;

  @override
  Widget build(BuildContext context) {
    final options = deriveCardFilterOptions(widget.cards);
    final ownershipActive =
        widget.ownershipFilter != null && widget.ownershipFilter != OwnershipFilter.all;
    final activeCount = widget.filters.activeCount + (ownershipActive ? 1 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SearchField(
          value: widget.filters.search,
          onChanged: (v) => widget.onFiltersChanged(widget.filters.copyWith(search: v)),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _FilterToggleButton(
              activeCount: activeCount,
              open: _panelOpen,
              onTap: () => setState(() => _panelOpen = !_panelOpen),
            ),
            const Spacer(),
            _SortButton(sortBy: widget.sortBy, onChanged: widget.onSortChanged),
            const SizedBox(width: 8),
            _ViewToggle(value: widget.viewMode, onChanged: widget.onViewModeChanged),
          ],
        ),
        if (_panelOpen) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ChipSection<CardCategory>(
                  label: 'Kategori',
                  options: options.categories,
                  selected: widget.filters.categories,
                  labelOf: (v) => v.labelId,
                  onToggle: (v) => widget.onFiltersChanged(
                    widget.filters.copyWith(categories: _toggled(widget.filters.categories, v)),
                  ),
                ),
                _ChipSection<PokemonType>(
                  label: 'Tipe',
                  options: options.types,
                  selected: widget.filters.types,
                  labelOf: (v) => v.labelId,
                  iconOf: (v) => TypeIcon(type: v, size: 16),
                  onToggle: (v) => widget.onFiltersChanged(
                    widget.filters.copyWith(types: _toggled(widget.filters.types, v)),
                  ),
                ),
                _ChipSection<String>(
                  label: 'Kelangkaan',
                  options: options.rarities,
                  selected: widget.filters.rarities,
                  labelOf: (v) => v,
                  onToggle: (v) => widget.onFiltersChanged(
                    widget.filters.copyWith(rarities: _toggled(widget.filters.rarities, v)),
                  ),
                ),
                if (options.evolutionStages.isNotEmpty)
                  _ChipSection<EvolutionStage>(
                    label: 'Evolusi',
                    options: options.evolutionStages,
                    selected: widget.filters.evolutionStages,
                    labelOf: (v) => v.labelId,
                    onToggle: (v) => widget.onFiltersChanged(
                      widget.filters.copyWith(
                        evolutionStages: _toggled(widget.filters.evolutionStages, v),
                      ),
                    ),
                  ),
                if (options.trainerSubtypes.isNotEmpty)
                  _ChipSection<TrainerSubtype>(
                    label: 'Subtipe',
                    options: options.trainerSubtypes,
                    selected: widget.filters.trainerSubtypes,
                    labelOf: (v) => v.labelId,
                    onToggle: (v) => widget.onFiltersChanged(
                      widget.filters.copyWith(
                        trainerSubtypes: _toggled(widget.filters.trainerSubtypes, v),
                      ),
                    ),
                  ),
                if (options.regulationMarks.isNotEmpty)
                  _ChipSection<String>(
                    label: 'Regulasi',
                    options: options.regulationMarks,
                    selected: widget.filters.regulationMarks,
                    labelOf: (v) => v,
                    onToggle: (v) => widget.onFiltersChanged(
                      widget.filters.copyWith(
                        regulationMarks: _toggled(widget.filters.regulationMarks, v),
                      ),
                    ),
                  ),
                if (widget.onOwnershipChanged != null)
                  _ChipSection<OwnershipFilter>(
                    label: 'Koleksi',
                    options: const [OwnershipFilter.owned, OwnershipFilter.notOwned],
                    selected: {
                      if (widget.ownershipFilter != null &&
                          widget.ownershipFilter != OwnershipFilter.all)
                        widget.ownershipFilter!,
                    },
                    labelOf: (v) => v == OwnershipFilter.owned ? 'Dimiliki' : 'Belum Dimiliki',
                    onToggle: (v) => widget.onOwnershipChanged!(
                      widget.ownershipFilter == v ? OwnershipFilter.all : v,
                    ),
                  ),
                if (activeCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          widget.onFiltersChanged(widget.filters.clearedKeepingSearch());
                          widget.onOwnershipChanged?.call(OwnershipFilter.all);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.appColors.error,
                          side: BorderSide(color: context.appColors.error.withValues(alpha: 0.4)),
                        ),
                        icon: const Icon(Icons.close, size: 14),
                        label: Text('Hapus filter ($activeCount)'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Set<T> _toggled<T>(Set<T> current, T value) {
    final next = {...current};
    if (!next.add(value)) next.remove(value);
    return next;
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Cari nama, nomor, atau ilustrator...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: widget.value.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                },
              )
            : null,
      ),
    );
  }
}

class _FilterToggleButton extends StatelessWidget {
  const _FilterToggleButton({required this.activeCount, required this.open, required this.onTap});

  final int activeCount;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final active = activeCount > 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? colors.primary.withValues(alpha: 0.1) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: active ? colors.primary.withValues(alpha: 0.4) : context.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list, size: 16, color: active ? colors.primary : context.mutedForeground),
            const SizedBox(width: 6),
            Text(
              'Filter',
              style: AppTypography.captionSemibold(active ? colors.primary : context.mutedForeground),
            ),
            if (active) ...[
              const SizedBox(width: 6),
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
                child: Text('$activeCount', style: AppTypography.badge(Colors.white)),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 16,
              color: active ? colors.primary : context.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.sortBy, required this.onChanged});

  final CardSortOption sortBy;
  final ValueChanged<CardSortOption> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<CardSortOption>(
      initialValue: sortBy,
      onSelected: onChanged,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      itemBuilder: (context) => [
        for (final option in CardSortOption.values)
          PopupMenuItem(
            value: option,
            child: Row(
              children: [
                if (option == sortBy)
                  Icon(Icons.check, size: 16, color: context.appColors.primary)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Text(option.label),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(sortBy.label, style: AppTypography.captionSemibold(context.mutedForeground)),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, size: 16, color: context.mutedForeground),
          ],
        ),
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.value, required this.onChanged});

  final CardViewMode value;
  final ValueChanged<CardViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ViewToggleButton(
            icon: Icons.grid_view_rounded,
            selected: value == CardViewMode.grid,
            onTap: () => onChanged(CardViewMode.grid),
          ),
          _ViewToggleButton(
            icon: Icons.view_list_rounded,
            selected: value == CardViewMode.list,
            onTap: () => onChanged(CardViewMode.list),
          ),
        ],
      ),
    );
  }
}

class _ViewToggleButton extends StatelessWidget {
  const _ViewToggleButton({required this.icon, required this.selected, required this.onTap});

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        color: selected ? colors.primary : Theme.of(context).cardColor,
        child: Icon(icon, size: 18, color: selected ? colors.onPrimary : context.mutedForeground),
      ),
    );
  }
}

class _ChipSection<T> extends StatelessWidget {
  const _ChipSection({
    required this.label,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onToggle,
    this.iconOf,
  });

  final String label;
  final List<T> options;
  final Set<T> selected;
  final String Function(T) labelOf;
  final Widget Function(T)? iconOf;
  final ValueChanged<T> onToggle;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.overline(context.mutedForeground)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                _Chip(
                  label: labelOf(option),
                  icon: iconOf?.call(option),
                  selected: selected.contains(option),
                  onTap: () => onToggle(option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final Widget? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.secondary,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: selected ? colors.primary : context.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 6)],
            Text(
              label,
              style: AppTypography.caption(selected ? colors.onPrimary : colors.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
