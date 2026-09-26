import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/card_model.dart';
import '../../../../shared/utils/card_filtering.dart';
import '../../../../shared/widgets/card_art.dart';
import '../../../../shared/widgets/card_language_badge.dart';
import '../../../../shared/widgets/pikachu_loader.dart';
import '../../../portfolio/usecase/portfolio_notifier.dart';
import '../../repository/seller_listings_repository.dart';

/// "Tambahkan Listing" — find cards, tick several, send them all to Draft.
///
/// This used to search for one card and hand it straight to the ask form,
/// which asked for a price, a condition and photos before the seller had
/// finished saying *what* they were selling. A seller emptying a binder
/// knows the twenty cards long before they know twenty prices.
///
/// So the sheet answers one question — which cards — and the drafts it
/// creates carry the rest, to be filled in on the cards themselves where a
/// market price is one tap away.
///
/// Returns true when anything was added, so the caller can refresh.
Future<bool?> showAddListingSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => const _AddListingSheet(),
  );
}

/// Web's picker refuses to search on one character; so does the RPC.
const _minQuery = 2;

class _AddListingSheet extends ConsumerStatefulWidget {
  const _AddListingSheet();

  @override
  ConsumerState<_AddListingSheet> createState() => _AddListingSheetState();
}

class _AddListingSheetState extends ConsumerState<_AddListingSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _saving = false;
  CardSortOption _sort = CardSortOption.setDesc;

  /// The pick, in the order it was made, so the strip at the top reads as a
  /// history of what was tapped rather than reshuffling on every addition.
  final List<CardModel> _selected = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _toggle(CardModel card) {
    setState(() {
      final at = _selected.indexWhere((c) => c.id == card.id);
      if (at >= 0) {
        _selected.removeAt(at);
      } else {
        _selected.add(card);
      }
    });
  }

  Future<void> _addToDraft() async {
    if (_selected.isEmpty || _saving) return;
    setState(() => _saving = true);

    final result = await ref.read(sellerListingsRepositoryProvider).addDrafts([
      for (final c in _selected) c.id,
    ]);

    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.error ?? '${result.added} kartu ditambahkan ke draft',
          ),
          persist: false,
        ),
      );

    if (result.added > 0) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final async = _query.length >= _minQuery
        ? ref.watch(cardSearchPickerProvider(_query))
        : null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.92,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tambahkan Listing',
                      style: AppTypography.h3(colors.onSurface),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 20),
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: _SearchBox(
                controller: _controller,
                onChanged: _onChanged,
                onClear: () {
                  _controller.clear();
                  _onChanged('');
                },
              ),
            ),
            if (_selected.isNotEmpty)
              _SelectedStrip(
                selected: _selected,
                onRemove: _toggle,
                onClearAll: () => setState(_selected.clear),
              ),
            Expanded(child: _results(context, async)),
            if (_selected.isNotEmpty)
              _AddBar(
                count: _selected.length,
                busy: _saving,
                onTap: _addToDraft,
              ),
          ],
        ),
      ),
    );
  }

  Widget _results(BuildContext context, AsyncValue<List<CardModel>>? async) {
    if (async == null) {
      return _hint(
        context,
        'Ketik minimal $_minQuery huruf untuk mencari kartu.',
      );
    }

    return async.when(
      loading: () => const PikachuLoader(),
      error: (_, __) => _hint(context, 'Gagal mencari kartu.'),
      data: (cards) {
        if (cards.isEmpty) {
          return _hint(context, 'Tidak ada kartu yang cocok.');
        }
        final sorted = sortCards(cards, _sort);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: [
                  Text(
                    '${sorted.length} kartu cocok',
                    style: AppTypography.bodySm(context.mutedForeground),
                  ),
                  const Spacer(),
                  _SortButton(
                    sort: _sort,
                    onChanged: (s) => setState(() => _sort = s),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.55,
                ),
                itemCount: sorted.length,
                itemBuilder: (context, i) {
                  final card = sorted[i];
                  return _PickTile(
                    card: card,
                    selected: _selected.any((c) => c.id == card.id),
                    onTap: () => _toggle(card),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _hint(BuildContext context, String message) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: AppTypography.bodySm(context.mutedForeground),
      ),
    ),
  );
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      autofocus: true,
      style: AppTypography.bodySm(context.appColors.onSurface),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Cari nama kartu...',
        hintStyle: AppTypography.bodySm(context.mutedForeground),
        filled: true,
        fillColor: Theme.of(context).scaffoldBackgroundColor,
        prefixIcon: Icon(
          LucideIcons.search,
          size: 18,
          color: context.mutedForeground,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 42),
        suffixIcon: ValueListenableBuilder(
          valueListenable: controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(LucideIcons.x, size: 16),
                  onPressed: onClear,
                ),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: context.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: context.borderColor),
        ),
      ),
    );
  }
}

