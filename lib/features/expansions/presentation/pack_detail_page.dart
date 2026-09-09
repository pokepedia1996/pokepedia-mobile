import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/card_ownership_controller.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/models/card_market_price.dart';
import '../../../shared/models/pack_model.dart';
import '../../../shared/utils/card_filtering.dart';
import '../../../shared/widgets/card_filter_bar.dart';
import '../../../shared/widgets/card_grid_item.dart';
import '../../../shared/widgets/card_list_item.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../home/repository/models/portfolio_value.dart';
import '../../portfolio/presentation/widgets/add_destination_sheet.dart';
import '../../portfolio/usecase/portfolio_notifier.dart';
import '../usecase/expansions_notifier.dart';
import '../usecase/recently_viewed_provider.dart';

/// Ports `app/expansions/[packSlug]/pack-detail-client.tsx` — the pack
/// header (image, title, meta) plus the search/filter bar and card grid
/// for a single expansion.
class PackDetailPage extends ConsumerStatefulWidget {
  const PackDetailPage({super.key, required this.packSlug});

  final String packSlug;

  @override
  ConsumerState<PackDetailPage> createState() => _PackDetailPageState();
}

class _PackDetailPageState extends ConsumerState<PackDetailPage> {
  CardFilters _filters = const CardFilters();
  CardSortOption _sortBy = CardSortOption.numberAsc;
  CardViewMode _viewMode = CardViewMode.grid;
  OwnershipFilter _ownershipFilter = OwnershipFilter.all;

  /// Mirrors the web's `bulkLoading` — disables both bulk buttons while
  /// either RPC is in flight.
  bool _bulkLoading = false;

