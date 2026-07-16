import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/card_grid_item.dart';
import '../../../shared/widgets/empty_state.dart';
import '../usecase/search_notifier.dart';

/// Ports `app/advanced-search/advanced-search-client.tsx`.
class AdvancedSearchPage extends ConsumerWidget {
  const AdvancedSearchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                          onPressed: notifier.reset,
                        )
                      : null,
                ),
              ),
            ),
            optionsAsync.when(
              data: (options) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kelangkaan',
                      style: AppTypography.overline(context.mutedForeground),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final rarity in options.rarities)
                          _FilterChip(
                            label: rarity,
                            selected: state.selectedRarities.contains(rarity),
                            onTap: () => notifier.toggleRarity(rarity),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Ekspansi',
                      style: AppTypography.overline(context.mutedForeground),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final mark in options.packMarks)
                          _FilterChip(
                            label: mark,
                            selected: state.selectedPackMarks.contains(mark),
                            onTap: () => notifier.togglePackMark(mark),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: state.loading
                  ? const Center(child: CircularProgressIndicator())
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
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
          border: Border.all(
            color: selected ? colors.primary : context.borderColor,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.caption(
            selected ? colors.onPrimary : colors.onSurface,
          ),
        ),
      ),
    );
  }
}
