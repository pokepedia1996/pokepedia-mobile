import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/deck_model.dart';
import '../../../shared/widgets/card_grid_item.dart';
import '../../../shared/widgets/empty_state.dart';
import '../usecase/portfolio_notifier.dart';

/// Ports `app/portfolio/collection`, `/deck` and `/inventory` as a single
/// tabbed screen (this UI-only pass keeps them under one Koleksi tab).
class PortfolioPage extends ConsumerStatefulWidget {
  const PortfolioPage({super.key});

  @override
  ConsumerState<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends ConsumerState<PortfolioPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Portofolio'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: context.appColors.primary,
          unselectedLabelColor: context.mutedForeground,
          indicatorColor: context.appColors.primary,
          tabs: const [
            Tab(text: 'Koleksi'),
            Tab(text: 'Deck'),
            Tab(text: 'Inventori'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tabController,
          children: const [_CollectionTab(), _DeckTab(), _InventoryTab()],
        ),
      ),
    );
  }
}

class _CollectionTab extends ConsumerWidget {
  const _CollectionTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(collectionProvider);
    return async.when(
      data: (cards) {
        if (cards.isEmpty) {
          return const EmptyState(
            icon: Icons.style_outlined,
            title: 'Koleksi masih kosong',
            description:
                'Tambahkan kartu yang kamu miliki dari halaman ekspansi.',
          );
        }
        final totalValue = cards.fold<int>(
          0,
          (sum, c) => sum + (c.marketPrice ?? 0) * c.owned,
        );
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    _StatChip(label: 'Kartu unik', value: '${cards.length}'),
                    const SizedBox(width: 8),
                    _StatChip(
                      label: 'Estimasi nilai',
                      value: formatRupiah(totalValue),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 29),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.62,
                ),
                delegate: SliverChildBuilderDelegate((context, i) {
                  final card = cards[i];
                  return CardGridItem(
                    card: card,
                    onTap: () =>
                        context.push(Routes.cardDetail(card.packSlug, card.id)),
                  );
                }, childCount: cards.length),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Gagal memuat koleksi')),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTypography.caption(context.mutedForeground)),
            const SizedBox(height: 2),
            Text(
              value,
              style: AppTypography.bodySmSemibold(context.appColors.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeckTab extends ConsumerWidget {
  const _DeckTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(decksProvider);
    return async.when(
      data: (decks) {
        if (decks.isEmpty) {
          return const EmptyState(
            icon: Icons.style_outlined,
            title: 'Belum ada deck',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: decks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _DeckTile(
            deck: decks[i],
            onTap: () => context.push(Routes.deckDetail(decks[i].id)),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Gagal memuat deck')),
    );
  }
}

class _DeckTile extends StatelessWidget {
  const _DeckTile({required this.deck, required this.onTap});

  final DeckModel deck;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.secondary,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                Icons.grid_view_rounded,
                color: colors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deck.name,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${deck.cardCount} kartu · ${deck.format} · ${deck.updatedAt}',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.mutedForeground),
          ],
        ),
      ),
    );
  }
}

class _InventoryTab extends ConsumerWidget {
  const _InventoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(collectionProvider);
    return async.when(
      data: (cards) {
        if (cards.isEmpty) {
          return const EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'Inventori kosong',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: cards.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final card = cards[i];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.name,
                          style: AppTypography.bodySmSemibold(
                            context.appColors.onSurface,
                          ),
                        ),
                        Text(
                          card.collectorNumber,
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '×${card.owned}',
                    style: AppTypography.bodySmSemibold(
                      context.appColors.onSurface,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    card.marketPrice != null
                        ? formatRupiah(card.marketPrice!)
                        : 'Rp-',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Gagal memuat inventori')),
    );
  }
}
