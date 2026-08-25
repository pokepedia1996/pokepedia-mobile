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
import '../../../shared/widgets/app_top_bar.dart';
import '../../../shared/widgets/card_filter_bar.dart';
import '../../../shared/widgets/card_grid_item.dart';
import '../../../shared/widgets/card_list_item.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../core/providers/card_ownership_controller.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/quantity_selector.dart';
import '../usecase/portfolio_notifier.dart';
import 'widgets/collection_add_sheet.dart';

/// Ports `app/portfolio/collection/page.tsx`.
///
/// Deck and Inventori used to be tabs here; on the web they're sibling
/// routes (`/portfolio/deck`, `/portfolio/inventory`), so they're their own
/// pages now and this holds only the Koleksi / Wishlist pair the web page
/// itself toggles between.
class PortfolioPage extends ConsumerStatefulWidget {
  const PortfolioPage({super.key});

  @override
  ConsumerState<PortfolioPage> createState() => _PortfolioPageState();
}

enum _CollectionView { collection, wishlist }

class _PortfolioPageState extends ConsumerState<PortfolioPage> {
  _CollectionView _view = _CollectionView.collection;

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
            const AppTopBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Koleksi Kartu',
                  style: AppTypography.h2(context.appColors.onSurface),
                ),
              ),
            ),
            if (user == null)
              Expanded(
                child: EmptyState(
                  icon: Icons.style_outlined,
                  title: 'Masuk untuk melihat koleksimu',
                  description:
                      'Kelola koleksi dan wishlist kartu Pokemon-mu.',
                  action: ElevatedButton(
                    onPressed: () => context.push(Routes.login),
                    child: const Text('Masuk'),
                  ),
                ),
              )
            else ...[
              // The web's underlined pair, not a Material TabBar — it sits
              // above the header stats rather than replacing them.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    for (final view in _CollectionView.values)
                      _ViewTab(
                        label: view == _CollectionView.collection
                            ? 'Koleksi'
                            : 'Wishlist',
                        selected: _view == view,
                        onTap: () => setState(() => _view = view),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _view == _CollectionView.collection
                    ? const _CollectionTab()
                    : const _WishlistTab(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One of the two underlined view tabs.
class _ViewTab extends StatelessWidget {
  const _ViewTab({
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
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        margin: const EdgeInsets.only(right: 18),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? colors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: selected
              ? AppTypography.bodySmSemibold(colors.onSurface)
              : AppTypography.bodySm(context.mutedForeground),
        ),
      ),
    );
  }
}

/// Shared search/filter/sort/grid-list browser for a flat card list — used
/// by both the Koleksi and Wishlist tabs.
class _CardBrowseTab extends ConsumerStatefulWidget {
  const _CardBrowseTab({
    required this.provider,
    required this.emptyIcon,
    required this.emptyTitle,
    this.emptyDescription,
  });

  final FutureProvider<List<CardModel>> provider;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyDescription;

  @override
  ConsumerState<_CardBrowseTab> createState() => _CardBrowseTabState();
}

class _CardBrowseTabState extends ConsumerState<_CardBrowseTab> {
  CardFilters _filters = const CardFilters();
  CardSortOption _sortBy = CardSortOption.numberAsc;
  CardViewMode _viewMode = CardViewMode.grid;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(widget.provider);
    return async.when(
      data: (cards) {
        if (cards.isEmpty) {
          return EmptyState(
            icon: widget.emptyIcon,
            title: widget.emptyTitle,
            description: widget.emptyDescription,
          );
        }

        var visible = applyCardFilters(cards, _filters);
        visible = sortCards(visible, _sortBy);

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: CardFilterBar(
                  cards: cards,
                  filters: _filters,
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
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.62,
                  ),
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final card = visible[i];
                    return CardGridItem(
                      card: card,
                      onTap: () => context.push(
                        Routes.cardDetail(card.packSlug, card.id),
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
                          Routes.cardDetail(card.packSlug, card.id),
                        ),
                      ),
                    );
                  }, childCount: visible.length),
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(height: AppBottomNav.reservedSpace(context)),
            ),
          ],
        );
      },
      loading: () => const PikachuLoader(),
      error: (_, __) => const Center(child: Text('Gagal memuat data')),
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
  bool _saving = false;

  void _exitEdit() => setState(() {
    _editMode = false;
    _edits.clear();
  });

  void _stage(CardModel card, int quantity) {
    setState(() {
      if (quantity == card.owned) {
        _edits.remove(card.id);
      } else {
        _edits[card.id] = quantity;
      }
    });
  }

  /// Web's "Hapus Semua" — stages every visible card to zero rather than
  /// deleting outright, so it still goes through the same confirmation.
  void _stageAllToZero(List<CardModel> visible) {
    setState(() {
      for (final card in visible) {
        if (card.owned > 0) _edits[card.id] = 0;
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
        content: Text(
          '${_edits.length} kartu akan diperbarui di koleksimu.',
        ),
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
      ..showSnackBar(
        SnackBar(content: Text(failure ?? 'Koleksi diperbarui')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(collectionProvider);

    return async.when(
      data: (cards) {
        var visible = applyCardFilters(cards, _filters);
        visible = sortCards(visible, _sortBy);

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _CollectionHeader(
                cards: cards,
                visible: visible,
                editMode: _editMode,
                pendingEdits: _edits.length,
                saving: _saving,
                onAdd: _openAddSheet,
                onManage: () => setState(() => _editMode = true),
                onClearAll: () => _stageAllToZero(visible),
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
                    filters: _filters,
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
              child: SizedBox(height: AppBottomNav.reservedSpace(context)),
            ),
          ],
        );
      },
      loading: () => const PikachuLoader(),
      error: (_, __) => const Center(child: Text('Gagal memuat data')),
    );
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

    // In edit mode the tile stops being a link — tapping through to a card
    // page mid-edit would strand the staged changes.
    return Stack(
      children: [
        IgnorePointer(child: tile),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
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
    required this.onClearAll,
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
  final VoidCallback onClearAll;
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${cards.length} kartu unik · $totalQuantity total',
            style: AppTypography.bodySm(context.mutedForeground),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              text: 'Nilai Total: ',
              style: AppTypography.h3(colors.onSurface),
              children: [
                TextSpan(
                  // Web shows "Rp–" rather than Rp0 when nothing is priced
                  // yet, so a missing price never reads as a zero valuation.
                  text: totalValue <= 0 ? 'Rp–' : formatRupiah(totalValue),
                  style: AppTypography.h3(colors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (editMode)
            Row(
              children: [
                if (visible.isNotEmpty)
                  TextButton.icon(
                    onPressed: saving ? null : onClearAll,
                    icon: const Icon(Icons.delete_outline, size: 15),
                    label: const Text('Hapus Semua'),
                    style: TextButton.styleFrom(foregroundColor: colors.error),
                  ),
                const Spacer(),
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
              children: [
                ElevatedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Tambah Kartu'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                  ),
                ),
                const SizedBox(width: 8),
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

class _WishlistTab extends StatelessWidget {
  const _WishlistTab();

  @override
  Widget build(BuildContext context) {
    return _CardBrowseTab(
      provider: wishlistProvider,
      emptyIcon: Icons.favorite_border,
      emptyTitle: 'Wishlist masih kosong',
      emptyDescription:
          'Belum ada kartu di wishlist. Tekan ikon hati pada kartu untuk '
          'menyimpannya.',
    );
  }
}
