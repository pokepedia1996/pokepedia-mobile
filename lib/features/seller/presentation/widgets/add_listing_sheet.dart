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

/// `add_listing_draft` clamps to this, so the stepper stops where the server
/// would rather than letting a seller type past it and be silently corrected.
const _maxQuantity = 99;

/// The grid's cell size, measured rather than fixed as an aspect ratio.
///
/// A tile is artwork at a fixed 245:342 plus rows of text and a stepper,
/// whose heights do not scale with the screen — so one `childAspectRatio` is
/// only ever right on one device width. The 0.55 here was already tight
/// before the tile grew a stepper row.
SliverGridDelegate _tileGrid(BuildContext context) {
  const columns = 3;
  const spacing = 10.0;
  final width = MediaQuery.sizeOf(context).width;
  final cell = (width - 32 - spacing * (columns - 1)) / columns;

  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    crossAxisSpacing: spacing,
    mainAxisSpacing: 12,
    // Artwork, the two caption rows, the stepper, and the gaps between.
    mainAxisExtent: cell * 342 / 245 + 84,
  );
}

/// One picked card and how many copies of it are going to Draft.
class _Pick {
  _Pick(this.card);

  final CardModel card;

  /// A pick starts at one copy — the tap that created it.
  int quantity = 1;
}

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

  /// Which catalog language to search in, or null for all of them.
  ///
  /// The same card is printed in three languages and a seller is holding
  /// exactly one of them: without this, finding the Japanese print of a
  /// common Pikachu means scrolling past every other print of it.
  CardLanguage? _language;

  /// The pick, in the order it was made, so the strip at the top reads as a
  /// history of what was tapped rather than reshuffling on every addition.
  final List<_Pick> _selected = [];

  /// How many copies, across every picked card — what actually lands in the
  /// draft list.
  int get _copies => _selected.fold(0, (sum, pick) => sum + pick.quantity);

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

  /// One more copy of [card] — the tile's whole tap target, and its +.
  ///
  /// Tapping a picked card used to unpick it, which made the commonest
  /// action on this screen (a playset: four of the same card) four taps
  /// that ended with nothing selected.
  void _add(CardModel card) {
    setState(() {
      final at = _selected.indexWhere((p) => p.card.id == card.id);
      if (at < 0) {
        _selected.add(_Pick(card));
      } else if (_selected[at].quantity < _maxQuantity) {
        _selected[at].quantity++;
      }
    });
  }

  /// One fewer. The last one takes the card out of the pick entirely, so the
  /// stepper's − is also the way to undo a mistap.
  void _removeOne(CardModel card) {
    setState(() {
      final at = _selected.indexWhere((p) => p.card.id == card.id);
      if (at < 0) return;
      if (_selected[at].quantity > 1) {
        _selected[at].quantity--;
      } else {
        _selected.removeAt(at);
      }
    });
  }

  void _drop(CardModel card) {
    setState(() => _selected.removeWhere((p) => p.card.id == card.id));
  }

  int _quantityOf(CardModel card) {
    for (final pick in _selected) {
      if (pick.card.id == card.id) return pick.quantity;
    }
    return 0;
  }

  Future<void> _addToDraft() async {
    if (_selected.isEmpty || _saving) return;
    setState(() => _saving = true);

    final result = await ref.read(sellerListingsRepositoryProvider).addDrafts([
      for (final pick in _selected)
        (cardId: pick.card.id, quantity: pick.quantity),
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
        ? ref.watch(
            cardSearchPickerProvider((query: _query, language: _language)),
          )
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
            _LanguageChips(
              value: _language,
              onChanged: (next) => setState(() => _language = next),
            ),
            // Out of the way while typing: with the keyboard up the strip
            // took most of what was left above it, so the results showed one
            // row and picking another card meant dismissing the keyboard
            // first. The bar below still counts what has been picked.
            if (_selected.isNotEmpty &&
                MediaQuery.viewInsetsOf(context).bottom == 0)
              _SelectedStrip(
                selected: _selected,
                onRemove: _drop,
                onClearAll: () => setState(_selected.clear),
              ),
            Expanded(child: _results(context, async)),
            if (_selected.isNotEmpty)
              _AddBar(
                cards: _selected.length,
                copies: _copies,
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
                gridDelegate: _tileGrid(context),
                itemCount: sorted.length,
                itemBuilder: (context, i) {
                  final card = sorted[i];
                  return _PickTile(
                    card: card,
                    quantity: _quantityOf(card),
                    onAdd: () => _add(card),
                    onRemove: () => _removeOne(card),
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

/// Semua / ID / EN / JP, above the results.
///
/// A row of chips rather than a dropdown: there are four of them, the
/// current one has to be readable at a glance while scrolling the grid, and
/// switching is the thing a seller does repeatedly while working through a
/// binder of mixed prints.
class _LanguageChips extends StatelessWidget {
  const _LanguageChips({required this.value, required this.onChanged});

  final CardLanguage? value;
  final ValueChanged<CardLanguage?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        children: [
          _LanguageChip(
            label: 'Semua',
            selected: value == null,
            onTap: () => onChanged(null),
          ),
          for (final language in CardLanguage.values) ...[
            const SizedBox(width: 8),
            _LanguageChip(
              label: language.shortLabel,
              selected: value == language,
              onTap: () => onChanged(language),
            ),
          ],
        ],
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
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
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          // The brand colour, not the near-black used for the sheet's
          // structural controls: this is a choice the seller has made, and
          // it should read as theirs rather than as more chrome.
          color: selected ? colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: selected ? colors.primary : context.borderColor,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.captionSemibold(
            selected ? colors.onPrimary : colors.onSurface,
          ),
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

  final List<_Pick> selected;
  final ValueChanged<CardModel> onRemove;
  final VoidCallback onClearAll;

  int get _copies => selected.fold(0, (sum, pick) => sum + pick.quantity);

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
              // The three labels share what is left after the button, and
              // the copies count is the one that gives way: it repeats what
              // the bar at the foot of the sheet already says.
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Terpilih',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmSemibold(colors.onSurface),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.onSurface,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        '${selected.length}',
                        style: AppTypography.badge(Theme.of(context).cardColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Cards and copies are different numbers as soon as
                    // anything is picked twice, and the one that decides the
                    // work ahead is the copies.
                    Flexible(
                      child: Text(
                        '$_copies lembar',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                    ),
                  ],
                ),
              ),
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
                    pick: selected[i],
                    onRemove: () => onRemove(selected[i].card),
                  ),
                ),
              ),
              // Only beside the first pick. It shared the row half and half,
              // so from the second card on the thumbnails ran in under it;
              // by then the tapping has been learned and the room is theirs.
              if (selected.length == 1)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      'Ketuk kartu untuk menambah, atur jumlahnya di bawah',
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
  const _SelectedThumb({required this.pick, required this.onRemove});

  final _Pick pick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final card = pick.card;

    return SizedBox(
      width: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CardArt(imageUrl: card.imageUrl),
          Positioned(
            left: 2,
            bottom: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: context.appColors.onSurface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                'x${pick.quantity}',
                style: AppTypography.badge(Theme.of(context).cardColor),
              ),
            ),
          ),
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
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final CardModel card;

  /// How many copies are picked — 0 when the card is not in the pick.
  final int quantity;

  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selected = quantity > 0;

    return GestureDetector(
      onTap: onAdd,
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
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    CardArt(imageUrl: card.imageUrl),
                    if (selected)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: context.appSemantic.success,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            LucideIcons.check,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
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
          const SizedBox(height: 4),
          // The stock decision, made here rather than on the draft card
          // afterwards: the seller counting copies is holding them now.
          selected
              ? _QuantityStepper(
                  quantity: quantity,
                  onAdd: onAdd,
                  onRemove: onRemove,
                )
              : _AddChip(onTap: onAdd),
        ],
      ),
    );
  }
}

