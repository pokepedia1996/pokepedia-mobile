import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../shared/widgets/app_search_field.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/pokemon_type.dart';
import '../../../../shared/widgets/type_icon.dart';
import '../../repository/search_repository.dart';

/// Collapses everything except the card-name field, which is the one filter
/// most searches only need. Carries the number of advanced facets currently
/// set, so a collapsed form still shows that it's filtering.
class AdvancedFilterToggle extends StatelessWidget {
  const AdvancedFilterToggle({
    super.key,
    required this.expanded,
    required this.activeCount,
    required this.onToggle,
  });

  final bool expanded;
  final int activeCount;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final active = activeCount > 0;

    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
        child: Row(
          children: [
            Icon(
              LucideIcons.slidersHorizontal,
              size: 18,
              color: active ? colors.primary : context.mutedForeground,
            ),
            const SizedBox(width: 8),
            Text(
              'Filter Lanjutan',
              style: AppTypography.bodySmSemibold(
                active ? colors.primary : colors.onSurface,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  '$activeCount',
                  style: AppTypography.badge(colors.onPrimary),
                ),
              ),
            ],
            const Spacer(),
            Icon(
              expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: 18,
              color: context.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

/// One entry in a [FilterDropdownButton]. Carrying its own toggle lets a
/// single control mix differently-typed facets — the web's "Kategori"
/// dropdown holds both categories and trainer subtypes.
class FilterOption {
  const FilterOption({
    required this.label,
    required this.selected,
    required this.onToggle,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback onToggle;
  final Widget? leading;
}

/// Ports `FilterDropdown`: a bordered pill that turns primary-tinted with a
/// count badge once something is picked. The web anchors its option list as
/// a floating panel; on touch that becomes a bottom sheet.
class FilterDropdownButton extends StatelessWidget {
  const FilterDropdownButton({
    super.key,
    required this.label,
    required this.options,
    required this.selectedCount,
  });

  final String label;
  final List<FilterOption> options;
  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    return FilterTrigger(
      label: label,
      activeLabel: selectedCount > 0 ? '$selectedCount' : null,
      onTap: options.isEmpty
          ? null
          : () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Theme.of(context).cardColor,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppRadius.xl),
                ),
              ),
              builder: (_) => _OptionSheet(label: label, options: options),
            ),
    );
  }
}

/// The shared trigger shape behind every facet control, so they line up
/// whatever they open.
class FilterTrigger extends StatelessWidget {
  const FilterTrigger({
    super.key,
    required this.label,
    required this.onTap,
    this.activeLabel,
    this.open = false,
  });

  final String label;
  final VoidCallback? onTap;

