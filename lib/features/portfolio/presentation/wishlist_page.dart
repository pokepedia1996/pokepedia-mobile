import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/utils/card_filtering.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../core/providers/card_ownership_controller.dart';
import '../../../core/theme/app_radius.dart';
import '../../../shared/widgets/card_filter_bar.dart';
import '../../../shared/widgets/card_grid_item.dart';
import '../../../shared/widgets/card_list_item.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../usecase/portfolio_notifier.dart';
import 'widgets/portfolio_picker_sheet.dart';
import 'widgets/selection_sheet.dart';

/// The wishlist, shown in place of the collection when Koleksi's heart is
/// switched on.
///
/// Kelola works the way it does on the collection: tap to tick cards, then
/// act on the lot from the bar that rises — copy them into a list, move them
/// into one, or drop them from the wishlist.
class WishlistView extends ConsumerStatefulWidget {
  const WishlistView({super.key, this.showSearch = true});

  /// Off when the host page already has a search box of its own.
  final bool showSearch;

  @override
  ConsumerState<WishlistView> createState() => _WishlistViewState();
}

class _WishlistViewState extends ConsumerState<WishlistView> {
  CardFilters _filters = const CardFilters();
  CardSortOption _sortBy = CardSortOption.numberAsc;
  CardViewMode _viewMode = CardViewMode.grid;

  bool _editMode = false;
  bool _working = false;
  final Set<int> _selected = {};

  void _exitEdit() => setState(() {
    _editMode = false;
    _selected.clear();
  });

  void _toggleSelected(CardModel card) {
    setState(() {
      if (!_selected.remove(card.id)) _selected.add(card.id);
    });
  }

  /// Copies the ticked cards into a list, and in `move` mode takes them off
  /// the wishlist afterwards.
  Future<void> _copyOrMove({required bool move}) async {
    final destination = await showListPicker(
      context,
      ref,
      title: move ? 'Pindahkan ke list' : 'Salin ke list',
    );
    if (destination == null || !mounted) return;

    final ids = _selected.toList();
    setState(() => _working = true);

    var error =
        (await ref
                .read(portfolioRepositoryProvider)
                .addCardsToList(listId: destination.id, cardIds: ids))
            .error;
    if (error == null && move) error = await _unwishlist(ids);

    if (!mounted) return;
    setState(() {
      _working = false;
      if (error == null) _selected.clear();
    });
    ref.invalidate(listsProvider);
    ref.invalidate(listCardsProvider(destination.id));
    _toast(
      error ??
          '${ids.length} kartu ${move ? "dipindahkan" : "disalin"} ke '
              '"${destination.name}"',
    );
  }

  Future<void> _removeSelected() async {
    final ids = _selected.toList();
    await showConfirmDialog(
      context,
      title: 'Hapus dari wishlist?',
      description: '${ids.length} kartu akan dikeluarkan dari wishlist.',
      confirmLabel: 'Hapus',
      loadingLabel: 'Menghapus...',
      onConfirm: () async {
        setState(() => _working = true);
        final error = await _unwishlist(ids);
        if (!mounted) return;
        setState(() {
          _working = false;
          if (error == null) _selected.clear();
        });
        _toast(error ?? '${ids.length} kartu dihapus dari wishlist');
      },
    );
  }

  /// One call per card: `card_wishlists` has no batch endpoint, and the
  /// controller's per-card revalidation is what keeps the heart on a card
  /// page in sync.
  Future<String?> _unwishlist(List<int> cardIds) async {
    final controller = ref.read(cardOwnershipControllerProvider);
    String? failure;
    for (final id in cardIds) {
      final error = await controller.setWishlisted(id, false);
      failure ??= error;
    }
    return failure;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), persist: false));
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authProvider).valueOrNull != null;
    final async = ref.watch(wishlistProvider);

    if (!signedIn) {
      return EmptyState(
        icon: LucideIcons.heart,
        title: 'Masuk untuk melihat wishlist',
        action: ElevatedButton(
          onPressed: () => context.push(Routes.login),
          child: const Text('Masuk'),
        ),
      );
    }

    return async.when(
      data: (cards) => Stack(
        children: [
          _buildBody(cards),
          Positioned(
            left: 0,
            right: 0,
            bottom: AppBottomNav.reservedSpace(context),
            child: SelectionSheet(
              count: _selected.length,
              busy: _working,
              // A wishlist card isn't held in a list, so "move" here means
              // into a list and off the wishlist.
              canMove: true,
              onCopy: () => _copyOrMove(move: false),
              onMove: () => _copyOrMove(move: true),
              onDelete: _removeSelected,
              onClear: () => setState(_selected.clear),
            ),
          ),
        ],
      ),
      loading: () => const PikachuLoader(),
      error: (_, __) => EmptyState(
        icon: LucideIcons.circleAlert,
        title: 'Gagal memuat wishlist',
        action: OutlinedButton(
          onPressed: () => ref.invalidate(wishlistProvider),
          child: const Text('Coba lagi'),
        ),
      ),
    );
  }

  Widget _buildBody(List<CardModel> cards) {
    if (cards.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.heart,
        title: 'Wishlist masih kosong',
        description:
            'Belum ada kartu di wishlist. Tekan ikon hati pada kartu untuk '
            'menyimpannya.',
      );
    }

    final filters = widget.showSearch
        ? _filters
        : _filters.copyWith(search: ref.watch(collectionSearchProvider));
    var visible = applyCardFilters(cards, filters);
    visible = sortCards(visible, _sortBy);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _WishlistHeader(
            editMode: _editMode,
            hasCards: cards.isNotEmpty,
            onManage: () => setState(() => _editMode = true),
            onDone: _exitEdit,
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: CardFilterBar(
              cards: cards,
              showSearch: widget.showSearch,
              filters: filters,
              onFiltersChanged: (f) => setState(() => _filters = f),
              sortBy: _sortBy,
              onSortChanged: (s) => setState(() => _sortBy = s),
              viewMode: _viewMode,
              onViewModeChanged: (v) => setState(() => _viewMode = v),
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
              delegate: SliverChildBuilderDelegate(
                (context, i) => _tile(visible[i]),
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
                  child: _tile(visible[i], list: true),
                ),
                childCount: visible.length,
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(
            height:
                AppBottomNav.reservedSpace(context) +
                (_selected.isEmpty ? 0 : 72),
          ),
        ),
      ],
    );
  }

  Widget _tile(CardModel card, {bool list = false}) {
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

    final selected = _selected.contains(card.id);
    return GestureDetector(
      onTap: () => _toggleSelected(card),
      // The tile below is inert in edit mode, so the whole area has to be
      // hit-testable here rather than deferring to a child.
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          IgnorePointer(child: tile),
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
                        LucideIcons.check,
                        size: 15,
                        color: context.appColors.onPrimary,
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Wishlist" with the Kelola switch, mirroring the collection's header.
class _WishlistHeader extends StatelessWidget {
  const _WishlistHeader({
    required this.editMode,
    required this.hasCards,
    required this.onManage,
    required this.onDone,
  });

  final bool editMode;
  final bool hasCards;
  final VoidCallback onManage;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          Text(
            'Wishlist',
            style: AppTypography.h2(context.appColors.onSurface),
          ),
          if (hasCards) ...[
            const SizedBox(height: 10),
            if (editMode)
              TextButton(onPressed: onDone, child: const Text('Selesai'))
            else
              OutlinedButton.icon(
                onPressed: onManage,
                icon: const Icon(LucideIcons.pencil, size: 15),
                label: const Text('Kelola'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
              ),
          ],
        ],
      ),
    );
  }
}
