import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
import '../../../shared/widgets/wishlist_heart.dart';
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
                  icon: LucideIcons.layers,
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

  /// Most valuable first. The collection is a portfolio rather than a
  /// checklist, so what it is worth is the order that answers the question
  /// the page is opened with.
  CardSortOption _sortBy = CardSortOption.priceDesc;
  CardViewMode _viewMode = CardViewMode.grid;

  bool _editMode = false;

  /// Staged quantities by card id — only the ones the user actually moved.
  final Map<int, int> _edits = {};

  /// Cards ticked in Kelola mode, for the batch actions.
  final Set<int> _selected = {};
  bool _saving = false;
  bool _working = false;

  /// How many of the filtered cards are handed to the sliver, and how much
  /// that grows by when the end of the window comes into view.
  ///
  /// The sliver builds its children lazily either way, but the child count is
  /// also the ceiling on how much work one fling can start: every tile the
  /// scroll passes resolves an image. A collection of a few thousand cards
  /// flung end to end opened that many requests at once, and the decodes
  /// alone pushed everything earlier out of the image cache. The window keeps
  /// it to a few screens' worth at a time.
  static const _pageSize = 36;
  int _shown = _pageSize;

  /// The last filter-and-sort pass, kept so that a rebuild which changes
  /// nothing about what is listed — a stepper tap, a tick in Kelola, the
  /// selection bar appearing — doesn't filter and re-sort the whole
  /// collection again. Both are O(n log n) over every card the user owns, and
  /// in Kelola mode they ran on every single tap.
  List<CardModel>? _visibleSource;
  CardFilters? _visibleFilters;
  String? _visibleSearch;
  CardSortOption? _visibleSort;
  List<CardModel> _visible = const [];

  /// Same idea for the facet options, which scan every card to find the
  /// rarities and types present. They only depend on the unfiltered set.
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
    // A different list of cards starts at the top again.
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

  /// Reveals the next page once the end of the current one is within a
  /// screenful. Returns false so the notification carries on bubbling.
  bool _revealMore(ScrollNotification notification, int total) {
    if (notification.depth != 0 || _shown >= total) return false;
    if (notification.metrics.extentAfter > 800) return false;
    setState(() => _shown = math.min(_shown + _pageSize, total));
    return false;
  }

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
    // Which shelf the grid is showing. A list holds its own copies, so an
    // edit there sets the list's quantity rather than moving the main
    // collection's — the numbers on screen are the list's.
    final target = ref.read(selectedPortfolioProvider);
    String? failure;

    for (final entry in _edits.entries) {
      final owned = byId[entry.key]?.owned ?? 0;
      if (entry.value == owned) continue;
      final error = target.isPrimary
          ? await controller.adjustQuantity(
              userId: user.id,
              cardId: entry.key,
              delta: entry.value - owned,
            )
          : await controller.setListCardQuantity(
              listId: target.listId!,
              cardId: entry.key,
              quantity: entry.value,
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
      ..showSnackBar(
        SnackBar(
          content: Text(
            failure ??
                (target.isPrimary
                    ? 'Koleksi diperbarui'
                    : '"${target.name}" diperbarui'),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    // Not `collectionProvider` directly: the title's picker can narrow the
    // page to one list, and this is that list's cards.
    final async = ref.watch(selectedPortfolioCardsProvider);
    // The search box lives at the top of the page now, so the query comes
    // from there rather than from this tab's own filter bar.
    final search = ref.watch(collectionSearchProvider);
    final filters = _filters.copyWith(search: search);

    return async.when(
      data: (cards) {
        final visible = _visibleFor(cards, search);

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
      error: (error, stack) {
        // The message on screen stays the same; the reason behind it used to
        // go nowhere at all, which made a failure here impossible to place.
        if (kDebugMode) {
          debugPrint('[portfolio] collection failed: $error\n$stack');
        }
        return const Center(child: Text('Gagal memuat data'));
      },
    );
  }

  Widget _grid(
    List<CardModel> cards,
    List<CardModel> visible,
    CardFilters filters,
  ) {
    final shown = math.min(_shown, visible.length);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) =>
          _revealMore(notification, visible.length),
      child: CustomScrollView(
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
                  // Derived once per collection rather than on every tap.
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
                gridDelegate: cardGridDelegate(
                  context,
                  // The stepper row only exists while editing.
                  extraChrome: _editMode ? cardGridItemFooterChrome : 0,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _collectionCard(visible[i]),
                  childCount: shown,
                  // A tile holds nothing worth keeping once it is off screen,
                  // and the keep-alive wrapper is per child.
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
                    child: _collectionCard(visible[i], list: true),
                  ),
                  childCount: shown,
                  addAutomaticKeepAlives: false,
                ),
              ),
            ),
          // Says the rest is coming rather than letting the grid look like it
          // ends early. It is only ever on screen for the frame or two the
          // next page takes to build.
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
              // Room for the nav pill, plus the batch bar when it's up.
              height:
                  AppBottomNav.reservedSpace(context) +
                  (_selected.isEmpty ? 0 : 72),
            ),
          ),
        ],
      ),
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

    var error = (await repository.addCardsToList(
      listId: destination.id,
      cardIds: ids,
    )).error;
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
    // Out of edit mode a tile is just a link to the card.
    if (!_editMode) {
      void open() => context.push(Routes.cardDetail(card.packSlug, card.id));
      return list
          ? CardListItem(card: card, onTap: open)
          : CardGridItem(card: card, onTap: open);
    }

    // In edit mode the tile stops being a link — it's a checkbox. Tapping
    // through to a card page mid-edit would strand the staged changes.
    //
    // The stepper rides in the tile's own footer, the way web's edit mode
    // renders it, rather than floating over the price line: an overlay had
    // to cover the tile's text to sit anywhere, and its taps then had to be
    // carved back out of the tile underneath.
    final selected = _selected.contains(card.id);
    final footer = _stepperRow(card);
    return list
        ? CardListItem(
            card: card,
            selected: selected,
            onTap: () => _toggleSelected(card),
            footer: footer,
          )
        : CardGridItem(
            card: card,
            selected: selected,
            onTap: () => _toggleSelected(card),
            footer: footer,
          );
  }

  /// The quantity stepper, and the trash that zeroes a card out in one tap
  /// instead of holding minus down — web's edit-mode row.
  Widget _stepperRow(CardModel card) {
    final quantity = _edits[card.id] ?? card.owned;
    return Row(
      children: [
        QuantitySelector(
          value: quantity,
          onChanged: (value) => _stage(card, value),
          size: QuantitySelectorSize.sm,
        ),
        const Spacer(),
        if (quantity > 0)
          InkWell(
            onTap: () => _stage(card, 0),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                LucideIcons.trash2,
                size: 15,
                color: context.appColors.error.withValues(alpha: 0.75),
              ),
            ),
          ),
      ],
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