  /// Ports `handleBulkAdd` / `handleBulkRemove`. [add] false removes, and
  /// [destination] is the portfolio an add was filed under (null when
  /// removing, since that always comes out of the collection itself).
  Future<void> _runBulk({
    required bool add,
    required List<int> cardIds,
    PortfolioTarget? destination,
  }) async {
    final user = ref.read(authProvider).valueOrNull;
    // The web opens `AuthGateModal` here; mobile sends guests to the login
    // route, as every other signed-out action on this app does.
    if (user == null) {
      context.push(Routes.login);
      return;
    }
    setState(() => _bulkLoading = true);
    final controller = ref.read(cardOwnershipControllerProvider);
    final result = add
        ? await controller.bulkAddToCollection(
            userId: user.id,
            cardIds: cardIds,
            listId: destination?.listId,
          )
        : await controller.bulkRemoveFromCollection(
            userId: user.id,
            cardIds: cardIds,
          );
    if (!mounted) return;
    setState(() => _bulkLoading = false);

    final messenger = ScaffoldMessenger.of(context);
    if (result.error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(result.error!), persist: false),
      );
      return;
    }
    final where = destination == null
        ? 'koleksi'
        : portfolioDestinationLabel(destination);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          add
              ? '${result.count} kartu ditambahkan ke $where'
              : '${result.count} kartu dihapus dari koleksi',
        ),
        persist: false,
      ),
    );
  }

  /// Asks where the cards should go first, then confirms — the destination
  /// is what the confirmation is confirming, so it has to be known by then.
  Future<void> _confirmBulkAdd({
    required List<int> allIds,
    required List<int> notOwnedIds,
  }) async {
    final destination = await showAddDestinationSheet(
      context,
      ref,
      subtitle: 'Tambah semua kartu dari ekspansi ini',
    );
    if (destination == null || !mounted) return;

    // "Belum dimiliki" counts copies in the main collection, which says
    // nothing about what a list holds — so a list gets offered every card in
    // the pack, and the ones already on that shelf are skipped there.
    final toList = !destination.isPrimary;
    final cardIds = toList ? allIds : notOwnedIds;
    final where = portfolioDestinationLabel(destination);

    await showConfirmDialog(
      context,
      title: 'Tambah semua kartu?',
      description: toList
          ? 'Kartu dari ekspansi ini yang belum ada di "$where" akan '
                'ditambahkan.'
          : '${cardIds.length} kartu yang belum dimiliki akan ditambahkan ke '
                '$where.',
      confirmLabel: 'Tambah Semua',
      loadingLabel: 'Menambahkan...',
      destructive: false,
      onConfirm: () =>
          _runBulk(add: true, cardIds: cardIds, destination: destination),
    );
  }

  Future<void> _confirmBulkRemove(List<int> cardIds) {
    return showConfirmDialog(
      context,
      title: 'Hapus semua kartu?',
      description:
          'Semua ${cardIds.length} kartu dari ekspansi ini akan dihapus dari koleksi kamu.',
      confirmLabel: 'Hapus Semua',
      loadingLabel: 'Menghapus...',
      onConfirm: () => _runBulk(add: false, cardIds: cardIds),
    );
  }

  @override
  Widget build(BuildContext context) {
    final packAsync = ref.watch(packDetailProvider(widget.packSlug));
    final cardsAsync = ref.watch(packCardsProvider(widget.packSlug));
    final user = ref.watch(authProvider).valueOrNull;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(recentlyViewedSlugsProvider.notifier)
          .markViewed(widget.packSlug);
    });

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: cardsAsync.when(
          data: (cards) {
            final pack = packAsync.valueOrNull;

            // `fetchCardsForPack` doesn't join `user_cards`, so every
            // `CardModel.owned` here is 0; the real quantities arrive
            // separately, exactly as the web's `useUserCardQuantities` does
            // it. Stamping them onto the models is what lights up the owned
            // badges in the grid/list items and drives the counts below.
            final quantities =
                ref
                    .watch(packOwnedQuantitiesProvider(widget.packSlug))
                    .valueOrNull ??
                const <int, int>{};
            // Prices are the same story: the catalog table holds none, so
            // they arrive from the price cache and are stamped on here.
            // Before they land the tiles read "Rp-", and a price sort has
            // nothing to sort by — both settle on the frame they arrive.
            final prices =
                ref
                    .watch(packCardPricesProvider(widget.packSlug))
                    .valueOrNull ??
                const <int, CardMarketPrice>{};
            final owned = [
              for (final card in cards)
                card.copyWith(
                  owned: quantities[card.id],
                  price: prices[card.id],
                ),
            ];

            var visible = applyCardFilters(owned, _filters);
            if (_ownershipFilter == OwnershipFilter.owned) {
              visible = visible.where((c) => c.owned > 0).toList();
            } else if (_ownershipFilter == OwnershipFilter.notOwned) {
              visible = visible.where((c) => c.owned == 0).toList();
            }
            visible = sortCards(visible, _sortBy);

            final ownedIds = [
              for (final c in owned)
                if (c.owned > 0) c.id,
            ];
            final notOwnedIds = [
              for (final c in owned)
                if (c.owned == 0) c.id,
            ];
            final hasLists =
                (ref.watch(listsProvider).valueOrNull ?? const []).isNotEmpty;

            return CustomScrollView(
              slivers: [
                if (pack != null)
                  SliverToBoxAdapter(
                    child: _PackHeader(
                      pack: pack,
                      cardCount: cards.length,
                      ownedCount: user != null ? ownedIds.length : null,
                      bulkLoading: _bulkLoading,
                      // Signed out, Add stays tappable so it can send the
                      // user to login — the web enables it for the same
                      // reason and opens its auth gate. Remove needs cards
                      // to remove, so it can only ever be a no-op there.
                      // Owning every card only closes the button off when
                      // the main collection is the only place they could go;
                      // with a list to file them into there's still work to
                      // do, whatever `user_cards` already holds.
                      onAddAll: _bulkLoading
                          ? null
                          : user == null
                          ? () => _runBulk(add: true, cardIds: const [])
                          : notOwnedIds.isEmpty && !hasLists
                          ? null
                          : () => _confirmBulkAdd(
                              allIds: [for (final c in owned) c.id],
                              notOwnedIds: notOwnedIds,
                            ),
                      onRemoveAll:
                          _bulkLoading || user == null || ownedIds.isEmpty
                          ? null
                          : () => _confirmBulkRemove(ownedIds),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: CardFilterBar(
                      cards: cards,
                      filters: _filters,
                      onFiltersChanged: (f) => setState(() => _filters = f),
                      sortBy: _sortBy,
                      onSortChanged: (s) => setState(() => _sortBy = s),
                      viewMode: _viewMode,
                      onViewModeChanged: (v) => setState(() => _viewMode = v),
                      ownershipFilter: user != null ? _ownershipFilter : null,
                      onOwnershipChanged: user != null
                          ? (v) => setState(() => _ownershipFilter = v)
                          : null,
                    ),
                  ),
                ),
                if (visible.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    sliver: SliverToBoxAdapter(
                      child: Center(
                        child: Text(
                          'Tidak ada kartu yang sesuai filter.',
                          style: AppTypography.bodySm(context.mutedForeground),
                        ),
                      ),
                    ),
                  )
                else if (_viewMode == CardViewMode.grid)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    sliver: SliverGrid(
                      gridDelegate: cardGridDelegate(context),
                      delegate: SliverChildBuilderDelegate((context, i) {
                        final card = visible[i];
                        return CardGridItem(
                          card: card,
                          onTap: () => context.push(
                            Routes.cardDetail(widget.packSlug, card.id),
                          ),
                        );
                      }, childCount: visible.length),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, i) {
                        final card = visible[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: CardListItem(
                            card: card,
                            onTap: () => context.push(
                              Routes.cardDetail(widget.packSlug, card.id),
                            ),
                          ),
                        );
                      }, childCount: visible.length),
                    ),
                  ),
              ],
            );
          },
          loading: () => const PikachuLoader(),
          error: (_, __) => const Center(child: Text('Gagal memuat kartu')),
        ),
      ),
    );
  }
}

