import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../models/card_model.dart';
import 'card_art.dart';
import 'card_language_badge.dart';
import 'card_price_note.dart';
import 'selection_mark.dart';

/// Everything in a tile that isn't artwork or the variant line: the name,
/// expansion and price rows, the gaps between them, and the tile's vertical
/// padding.
///
/// Measured, not guessed — `card_grid_item_height_test` needs about 89 in
/// the test harness's square fallback font, so 94 keeps a few points in hand
/// for a row that grows by a point or two.
const cardGridItemChrome = 94.0;

/// The italic variant line ("Holo Pokeball"), a 17pt caption. Only rows
/// holding a card that has one are given it.
const cardGridVariantChrome = 17.0;

/// What a tile grows by when it carries a [CardGridItem.footer]: a `sm`
/// [QuantitySelector] and the gap above it. Pass it as `extraChrome` whenever
/// the grid's tiles have footers.
const cardGridItemFooterChrome = 32.0;

/// How tall a row of [CardGridItem]s is for a cell [cellWidth] wide.
///
/// Per row rather than one height for the whole grid: a tile is artwork (a
/// fixed 245:342) plus text, and only some cards have a variant line. Sized
/// for the tallest case everywhere, every plain print sat over a blank band;
/// sized per row, a row of plain prints is exactly as tall as it needs.
double cardGridRowExtent(
  double cellWidth, {
  required bool hasVariant,
  double extraChrome = 0,
}) {
  // The artwork sits inside the tile's 10pt horizontal padding.
  final art = (cellWidth - 20) * 342 / 245;
  return art +
      cardGridItemChrome +
      (hasVariant ? cardGridVariantChrome : 0) +
      extraChrome;
}

/// One row of a card grid: [columns] cells, as tall as the row's tallest
/// tile needs — see [cardGridRowExtent].
class _CardGridRow extends StatelessWidget {
  const _CardGridRow({
    required this.start,
    required this.itemCount,
    required this.itemBuilder,
    required this.hasVariant,
    required this.columns,
    required this.spacing,
    required this.extraChrome,
  });

  final int start;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool Function(int index) hasVariant;
  final int columns;
  final double spacing;
  final double extraChrome;

  @override
  Widget build(BuildContext context) {
    final end = (start + columns).clamp(0, itemCount);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        final height = cardGridRowExtent(
          cell,
          hasVariant: [
            for (var i = start; i < end; i++) hasVariant(i),
          ].any((v) => v),
          extraChrome: extraChrome,
        );
        return SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) SizedBox(width: spacing),
                Expanded(
                  child: start + c < end
                      ? itemBuilder(context, start + c)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A lazily built grid of [CardGridItem]s whose rows each fit their own
/// tiles. Takes the place of a `SliverGrid` with one fixed extent.
///
/// [hasVariant] says whether the tile at an index draws the variant line —
/// usually `(i) => cards[i].variantLabel != null`. An index with something
/// else in it, like a "load more" cell, answers false.
class SliverCardGrid extends StatelessWidget {
  const SliverCardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.hasVariant,
    this.columns = 2,
    this.spacing = 12,
    this.extraChrome = 0,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool Function(int index) hasVariant;
  final int columns;
  final double spacing;
  final double extraChrome;

  @override
  Widget build(BuildContext context) {
    final rows = (itemCount / columns).ceil();
    return SliverList.builder(
      itemCount: rows,
      // A tile holds nothing worth keeping once it is off screen.
      addAutomaticKeepAlives: false,
      itemBuilder: (context, r) => Padding(
        padding: EdgeInsets.only(bottom: r == rows - 1 ? 0 : spacing),
        child: _CardGridRow(
          start: r * columns,
          itemCount: itemCount,
          itemBuilder: itemBuilder,
          hasVariant: hasVariant,
          columns: columns,
          spacing: spacing,
          extraChrome: extraChrome,
        ),
      ),
    );
  }
}

/// [SliverCardGrid] for a page that isn't a sliver list — every row built up
/// front, the way the `shrinkWrap` grids it replaces were.
class CardGridRows extends StatelessWidget {
  const CardGridRows({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.hasVariant,
    this.columns = 2,
    this.spacing = 12,
    this.extraChrome = 0,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool Function(int index) hasVariant;
  final int columns;
  final double spacing;
  final double extraChrome;

  @override
  Widget build(BuildContext context) {
    final rows = (itemCount / columns).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < rows; r++) ...[
          if (r > 0) SizedBox(height: spacing),
          _CardGridRow(
            start: r * columns,
            itemCount: itemCount,
            itemBuilder: itemBuilder,
            hasVariant: hasVariant,
            columns: columns,
            spacing: spacing,
            extraChrome: extraChrome,
          ),
        ],
      ],
    );
  }
}

/// Ports the grid-mode branch of `components/card/card-item.tsx` — a
/// catalog card tile showing artwork, name, where the print is from, the
/// market price and how many are held.
///
/// Laid out like the marketplace's [ListingCard]: the name on a line of its
/// own, then language / expansion / number, then the price row. The price
/// carries web's `font-bold tabular-nums` so it reads as the number on the
/// tile rather than as a second caption under the name.
class CardGridItem extends StatelessWidget {
  const CardGridItem({
    super.key,
    required this.card,
    required this.onTap,
    this.footer,
    this.selected,
  });

