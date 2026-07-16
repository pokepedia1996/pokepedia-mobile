import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/card_grid_item.dart';
import '../../../shared/widgets/pokeball_icon.dart';
import '../usecase/expansions_notifier.dart';

/// Ports `app/expansions/[packSlug]/pack-detail-client.tsx` — the card grid
/// for a single expansion.
class PackDetailPage extends ConsumerWidget {
  const PackDetailPage({super.key, required this.packSlug});

  final String packSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packAsync = ref.watch(packDetailProvider(packSlug));
    final cardsAsync = ref.watch(packCardsProvider(packSlug));

    return Scaffold(
      appBar: AppBar(
        title: packAsync.when(
          data: (pack) => Text(pack?.name ?? 'Ekspansi'),
          loading: () => const Text('Memuat...'),
          error: (_, __) => const Text('Ekspansi'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: cardsAsync.when(
          data: (cards) {
            final pack = packAsync.valueOrNull;
            return CustomScrollView(
              slivers: [
                if (pack != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          PokeballIcon(size: 18, color: context.appColors.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${pack.mark} · Dirilis ${pack.releaseDate}',
                              style: AppTypography.bodySm(context.mutedForeground),
                            ),
                          ),
                          Text(
                            '${pack.collectedCount}/${pack.cardCount}',
                            style: AppTypography.captionSemibold(
                              context.appColors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.62,
                        ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final card = cards[i];
                        return CardGridItem(
                          card: card,
                          onTap: () => context.push(
                            Routes.cardDetail(packSlug, card.id),
                          ),
                        );
                      },
                      childCount: cards.length,
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('Gagal memuat kartu')),
        ),
      ),
    );
  }
}
