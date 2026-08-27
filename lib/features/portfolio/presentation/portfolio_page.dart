import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/utils/card_filtering.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/card_filter_bar.dart';
import '../../../shared/widgets/card_grid_item.dart';
import '../../../shared/widgets/card_list_item.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../core/providers/card_ownership_controller.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/quantity_selector.dart';
import '../../home/usecase/portfolio_value_notifier.dart';
import '../usecase/portfolio_notifier.dart';
import 'widgets/portfolio_picker_sheet.dart';
import 'widgets/selection_sheet.dart';
import 'wishlist_page.dart';
import 'widgets/collection_add_sheet.dart';

/// Ports `app/portfolio/collection/page.tsx`.
///
/// Deck and Inventori are sibling routes rather than tabs here. The wishlist
/// is still on this page, but behind the heart beside the search box rather
/// than a tab strip: it shares the search, filters and sort with the
/// collection, so it's a switch of what's listed, not a different screen.
class PortfolioPage extends ConsumerStatefulWidget {
  const PortfolioPage({super.key});

  @override
  ConsumerState<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends ConsumerState<PortfolioPage> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull;

    return Scaffold(
      // `bottom: false` lets the list run under the floating nav pill; the
      // tabs pad their own scroll extent to clear it.
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Search first, with the way to the wishlist beside it. It's the
            // only pinned row — the title scrolls away with the cards.
            const _SearchRow(),
            if (user == null)
              Expanded(
                child: EmptyState(
                  icon: Icons.style_outlined,
                  title: 'Masuk untuk melihat koleksimu',
                  description: 'Kelola koleksi dan wishlist kartu Pokemon-mu.',
                  action: ElevatedButton(
                    onPressed: () => context.push(Routes.login),
                    child: const Text('Masuk'),
                  ),
                ),
              )
            else
              Expanded(
                child: ref.watch(showWishlistProvider)
                    ? const WishlistView(showSearch: false)
                    : const _CollectionTab(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ports `app/portfolio/collection/page.tsx`'s Koleksi view: the header
/// counts and total value, the Tambah Kartu / Kelola actions, and the same
/// filter-sort-view browser underneath.
///
/// "Kelola" is web's `editMode`: quantities are staged locally and only
/// written on Selesai, so a mis-tap costs nothing until it's confirmed.
class _CollectionTab extends ConsumerStatefulWidget {
  const _CollectionTab();

  @override
  ConsumerState<_CollectionTab> createState() => _CollectionTabState();
}

class _CollectionTabState extends ConsumerState<_CollectionTab> {
  CardFilters _filters = const CardFilters();
  CardSortOption _sortBy = CardSortOption.numberAsc;
  CardViewMode _viewMode = CardViewMode.grid;

  bool _editMode = false;

  /// Staged quantities by card id — only the ones the user actually moved.
  final Map<int, int> _edits = {};

  /// Cards ticked in Kelola mode, for the batch actions.
  final Set<int> _selected = {};
  bool _saving = false;
  bool _working = false;

  void _exitEdit() => setState(() {
    _editMode = false;
    _edits.clear();
    _selected.clear();
  });

  void _toggleSelected(CardModel card) {
    setState(() {
      if (!_selected.remove(card.id)) _selected.add(card.id);
    });
  }

  void _stage(CardModel card, int quantity) {
    setState(() {
      if (quantity == card.owned) {
        _edits.remove(card.id);
      } else {
        _edits[card.id] = quantity;
      }
    });
  }

  Future<void> _save(List<CardModel> cards) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null || _edits.isEmpty) {
      _exitEdit();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Simpan perubahan?'),
        content: Text('${_edits.length} kartu akan diperbarui di koleksimu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    final byId = {for (final card in cards) card.id: card};
    final controller = ref.read(cardOwnershipControllerProvider);
    String? failure;

    for (final entry in _edits.entries) {
      final owned = byId[entry.key]?.owned ?? 0;
      final delta = entry.value - owned;
      if (delta == 0) continue;
      final error = await controller.adjustQuantity(
        userId: user.id,
        cardId: entry.key,
        delta: delta,
      );
      failure ??= error;
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _editMode = false;
      _edits.clear();
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(failure ?? 'Koleksi diperbarui')));
  }

  @override
  Widget build(BuildContext context) {
    // Not `collectionProvider` directly: the title's picker can narrow the
    // page to one list, and this is that list's cards.
    final async = ref.watch(selectedPortfolioCardsProvider);
    // The search box lives at the top of the page now, so the query comes
    // from there rather than from this tab's own filter bar.
    final filters = _filters.copyWith(
      search: ref.watch(collectionSearchProvider),
    );

    return async.when(
      data: (cards) {
        var visible = applyCardFilters(cards, filters);
        visible = sortCards(visible, _sortBy);

        return Stack(
          children: [
            _grid(cards, visible, filters),
            // The batch bar rides above the grid, clearing the floating nav.
            Positioned(
              left: 0,
              right: 0,
              bottom: AppBottomNav.reservedSpace(context),
              child: SelectionSheet(
                count: _selected.length,
                busy: _working,
                canMove: !ref.watch(selectedPortfolioProvider).isPrimary,
                moveHint: const Text('Pilih list dulu'),
                onCopy: () => _copyOrMove(cards, move: false),
                onMove: () => _copyOrMove(cards, move: true),
                onDelete: () => _deleteSelected(cards),
                onClear: () => setState(_selected.clear),
              ),
            ),
          ],
        );
      },
      loading: () => const PikachuLoader(),
      error: (_, __) => const Center(child: Text('Gagal memuat data')),
    );
  }

  Widget _grid(
    List<CardModel> cards,
    List<CardModel> visible,
    CardFilters filters,
  ) {
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: _TitleRow()),
        SliverToBoxAdapter(
          child: _CollectionHeader(
            cards: cards,
            visible: visible,
            editMode: _editMode,
            pendingEdits: _edits.length,
            saving: _saving,
            onAdd: _openAddSheet,
            onManage: () => setState(() => _editMode = true),
            onDone: () => _save(cards),
            onCancel: _exitEdit,
          ),
        ),
        if (cards.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: CardFilterBar(
                cards: cards,
                showSearch: false,
                filters: filters,
                onFiltersChanged: (f) => setState(() => _filters = f),
                sortBy: _sortBy,
                onSortChanged: (s) => setState(() => _sortBy = s),
                viewMode: _viewMode,
                onViewModeChanged: (v) => setState(() => _viewMode = v),
              ),
            ),
          ),
        if (cards.isEmpty)
          _message(
            'Belum ada kartu dalam koleksi. Tambahkan kartu dari halaman '
            'ekspansi!',
          )
        else if (visible.isEmpty)
          _message('Tidak ada kartu yang sesuai filter.')
        else if (_viewMode == CardViewMode.grid)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.62,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _collectionCard(visible[i]),
                childCount: visible.length,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _collectionCard(visible[i], list: true),
                ),
                childCount: visible.length,
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(
            // Room for the nav pill, plus the batch bar when it's up.
            height:
                AppBottomNav.reservedSpace(context) +
                (_selected.isEmpty ? 0 : 72),
          ),
        ),
      ],
    );
  }

  /// Adds the selected cards to a list the user picks, and in `move` mode
  /// takes them out of the list currently on screen.
  Future<void> _copyOrMove(List<CardModel> cards, {required bool move}) async {
    final target = ref.read(selectedPortfolioProvider);
    if (move && target.isPrimary) return;

    final destination = await showListPicker(
      context,
      ref,
      excludeListId: target.listId,
      title: move ? 'Pindahkan ke list' : 'Salin ke list',
    );
    if (destination == null || !mounted) return;

    final ids = _selected.toList();
    setState(() => _working = true);
    final repository = ref.read(portfolioRepositoryProvider);

    var error = await repository.addCardsToList(
      listId: destination.id,
      cardIds: ids,
    );
    if (error == null && move) {
      error = await repository.removeCardsFromList(
        listId: target.listId!,
        cardIds: ids,
      );
    }

    if (!mounted) return;
    setState(() {
      _working = false;
      if (error == null) _selected.clear();
    });

    ref.invalidate(listsProvider);
    ref.invalidate(listCardsProvider(destination.id));
    if (target.listId != null) {
      ref.invalidate(listCardsProvider(target.listId!));
    }

    _toast(
      error ??
          (move
              ? '${ids.length} kartu dipindahkan ke "${destination.name}"'
              : '${ids.length} kartu disalin ke "${destination.name}"'),
    );
  }

  /// Removes the selected cards from the list on screen, or from the
  /// collection itself when the main portfolio is the one being shown.
  Future<void> _deleteSelected(List<CardModel> cards) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    final target = ref.read(selectedPortfolioProvider);
    final ids = _selected.toList();
    final fromList = !target.isPrimary;

    await showConfirmDialog(
      context,
      title: fromList ? 'Hapus dari list?' : 'Hapus dari koleksi?',
      description: fromList
          ? '${ids.length} kartu akan dikeluarkan dari "${target.name}". '
                'Kartunya tetap ada di koleksimu.'
          : '${ids.length} kartu akan dihapus dari koleksimu.',
      confirmLabel: 'Hapus',
      loadingLabel: 'Menghapus...',
      onConfirm: () async {
        setState(() => _working = true);
        final String? error;
        if (fromList) {
          error = await ref
              .read(portfolioRepositoryProvider)
              .removeCardsFromList(listId: target.listId!, cardIds: ids);
          ref.invalidate(listCardsProvider(target.listId!));
          ref.invalidate(listsProvider);
        } else {
          final result = await ref
              .read(cardOwnershipControllerProvider)
              .bulkRemoveFromCollection(userId: user.id, cardIds: ids);
          error = result.error;
        }

        if (!mounted) return;
        setState(() {
          _working = false;
          if (error == null) _selected.clear();
        });
        _toast(error ?? '${ids.length} kartu dihapus');
      },
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), persist: false));
  }

  Widget _collectionCard(CardModel card, {bool list = false}) {
    final tile = list
        ? CardListItem(
            card: card,
            onTap: () =>
                context.push(Routes.cardDetail(card.packSlug, card.id)),
          )
        : CardGridItem(
            card: card,
            onTap: () =>
                context.push(Routes.cardDetail(card.packSlug, card.id)),
          );

    if (!_editMode) return tile;

    // In edit mode the tile stops being a link — it's a checkbox. Tapping
    // through to a card page mid-edit would strand the staged changes.
    final selected = _selected.contains(card.id);
    return GestureDetector(
      onTap: () => _toggleSelected(card),
      // Opaque, not the default `deferToChild`: the tile underneath is
      // wrapped in an IgnorePointer, so with deferToChild nothing in the
      // card's own area is hit-testable and only the counter took taps.
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          IgnorePointer(child: tile),
          // Selection state, drawn over the art so it reads at a glance.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: selected
                        ? context.appColors.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                  color: selected
                      ? context.appColors.primary.withValues(alpha: 0.12)
                      : Colors.transparent,
                ),
              ),
            ),
          ),
          Positioned(
            top: 6,
            left: 6,
            child: IgnorePointer(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: selected
                      ? context.appColors.primary
                      : Theme.of(context).cardColor.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                  border: Border.all(color: context.borderColor),
                ),
                child: selected
                    ? Icon(
                        Icons.check,
                        size: 15,
                        color: context.appColors.onPrimary,
                      )
                    : null,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              // Hugs the bottom edge with no padding of its own, so it sits
              // over the price line and leaves the card's name uncovered.
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: context.borderColor),
              ),
              child: QuantitySelector(
                value: _edits[card.id] ?? card.owned,
                onChanged: (value) => _stage(card, value),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(String text) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      sliver: SliverToBoxAdapter(
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTypography.bodySm(context.mutedForeground),
          ),
        ),
      ),
    );
  }

  Future<void> _openAddSheet() async {
    final added = await showCollectionAddSheet(context);
    if (added == true && mounted) ref.invalidate(collectionProvider);
  }
}