/// The unpicked tile's button. Says what the tap does, which the artwork
/// alone cannot.
class _AddChip extends StatelessWidget {
  const _AddChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _stepperHeight,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(LucideIcons.plus, size: 13),
        label: const Text('Tambah'),
        style: OutlinedButton.styleFrom(
          foregroundColor: context.appColors.onSurface,
          side: BorderSide(color: context.borderColor),
          padding: EdgeInsets.zero,
          minimumSize: const Size.fromHeight(_stepperHeight),
          textStyle: AppTypography.caption(context.appColors.onSurface),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
    );
  }
}

const _stepperHeight = 30.0;

/// − n + under a picked tile.
class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      height: _stepperHeight,
      decoration: BoxDecoration(
        color: colors.onSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          _StepperButton(
            icon: LucideIcons.minus,
            // Also the way out of the pick: at one copy this drops the card.
            semantics: quantity > 1 ? 'Kurangi jumlah' : 'Lepas dari pilihan',
            onTap: onRemove,
          ),
          Expanded(
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: AppTypography.captionSemibold(Theme.of(context).cardColor),
            ),
          ),
          _StepperButton(
            icon: LucideIcons.plus,
            semantics: 'Tambah jumlah',
            onTap: quantity < _maxQuantity ? onAdd : null,
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.semantics,
    required this.onTap,
  });

  final IconData icon;
  final String semantics;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Theme.of(context).cardColor;

    return Semantics(
      button: true,
      label: semantics,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          width: 28,
          height: _stepperHeight,
          child: Icon(
            icon,
            size: 14,
            color: onTap == null ? card.withValues(alpha: 0.4) : card,
          ),
        ),
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
  const _AddBar({
    required this.cards,
    required this.copies,
    required this.busy,
    required this.onTap,
  });

  final int cards;
  final int copies;
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
                label: Text(
                  cards == copies
                      ? 'Tambahkan $cards kartu ke Draft'
                      : 'Tambahkan $cards kartu · $copies lembar ke Draft',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