/// What has been picked so far, and the way back out of each one.
class _SelectedStrip extends StatelessWidget {
  const _SelectedStrip({
    required this.selected,
    required this.onRemove,
    required this.onClearAll,
  });

  final List<CardModel> selected;
  final ValueChanged<CardModel> onRemove;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Text(
                'Terpilih',
                style: AppTypography.bodySmSemibold(colors.onSurface),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.onSurface,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  '${selected.length}',
                  style: AppTypography.badge(Theme.of(context).cardColor),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onClearAll,
                child: const Text('Hapus semua'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 74,
          child: Row(
            children: [
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: selected.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => _SelectedThumb(
                    card: selected[i],
                    onRemove: () => onRemove(selected[i]),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                    'Ketuk kartu di bawah untuk menambah atau melepas',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SelectedThumb extends StatelessWidget {
  const _SelectedThumb({required this.card, required this.onRemove});

  final CardModel card;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CardArt(imageUrl: card.imageUrl),
          Positioned(
            right: -6,
            top: -6,
            child: Semantics(
              button: true,
              label: 'Lepas ${card.name}',
              child: InkWell(
                onTap: onRemove,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: context.appColors.onSurface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).cardColor,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    LucideIcons.x,
                    size: 11,
                    color: Theme.of(context).cardColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One card in the grid. Ticked cards carry a heavy border rather than a
/// tint — the artwork is the thing being recognised, and a wash over it
/// changes the colours the seller is reading the card by.
class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.card,
    required this.selected,
    required this.onTap,
  });

  final CardModel card;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Loose, so the artwork gives up a pixel rather than the tile
          // overflowing: the two caption rows below are text, and text is
          // exactly the part whose height no fixed ratio can predict across
          // fonts and text-size settings.
          Flexible(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: selected ? colors.onSurface : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: CardArt(imageUrl: card.imageUrl),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              CardLanguageBadge(language: card.language, size: 12),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  card.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.captionSemibold(colors.onSurface),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Flexible(
                child: Text(
                  card.collectorNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  card.expansionCode.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onChanged});

  final CardSortOption sort;
  final ValueChanged<CardSortOption> onChanged;

  static const _offered = [
    CardSortOption.setDesc,
    CardSortOption.nameAsc,
    CardSortOption.numberAsc,
  ];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<CardSortOption>(
      initialValue: sort,
      tooltip: 'Urutkan',
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in _offered)
          PopupMenuItem(value: option, child: Text(option.label)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.arrowUpDown,
              size: 13,
              color: context.mutedForeground,
            ),
            const SizedBox(width: 6),
            Text(
              sort.label,
              style: AppTypography.captionSemibold(context.appColors.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one way out of the sheet that does anything.
class _AddBar extends StatelessWidget {
  const _AddBar({required this.count, required this.busy, required this.onTap});

  final int count;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final success = context.appSemantic.success;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onTap,
                icon: busy
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.plus, size: 18),
                label: Text('Tambahkan $count kartu ke Draft'),
                style: FilledButton.styleFrom(
                  backgroundColor: success,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Harga, kondisi & foto bisa diatur setelah ditambahkan',
              style: AppTypography.caption(context.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}