/// Total value, how the market has moved it, and the action row — web's
/// header block.
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
    final totalValue = cards.fold<int>(
      0,
      (sum, c) => sum + (c.marketPrice ?? 0) * c.owned,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            // Web shows "Rp–" rather than Rp0 when nothing is priced yet, so
            // a missing price never reads as a zero valuation.
            totalValue <= 0 ? 'Rp–' : formatRupiah(totalValue),
            // Plain foreground, not the brand red: red on a portfolio total
            // reads as a loss rather than as a headline.
            style: AppTypography.h2(colors.onSurface),
          ),
          const SizedBox(height: 6),
          const _MarketTrend(),
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
                    icon: const Icon(LucideIcons.pencil, size: 15),
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

/// How the market has moved the portfolio over the selected range — the
/// same figure Beranda shows under its headline, in place of the card
/// counts that used to sit here.
///
/// The series only exists for the whole collection, so when a single list is
/// on screen there is nothing to state and the line is left out rather than
/// borrowing the collection's trend under a list's name.
class _MarketTrend extends ConsumerWidget {
  const _MarketTrend();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delta = ref.watch(portfolioDeltaProvider);
    if (delta == null) return const SizedBox.shrink();

    final colors = context.appColors;
    final tone = delta.isUp ? context.appSemantic.success : colors.error;
    final range = ref.watch(portfolioRangeProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          delta.isUp ? LucideIcons.chevronUp : LucideIcons.chevronDown,
          size: 16,
          color: tone,
        ),
        Text(
          '${formatRupiah(delta.amount.abs())} '
          '(${delta.percent.abs().toStringAsFixed(2)}%)',
          style: AppTypography.bodySm(tone),
        ),
        const SizedBox(width: 4),
        Text(
          '· ${range.label}',
          style: AppTypography.bodySm(context.mutedForeground),
        ),
      ],
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
              value: query,
              onChanged: (value) =>
                  ref.read(collectionSearchProvider.notifier).state = value,
            ),
          ),
          IconButton(
            // Filled while the wishlist is what's on screen, so the heart
            // reads as a switch rather than a link.
            icon: WishlistHeart(active: showWishlist, size: 24),
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