/// Title, counts, total value and the action row — web's header block.
class _CollectionHeader extends StatelessWidget {
  const _CollectionHeader({
    required this.cards,
    required this.visible,
    required this.editMode,
    required this.pendingEdits,
    required this.saving,
    required this.onAdd,
    required this.onManage,
    required this.onDone,
    required this.onCancel,
  });

  final List<CardModel> cards;
  final List<CardModel> visible;
  final bool editMode;
  final int pendingEdits;
  final bool saving;
  final VoidCallback onAdd;
  final VoidCallback onManage;
  final VoidCallback onDone;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final totalQuantity = cards.fold<int>(0, (sum, c) => sum + c.owned);
    final totalValue = cards.fold<int>(
      0,
      (sum, c) => sum + (c.marketPrice ?? 0) * c.owned,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text.rich(
            TextSpan(
              style: AppTypography.h3(colors.onSurface),
              children: [
                TextSpan(
                  // Web shows "Rp–" rather than Rp0 when nothing is priced
                  // yet, so a missing price never reads as a zero valuation.
                  text: totalValue <= 0 ? 'Rp–' : formatRupiah(totalValue),
                  style: AppTypography.h2(colors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${cards.length} kartu unik · $totalQuantity total',
            style: AppTypography.bodySm(context.mutedForeground),
          ),
          const SizedBox(height: 6),
          if (editMode)
            Row(
              // Batch deletion moved to the selection bar's menu, so this row
              // is only about the staged quantity edits now.
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: saving ? null : onDone,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          pendingEdits > 0
                              ? 'Selesai ($pendingEdits)'
                              : 'Selesai',
                        ),
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: saving ? null : onCancel,
                  child: const Text('Batal'),
                ),
              ],
            )
          else
            Row(
              // Centred under the centred title, rather than hanging off the
              // left edge on its own.
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // const SizedBox(width: 8),
                if (cards.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: onManage,
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('Kelola'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The collection's search box, with the heart that opens the wishlist.
class _SearchRow extends ConsumerWidget {
  const _SearchRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(collectionSearchProvider);
    final showWishlist = ref.watch(showWishlistProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: CardSearchField(
              dense: true,
              value: query,
              onChanged: (value) =>
                  ref.read(collectionSearchProvider.notifier).state = value,
            ),
          ),
          IconButton(
            // Filled while the wishlist is what's on screen, so the heart
            // reads as a switch rather than a link.
            icon: Icon(showWishlist ? Icons.favorite : Icons.favorite_border),
            color: context.appColors.primary,
            tooltip: showWishlist ? 'Kembali ke koleksi' : 'Wishlist',
            onPressed: () =>
                ref.read(showWishlistProvider.notifier).state = !showWishlist,
          ),
        ],
      ),
    );
  }
}

/// "Portfolio" with the list it's showing beside it — tapping the name opens
/// the same picker Beranda uses, so both screens switch the same selection.
class _TitleRow extends ConsumerWidget {
  const _TitleRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final target = ref.watch(selectedPortfolioProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Portfolio', style: AppTypography.h2(colors.onSurface)),
          const SizedBox(width: 4),
          Flexible(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => showPortfolioPicker(context, ref),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        target.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.h2(colors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
