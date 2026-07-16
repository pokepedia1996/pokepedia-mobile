import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../repository/models/deck_card_entry.dart';
import '../usecase/portfolio_notifier.dart';

/// Ports `app/portfolio/deck/[id]/page.tsx` — `components/deck/deck-panel.tsx`.
class DeckDetailPage extends ConsumerWidget {
  const DeckDetailPage({super.key, required this.deckId});

  final int deckId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(deckCardsProvider(deckId));
    final decksAsync = ref.watch(decksProvider);
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(
        title: decksAsync.maybeWhen(
          data: (decks) {
            final deck = decks.where((d) => d.id == deckId).firstOrNull;
            return Text(deck?.name ?? 'Deck');
          },
          orElse: () => const Text('Deck'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: async.when(
          data: (entries) {
            final grouped = <DeckCategory, List<DeckCardEntry>>{};
            for (final entry in entries) {
              grouped.putIfAbsent(entry.category, () => []).add(entry);
            }
            final totalCards = entries.fold<int>(0, (s, e) => s + e.quantity);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '$totalCards / 60 kartu',
                  style: AppTypography.bodySm(context.mutedForeground),
                ),
                const SizedBox(height: 12),
                for (final category in DeckCategory.values)
                  if (grouped[category] != null) ...[
                    Text(
                      '${category.label} (${grouped[category]!.fold<int>(0, (s, e) => s + e.quantity)})',
                      style: AppTypography.h3(colors.onSurface),
                    ),
                    const SizedBox(height: 8),
                    for (final entry in grouped[category]!)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: colors.secondary,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${entry.quantity}',
                                style: AppTypography.captionSemibold(colors.onSurface),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                entry.card.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodySm(colors.onSurface),
                              ),
                            ),
                            Text(
                              entry.card.collectorNumber,
                              style: AppTypography.caption(context.mutedForeground),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('Gagal memuat deck')),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
