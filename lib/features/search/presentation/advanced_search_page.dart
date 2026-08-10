import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/pokemon_type.dart';
import '../../../shared/widgets/card_grid_item.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../usecase/search_notifier.dart';

/// Ports `app/advanced-search/advanced-search-client.tsx`, simplified into
/// one search bar instead of the web's separate simple/advanced search
/// entry points: the name search stays visible by default, with every
/// facet (Kelangkaan, Ekspansi, plus Kategori/Tipe/Evolusi/Subtipe/Regulasi
/// behind a "Filter Lanjutan" toggle) rendered as a compact dropdown button
/// — like web's `FilterDropdown` — instead of a wall of chips, so having
/// many options per facet doesn't overwhelm the screen.
class AdvancedSearchPage extends ConsumerStatefulWidget {
  const AdvancedSearchPage({super.key});

  @override
  ConsumerState<AdvancedSearchPage> createState() => _AdvancedSearchPageState();
}

class _AdvancedSearchPageState extends ConsumerState<AdvancedSearchPage> {
  bool _advancedOpen = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchNotifierProvider);
    final notifier = ref.read(searchNotifierProvider.notifier);
    final optionsAsync = ref.watch(searchFilterOptionsProvider);
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Pencarian Lanjutan')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                onChanged: notifier.setQuery,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Cari nama kartu...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: state.hasAnyFilter
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            notifier.reset();
                            setState(() => _advancedOpen = false);
                          },
                        )
                      : null,
                ),
              ),
            ),
            optionsAsync.when(
              data: (options) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () =>
                            setState(() => _advancedOpen = !_advancedOpen),
                        icon: Icon(
                          _advancedOpen
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 16,
                        ),
                        label: Text(
                          _advancedOpen ? 'Sembunyikan Filter' : 'Filter',
                        ),
                      ),
                    ),
                    if (_advancedOpen) ...[
                      TextField(
                        onChanged: notifier.setIllustrator,
                        decoration: const InputDecoration(
                          labelText: 'Ilustrator',
                          hintText: 'Cari ilustrator...',
                          prefixIcon: Icon(Icons.brush_outlined, size: 18),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _FilterDropdownButton<CardCategory>(
                            label: 'Kategori',
                            options: options.categories,
                            labelOf: (v) => v.labelId,
                            selectedOf: (s) => s.filters.categories,
                            onToggle: (n, v) => n.toggleCategory(v),
                          ),
                          _FilterDropdownButton<PokemonType>(
                            label: 'Tipe',
                            options: options.types,
                            labelOf: (v) => v.labelId,
                            selectedOf: (s) => s.filters.types,
                            onToggle: (n, v) => n.toggleType(v),
                          ),
                          _FilterDropdownButton<EvolutionStage>(
                            label: 'Evolusi',
                            options: options.evolutionStages,
                            labelOf: (v) => v.labelId,
                            selectedOf: (s) => s.filters.evolutionStages,
                            onToggle: (n, v) => n.toggleEvolutionStage(v),
                          ),
                          _FilterDropdownButton<TrainerSubtype>(
                            label: 'Subtipe',
                            options: options.trainerSubtypes,
                            labelOf: (v) => v.labelId,
                            selectedOf: (s) => s.filters.trainerSubtypes,
                            onToggle: (n, v) => n.toggleTrainerSubtype(v),
                          ),
                          _FilterDropdownButton<String>(
                            label: 'Regulasi',
                            options: options.regulationMarks,
                            labelOf: (v) => v,
                            selectedOf: (s) => s.filters.regulationMarks,
                            onToggle: (n, v) => n.toggleRegulationMark(v),
                          ),
                          _FilterDropdownButton<String>(
                            label: 'Kelangkaan',
                            options: options.rarities,
                            labelOf: (v) => v,
                            selectedOf: (s) => s.filters.rarities,
                            onToggle: (n, v) => n.toggleRarity(v),
                          ),
                          _FilterDropdownButton<String>(
                            label: 'Ekspansi',
                            options: options.packMarks,
                            labelOf: (v) => v,
                            selectedOf: (s) => s.packMarks,
                            onToggle: (n, v) => n.togglePackMark(v),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            Expanded(
              child: state.loading
                  ? const PikachuLoader()
                  : !state.hasSearched
                  ? EmptyState(
                      icon: Icons.travel_explore,
                      title: 'Mulai pencarian',
                      description:
                          'Gunakan kolom pencarian atau filter di atas untuk menemukan kartu.',
                    )
                  : state.results.isEmpty
                  ? const EmptyState(
                      icon: Icons.search_off,
                      title: 'Tidak ada hasil',
                      description: 'Coba kata kunci atau filter lain.',
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: state.results.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.62,
                          ),
                      itemBuilder: (context, i) {
                        final card = state.results[i];
                        return CardGridItem(
                          card: card,
                          onTap: () => context.push(
                            Routes.cardDetail(card.packSlug, card.id),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      backgroundColor: colors.surface,
    );
  }
}

/// A compact "label + active count + chevron" button that opens a
/// [_FilterDropdownSheet] — mirrors web's `FilterDropdown` but as a bottom
/// sheet instead of an anchored popover, which suits touch better than a
/// tiny floating panel.
class _FilterDropdownButton<T> extends StatelessWidget {
  const _FilterDropdownButton({
    required this.label,
    required this.options,
    required this.labelOf,
    required this.selectedOf,
    required this.onToggle,
  });

  final String label;
  final List<T> options;
  final String Function(T) labelOf;
  final Set<T> Function(SearchState) selectedOf;
  final void Function(SearchNotifier, T) onToggle;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    return Consumer(
      builder: (context, ref, _) {
        final selected = selectedOf(ref.watch(searchNotifierProvider));
        final colors = context.appColors;
        final active = selected.isNotEmpty;
        return InkWell(
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (context) => _FilterDropdownSheet<T>(
              label: label,
              options: options,
              labelOf: labelOf,
              selectedOf: selectedOf,
              onToggle: onToggle,
            ),
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: active
                  ? colors.primary.withValues(alpha: 0.1)
                  : Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(AppRadius.md),
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
                if (active) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${selected.length}',
                      style: AppTypography.badge(Colors.white),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: active ? colors.primary : context.mutedForeground,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FilterDropdownSheet<T> extends StatelessWidget {
  const _FilterDropdownSheet({
    required this.label,
    required this.options,
    required this.labelOf,
    required this.selectedOf,
    required this.onToggle,
  });

  final String label;
  final List<T> options;
  final String Function(T) labelOf;
  final Set<T> Function(SearchState) selectedOf;
  final void Function(SearchNotifier, T) onToggle;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(searchNotifierProvider);
          final notifier = ref.read(searchNotifierProvider.notifier);
          final selected = selectedOf(state);
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
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
                          label,
                          style: AppTypography.h3(context.appColors.onSurface),
                        ),
                      ),
                      if (selected.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            for (final option in [...selected]) {
                              onToggle(notifier, option);
                            }
                          },
                          child: const Text('Hapus semua'),
                        ),
                    ],
                  ),
                ),
                Divider(height: 1, color: context.borderColor),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      for (final option in options)
                        CheckboxListTile(
                          value: selected.contains(option),
                          onChanged: (_) => onToggle(notifier, option),
                          title: Text(labelOf(option)),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