  final CardModel card;
  final VoidCallback onTap;

  /// An extra row under the price — web's edit mode puts the quantity
  /// stepper here, in the tile's flow rather than floating over its text.
  /// A grid with footers must pass [cardGridItemFooterChrome] as its
  /// `extraChrome`.
  final Widget? footer;

  /// Whether the tile is ticked in a multi-select grid, or null when the
  /// grid isn't selecting. The border carries it and a mark sits on the art;
  /// nothing tints the tile, so the card itself still reads normally.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final owned = card.owned > 0;
    final selected = this.selected;
    final radius = BorderRadius.circular(AppRadius.lg);

    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: radius,
          border: Border.all(
            color: selected == true ? colors.primary : context.borderColor,
            width: selected == true ? 2 : 1,
          ),
        ),
        // Two halves pushed apart: in a row whose neighbour has a variant
        // line and this card doesn't, the spare line opens up under the name
        // and the price and stepper stay level with the neighbour's.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (selected == null)
                  CardArt(imageUrl: card.imageUrl)
                else
                  Stack(
                    children: [
                      CardArt(imageUrl: card.imageUrl),
                      // Top-right: a Pokémon card's own art is busiest at the
                      // top-left, where the evolution box sits.
                      Positioned(
                        top: 6,
                        right: 6,
                        child: SelectionMark(selected: selected),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),

                // Row 1 — the card's name, on a line of its own.
                Text(
                  card.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),

                // Row 1b — the finish, web's italic `VariantLabel`, only when
                // there is one. The plain print used to hold an empty line here
                // to keep prices level across a row, which read as a gap under
                // every name. The grid's height still allows for the line, so a
                // tile that has one fits and one that doesn't has room to spare.
                if (card.variantLabel case final label?)
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(
                      context.mutedForeground.withValues(alpha: 0.7),
                    ).copyWith(fontStyle: FontStyle.italic),
                  ),
                const SizedBox(height: 3),

                // Row 2 — where the print is from: language, expansion, number.
                Row(
                  children: [
                    CardLanguageBadge(language: card.language, size: 14),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        card.expansionCode.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        card.collectorNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 3),

                // Row 3 — the price, then its week's move, then how many are
                // held. The price leads the row rather than sitting against the
                // tile's right edge: it is the number every tile is read for,
                // and a column of prices that all start in the same place can be
                // compared down the grid without reading each one.
                Row(
                  children: [
                    Text(
                      card.marketPrice != null
                          ? formatRupiah(card.marketPrice!)
                          : 'Rp-',
                      maxLines: 1,
                      style: AppTypography.price(colors.onSurface),
                    ),
                    // Only the note gives way when the row runs out of room — it
                    // scales itself down inside this box. The price is never
                    // flexed: a price that had to shrink or clip to fit is a
                    // number the reader can't trust.
                    Flexible(child: CardPriceNote(card: card)),
                    // The count is the incidental half, so it takes the edge the
                    // price gave up. A tile with a stepper below says it there
                    // instead, and this would only repeat it.
                    if (owned && footer == null) ...[
                      const SizedBox(width: 6),
                      // Flexed so a long price and a trend beside it push this
                      // out of the way rather than off the tile — it is the one
                      // thing in the row the reader can do without.
                      Flexible(
                        child: Text(
                          'Qty: ${card.owned}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ),
                    ],
                  ],
                ),
                if (footer != null) ...[const SizedBox(height: 6), footer!],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