class _PackHeader extends StatelessWidget {
  const _PackHeader({
    required this.pack,
    required this.cardCount,
    required this.ownedCount,
    required this.bulkLoading,
    required this.onAddAll,
    required this.onRemoveAll,
  });

  final PackModel pack;
  final int cardCount;

  /// Null when signed out — mirrors the web only appending "Dimiliki: X/Y"
  /// for a logged-in `user`.
  final int? ownedCount;

  final bool bulkLoading;

  /// Null disables the button, matching the web's `disabled` expressions.
  final VoidCallback? onAddAll;
  final VoidCallback? onRemoveAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: pack.image != null
                ? Image.network(
                    pack.image!,
                    width: double.infinity,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _PackImageFallback(mark: pack.mark),
                  )
                : _PackImageFallback(mark: pack.mark),
          ),
          const SizedBox(height: 16),
          Text(pack.name, style: AppTypography.h1(colors.onSurface)),
          const SizedBox(height: 4),
          Text(
            [
              'Dirilis: ${pack.releaseDate}',
              '$cardCount kartu',
              if (ownedCount != null) 'Dimiliki: $ownedCount / $cardCount',
            ].join(' · '),
            style: AppTypography.caption(context.mutedForeground),
          ),
          const SizedBox(height: 12),
          // Web sits these to the right of the title as a `flex shrink-0
          // gap-2` pair; there's no room for that beside an h1 on a phone,
          // so they take a full-width row of their own under the meta line.
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: bulkLoading ? null : onRemoveAll,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.error,
                    side: BorderSide(
                      color: colors.error.withValues(alpha: 0.5),
                    ),
                    padding: EdgeInsets.fromLTRB(2, 2, 2, 2),
                  ),
                  child: const Text(
                    'Hapus Semua dari Koleksi',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: bulkLoading ? null : onAddAll,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.appSemantic.success,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.fromLTRB(2, 2, 2, 2),
                  ),
                  child: const Text(
                    'Tambah Semua ke Koleksi',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PackImageFallback extends StatelessWidget {
  const _PackImageFallback({required this.mark});

  final String mark;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      height: 120,
      color: colors.secondary,
      alignment: Alignment.center,
      child: Text(mark, style: AppTypography.h1(context.mutedForeground)),
    );
  }
}