  /// Text for the badge — a count, or a range like "1 – 3".
  final String? activeLabel;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final active = activeLabel != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: active
              ? colors.primary.withValues(alpha: 0.1)
              : Theme.of(context).cardColor,
          border: Border.all(
            color: active
                ? colors.primary.withValues(alpha: 0.4)
                : context.borderColor,
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.captionSemibold(
                  active ? colors.primary : context.mutedForeground,
                ),
              ),
            ),
            if (active) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  activeLabel!,
                  style: AppTypography.badge(colors.onPrimary),
                ),
              ),
            ],
            Icon(
              open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: 14,
              color: active ? colors.primary : context.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

/// Checkable option list, the sheet form of web's dropdown panel.
class _OptionSheet extends StatefulWidget {
  const _OptionSheet({required this.label, required this.options});

  final String label;
  final List<FilterOption> options;

  @override
  State<_OptionSheet> createState() => _OptionSheetState();
}

class _OptionSheetState extends State<_OptionSheet> {
  /// The sheet sits in its own route, so it never rebuilds from the parent
  /// while it's open — the checkboxes have to track their own state or they
  /// would stay frozen at whatever was selected when it opened.
  late final Set<int> _selected = {
    for (var i = 0; i < widget.options.length; i++)
      if (widget.options[i].selected) i,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.label,
                      style: AppTypography.h3(colors.onSurface),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: widget.options.length,
                itemBuilder: (context, i) {
                  final option = widget.options[i];
                  return CheckboxListTile(
                    value: _selected.contains(i),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (_) {
                      option.onToggle();
                      setState(() {
                        if (!_selected.add(i)) _selected.remove(i);
                      });
                    },
                    title: Row(
                      children: [
                        if (option.leading != null) ...[
                          option.leading!,
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            option.label,
                            style: AppTypography.bodySm(colors.onSurface),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ports `RangeSlider` from `components/ui/range-slider.tsx` — a trigger
/// showing "lo – hi" that expands to a two-thumb slider. Kept inline rather
/// than in a sheet, since the web panel drops directly under the button.
class RangeControl extends StatefulWidget {
  const RangeControl({
    super.key,
    required this.label,
    required this.min,
    required this.max,
    required this.valueMin,
    required this.valueMax,
    required this.onChanged,
  });

  final String label;
  final int min;
  final int max;
  final int? valueMin;
  final int? valueMax;
  final void Function(int? min, int? max) onChanged;

  @override
  State<RangeControl> createState() => _RangeControlState();
}

class _RangeControlState extends State<RangeControl> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final lo = widget.valueMin ?? widget.min;
    final hi = widget.valueMax ?? widget.max;
    final active = widget.valueMin != null || widget.valueMax != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterTrigger(
          label: widget.label,
          activeLabel: active ? '$lo – $hi' : null,
          open: _open,
          onTap: () => setState(() {
            // Opening an untouched slider seeds it with the full range, the
            // same nudge the web button gives.
            if (!_open && !active) {
              widget.onChanged(widget.min, widget.max);
            }
            _open = !_open;
          }),
        ),
        if (_open)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border.all(color: context.borderColor),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      '${widget.min}',
                      style: AppTypography.badge(context.mutedForeground),
                    ),
                    Expanded(
                      child: RangeSlider(
                        values: RangeValues(lo.toDouble(), hi.toDouble()),
                        min: widget.min.toDouble(),
                        max: widget.max.toDouble(),
                        divisions: widget.max - widget.min,
                        labels: RangeLabels('$lo', '$hi'),
                        activeColor: colors.primary,
                        onChanged: (values) => widget.onChanged(
                          values.start.round(),
                          values.end.round(),
                        ),
                      ),
                    ),
                    Text(
                      '${widget.max}',
                      style: AppTypography.badge(context.mutedForeground),
                    ),
                  ],
                ),
                if (active)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        widget.onChanged(null, null);
                        setState(() => _open = false);
                      },
                      child: Text(
                        'Hapus',
                        style: AppTypography.caption(colors.error),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Ports `TypeWRFilter` — one control covering both weakness and resistance,
/// with a W and an R toggle on every type row.
class TypeWeaknessResistanceControl extends StatelessWidget {
  const TypeWeaknessResistanceControl({
    super.key,
    required this.types,
    required this.selectedWeakness,
    required this.selectedResistance,
    required this.onToggleWeakness,
    required this.onToggleResistance,
  });

  final List<PokemonType> types;
  final Set<PokemonType> selectedWeakness;
  final Set<PokemonType> selectedResistance;
  final ValueChanged<PokemonType> onToggleWeakness;
  final ValueChanged<PokemonType> onToggleResistance;

  @override
  Widget build(BuildContext context) {
    final count = selectedWeakness.length + selectedResistance.length;

    return FilterTrigger(
      label: 'Kelemahan & Resistansi',
      activeLabel: count > 0 ? '$count' : null,
      onTap: types.isEmpty
          ? null
          : () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Theme.of(context).cardColor,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppRadius.xl),
                ),
              ),
              builder: (_) => _TypeWRSheet(
                types: types,
                selectedWeakness: selectedWeakness,
                selectedResistance: selectedResistance,
                onToggleWeakness: onToggleWeakness,
                onToggleResistance: onToggleResistance,
              ),
            ),
    );
  }
}

class _TypeWRSheet extends StatefulWidget {
  const _TypeWRSheet({
    required this.types,
    required this.selectedWeakness,
    required this.selectedResistance,
    required this.onToggleWeakness,
    required this.onToggleResistance,
  });

  final List<PokemonType> types;
  final Set<PokemonType> selectedWeakness;
  final Set<PokemonType> selectedResistance;
  final ValueChanged<PokemonType> onToggleWeakness;
  final ValueChanged<PokemonType> onToggleResistance;

  @override
  State<_TypeWRSheet> createState() => _TypeWRSheetState();
}

class _TypeWRSheetState extends State<_TypeWRSheet> {
  late final Set<PokemonType> _weakness = {...widget.selectedWeakness};
  late final Set<PokemonType> _resistance = {...widget.selectedResistance};

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Kelemahan & Resistansi',
                      style: AppTypography.h3(colors.onSurface),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Row(
                children: [
                  const Spacer(),
                  SizedBox(
                    width: 34,
                    child: Text(
                      'W',
                      textAlign: TextAlign.center,
                      style: AppTypography.badge(colors.error),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 34,
                    child: Text(
                      'R',
                      textAlign: TextAlign.center,
                      style: AppTypography.badge(context.appSemantic.bid),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                itemCount: widget.types.length,
                itemBuilder: (context, i) {
                  final type = widget.types[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        TypeIcon(type: type, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            type.labelId,
                            style: AppTypography.bodySm(colors.onSurface),
                          ),
                        ),
                        _WRButton(
                          letter: 'W',
                          selected: _weakness.contains(type),
                          color: colors.error,
                          onTap: () {
                            widget.onToggleWeakness(type);
                            setState(() {
                              if (!_weakness.add(type)) _weakness.remove(type);
                            });
                          },
                        ),
                        const SizedBox(width: 6),
                        _WRButton(
                          letter: 'R',
                          selected: _resistance.contains(type),
                          color: context.appSemantic.bid,
                          onTap: () {
                            widget.onToggleResistance(type);
                            setState(() {
                              if (!_resistance.add(type)) {
                                _resistance.remove(type);
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WRButton extends StatelessWidget {
  const _WRButton({
    required this.letter,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String letter;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        width: 34,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color : context.appColors.secondary,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          letter,
          style: AppTypography.badge(
            selected ? Colors.white : context.mutedForeground,
          ),
        ),
      ),
    );
  }
}

/// Ports `ExpansionFilter` — expansions grouped by series, searchable, with
/// a select-all row per series and the set symbol beside each entry.
class ExpansionFilterControl extends StatelessWidget {
  const ExpansionFilterControl({
    super.key,
    required this.expansions,
    required this.selected,
    required this.onToggle,
    required this.onToggleSeries,
  });

  final List<SearchExpansionOption> expansions;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final ValueChanged<List<String>> onToggleSeries;

  @override
  Widget build(BuildContext context) {
    return FilterTrigger(
      label: 'Ekspansi',
      activeLabel: selected.isEmpty ? null : '${selected.length}',
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).cardColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
        builder: (_) => _ExpansionSheet(
          expansions: expansions,
          selected: selected,
          onToggle: onToggle,
          onToggleSeries: onToggleSeries,
        ),
      ),
    );
  }
}

class _ExpansionSheet extends StatefulWidget {
  const _ExpansionSheet({
    required this.expansions,
    required this.selected,
    required this.onToggle,
    required this.onToggleSeries,
  });

  final List<SearchExpansionOption> expansions;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final ValueChanged<List<String>> onToggleSeries;

  @override
  State<_ExpansionSheet> createState() => _ExpansionSheetState();
}

class _ExpansionSheetState extends State<_ExpansionSheet> {
  late final Set<String> _selected = {...widget.selected};
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final query = _search.trim().toLowerCase();

    // Grouped by series, keeping the release order the query returned.
    final groups = <String, List<SearchExpansionOption>>{};
    for (final expansion in widget.expansions) {
      if (query.isNotEmpty &&
          !expansion.name.toLowerCase().contains(query) &&
          !expansion.code.toLowerCase().contains(query)) {
        continue;
      }
      groups.putIfAbsent(expansion.series, () => []).add(expansion);
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ekspansi',
                        style: AppTypography.h3(colors.onSurface),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(LucideIcons.x, size: 20),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: AppSearchField(
                  hintText: 'Cari ekspansi...',
                  onChanged: (value) => setState(() => _search = value),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  children: [
                    for (final entry in groups.entries) ...[
                      _SeriesHeaderRow(
                        series: entry.key,
                        codes: entry.value.map((e) => e.code).toList(),
                        selected: _selected,
                        onToggleSeries: (codes) {
                          widget.onToggleSeries(codes);
                          setState(() {
                            final all = codes.every(_selected.contains);
                            for (final code in codes) {
                              all
                                  ? _selected.remove(code)
                                  : _selected.add(code);
                            }
                          });
                        },
                      ),
                      for (final expansion in entry.value)
                        _ExpansionRow(
                          expansion: expansion,
                          selected: _selected.contains(expansion.code),
                          onToggle: () {
                            widget.onToggle(expansion.code);
                            setState(() {
                              if (!_selected.add(expansion.code)) {
                                _selected.remove(expansion.code);
                              }
                            });
                          },
                        ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeriesHeaderRow extends StatelessWidget {
  const _SeriesHeaderRow({
    required this.series,
    required this.codes,
    required this.selected,
    required this.onToggleSeries,
  });

  final String series;
  final List<String> codes;
  final Set<String> selected;
  final ValueChanged<List<String>> onToggleSeries;

  @override
  Widget build(BuildContext context) {
    final allSelected = codes.every(selected.contains);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              series,
              style: AppTypography.overline(context.mutedForeground),
            ),
          ),
          TextButton(
            onPressed: () => onToggleSeries(codes),
            child: Text(
              allSelected ? 'Hapus semua' : 'Pilih semua',
              style: AppTypography.caption(context.appColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpansionRow extends StatelessWidget {
  const _ExpansionRow({
    required this.expansion,
    required this.selected,
    required this.onToggle,
  });

  final SearchExpansionOption expansion;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: selected,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (_) => onToggle(),
              ),
            ),
            const SizedBox(width: 10),
            if (expansion.symbolUrl != null) ...[
              SvgPicture.network(
                expansion.symbolUrl!,
                height: 16,
                width: 16,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(width: 16),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                expansion.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySm(colors.onSurface),
              ),
            ),
            Text(
              expansion.code.toUpperCase(),
              style: AppTypography.caption(context.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single-select popup for sort and ownership.
class SingleSelectButton<T> extends StatelessWidget {
  const SingleSelectButton({
    super.key,
    required this.label,
    required this.active,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onSelected,
  });

  final String label;
  final bool active;
  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: context.borderColor),
      ),
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem(
            value: option,
            height: 42,
            child: Row(
              children: [
                if (option == value)
                  Icon(LucideIcons.check, size: 16, color: colors.primary)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Text(
                  labelOf(option),
                  style: AppTypography.bodySm(colors.onSurface),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? colors.primary.withValues(alpha: 0.1)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: active
                ? colors.primary.withValues(alpha: 0.4)
                : context.borderColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTypography.captionSemibold(
                active ? colors.primary : context.mutedForeground,
              ),
            ),
            Icon(
              LucideIcons.chevronDown,
              size: 14,
              color: active ? colors.primary : context.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown only when a source failing actually costs the user a facet.
///
/// Every enum-backed facet falls back to the app's own vocabulary, so a
/// failed options request usually leaves the form completely usable — in
/// that case there is nothing worth interrupting for. This stays muted
/// rather than red for the same reason: it reports two missing lists, not a
/// broken page, and nothing the user does in the app can fix it.
class OptionsErrorRow extends StatelessWidget {
  const OptionsErrorRow({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: context.appColors.secondary.withValues(alpha: 0.5),
        border: Border.all(color: context.borderColor),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 14, color: context.mutedForeground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTypography.caption(context.mutedForeground),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'Coba lagi',
              style: AppTypography.caption(context.appColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Occupies the last grid cell so paging needs no separate footer.
class LoadMoreTile extends StatelessWidget {
  const LoadMoreTile({super.key, required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: context.borderColor),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                'Muat lebih\nbanyak',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmSemibold(context.appColors.primary),
              ),
      ),
    );
  }
}
