import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/card_ownership_controller.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/models/card_market_price.dart';
import '../../../shared/models/pack_model.dart';
import '../../../shared/utils/card_filtering.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/card_filter_bar.dart';
import '../../../shared/widgets/card_grid_item.dart';
import '../../../shared/widgets/card_list_item.dart';
import '../../../shared/widgets/cart_app_bar_button.dart';
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
      // The nav floats over the grid, the same way it does on the tab roots.
      extendBody: true,
      appBar: const TransparentAppBar(actions: [CartAppBarButton()]),
      // Kept rather than hidden: browsing a set is still browsing, so the
      // tabs stay reachable without walking back to the expansions list.
      //
      // The page is pushed on the root navigator, above [AppShell], so there
      // is no `StatefulNavigationShell` here to call `goBranch` on — `go` to
      // the tab's own path switches the branch and drops this page, which is
      // what tapping a tab means anyway. The pill also doesn't shrink on
      // scroll here; that animation is driven by the shell's listener.
      bottomNavigationBar: AppBottomNav(
        currentIndex: AppBottomNav.tabPaths.indexOf(Routes.expansions),
        onTap: (index) => context.go(AppBottomNav.tabPaths[index]),
      ),
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
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      // Clears the floating pill, which now covers the foot
                      // of the grid.
                      AppBottomNav.reservedSpace(context) + 12,
                    ),
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
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      // Clears the floating pill, which now covers the foot
                      // of the grid.
                      AppBottomNav.reservedSpace(context) + 12,
                    ),
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
          // The two bulk actions used to be a full-width pair of buttons
          // under the meta line — two sentences of shouting for something
          // done once, if ever. They live behind the title's menu now, which
          // is also where web keeps them: beside the name, not under it.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  pack.name,
                  style: AppTypography.h1(colors.onSurface),
                ),
              ),
              const SizedBox(width: 8),
              _BulkMenu(
                busy: bulkLoading,
                onAddAll: onAddAll,
                onRemoveAll: onRemoveAll,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              'Dirilis: ${pack.releaseDate}',
              '$cardCount kartu',
              if (ownedCount != null) 'Dimiliki: $ownedCount / $cardCount',
            ].join(' · '),
            style: AppTypography.caption(context.mutedForeground),
          ),
        ],
      ),
    );
  }
}

/// The title row's "⋮" — everything that acts on the whole expansion.
class _BulkMenu extends StatelessWidget {
  const _BulkMenu({
    required this.busy,
    required this.onAddAll,
    required this.onRemoveAll,
  });

  /// A bulk write is running: the menu still opens, but its entries are
  /// inert rather than queuing a second pass over the same expansion.
  final bool busy;

  /// Null disables the entry, matching the web's `disabled` expressions —
  /// nothing to remove when nothing is owned, and so on.
  final VoidCallback? onAddAll;
  final VoidCallback? onRemoveAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return PopupMenuButton<String>(
      tooltip: 'Aksi ekspansi',
      padding: EdgeInsets.zero,
      // Level with the title's first line rather than centred against a name
      // that may wrap to two.
      position: PopupMenuPosition.under,
      icon: Icon(
        LucideIcons.ellipsisVertical,
        size: 20,
        color: context.mutedForeground,
      ),
      onSelected: (value) => switch (value) {
        'add' => onAddAll?.call(),
        'remove' => onRemoveAll?.call(),
        _ => null,
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'add',
          enabled: !busy && onAddAll != null,
          child: _BulkMenuItem(
            icon: LucideIcons.plus,
            label: 'Tambah semua',
            color: context.appSemantic.success,
          ),
        ),
        PopupMenuItem(
          value: 'remove',
          enabled: !busy && onRemoveAll != null,
          child: _BulkMenuItem(
            icon: LucideIcons.minus,
            label: 'Hapus semua',
            color: colors.error,
          ),
        ),
      ],
    );
  }
}

/// One line of [_BulkMenu] — the sign, then what it does.
class _BulkMenuItem extends StatelessWidget {
  const _BulkMenuItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label, style: AppTypography.bodySm(context.appColors.onSurface)),
      ],
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
