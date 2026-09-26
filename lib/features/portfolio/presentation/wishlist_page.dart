import 'dart:math' as math;

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

  /// The reveal window and the memoised filter pass — the same reasoning as
  /// the collection tab's, which this view shares a page with.
  static const _pageSize = 36;
  int _shown = _pageSize;

  List<CardModel>? _visibleSource;
  CardFilters? _visibleFilters;
  String? _visibleSearch;
  CardSortOption? _visibleSort;
  List<CardModel> _visible = const [];

  List<CardModel>? _optionsSource;
  CardFilterOptions? _options;

  List<CardModel> _visibleFor(List<CardModel> cards, String search) {
    if (identical(cards, _visibleSource) &&
        identical(_filters, _visibleFilters) &&
        search == _visibleSearch &&
        _sortBy == _visibleSort) {
      return _visible;
    }

    _visibleSource = cards;
    _visibleFilters = _filters;
    _visibleSearch = search;
    _visibleSort = _sortBy;
    _visible = sortCards(
      applyCardFilters(cards, _filters.copyWith(search: search)),
      _sortBy,
    );
    _shown = _pageSize;
    return _visible;
  }

  CardFilterOptions _optionsFor(List<CardModel> cards) {
    if (!identical(cards, _optionsSource) || _options == null) {
      _optionsSource = cards;
      _options = deriveCardFilterOptions(cards);
    }
    return _options!;
  }

  bool _revealMore(ScrollNotification notification, int total) {
    if (notification.depth != 0 || _shown >= total) return false;
    if (notification.metrics.extentAfter > 800) return false;
    setState(() => _shown = math.min(_shown + _pageSize, total));
    return false;
  }

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

    final search = widget.showSearch
        ? _filters.search
        : ref.watch(collectionSearchProvider);
    final filters = _filters.copyWith(search: search);
    final visible = _visibleFor(cards, search);
    final shown = math.min(_shown, visible.length);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) =>
          _revealMore(notification, visible.length),
      child: CustomScrollView(
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
                optionsOverride: _optionsFor(cards),
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
                  childCount: shown,
                  addAutomaticKeepAlives: false,
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
                  childCount: shown,
                  addAutomaticKeepAlives: false,
                ),
              ),
            ),
          if (shown < visible.length)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
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
      ),
    );
  }

  Widget _tile(CardModel card, {bool list = false}) {
    if (!_editMode) {
      void open() => context.push(Routes.cardDetail(card.packSlug, card.id));
      return list
          ? CardListItem(card: card, onTap: open)
          : CardGridItem(card: card, onTap: open);
    }

    // Editing turns the tile into a checkbox — the tick and the tile's own
    // border carry it, so the artwork stays legible underneath.
    final selected = _selected.contains(card.id);
    return list
        ? CardListItem(
            card: card,
            selected: selected,
            onTap: () => _toggleSelected(card),
          )
        : CardGridItem(
            card: card,
            selected: selected,
            onTap: () => _toggleSelected(card),
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
