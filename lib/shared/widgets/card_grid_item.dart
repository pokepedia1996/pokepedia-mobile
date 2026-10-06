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

/// The grid geometry [CardGridItem] needs, computed from the cell width
/// rather than set as a fixed aspect ratio — the same reasoning as
/// `listingGridDelegate`.
///
/// A tile is artwork (a fixed 245:342) plus rows of text whose height does
/// not scale with the screen, so one `childAspectRatio` can only be right on
/// one device width: the 0.62 these grids used was already within a couple
/// of points of overflowing before the tile grew its expansion row.
///
/// The chrome constant is measured in `test/card_grid_item_height_test.dart`,
/// which fails the build if the tile outgrows it.
SliverGridDelegate cardGridDelegate(
  BuildContext context, {
  int columns = 2,
  double spacing = 12,
  double horizontalPadding = 16,
  double extraChrome = 0,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final cell =
      (width - horizontalPadding * 2 - spacing * (columns - 1)) / columns;

  // The artwork sits inside the tile's 10pt horizontal padding.
  final art = (cell - 20) * 342 / 245;

  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    mainAxisSpacing: spacing,
    crossAxisSpacing: spacing,
    mainAxisExtent: art + cardGridItemChrome + extraChrome,
  );
}

/// Everything in the tile that isn't artwork: the name, expansion and
/// price rows, the gaps between them, and the tile's vertical padding.
///
/// Measured, not guessed — `card_grid_item_height_test` needs about 106 in
/// the test harness's square fallback font since the variant line (a 17pt
/// caption) joined the tile, so 111 keeps a few points in hand for a row
/// that grows by a point or two.
const cardGridItemChrome = 111.0;

/// What a tile grows by when it carries a [CardGridItem.footer]: a `sm`
/// [QuantitySelector] and the gap above it. Pass it to [cardGridDelegate] as
/// `extraChrome` whenever the grid's tiles have footers.
const cardGridItemFooterChrome = 32.0;

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
  /// A grid with footers must add [cardGridItemFooterChrome] to its delegate.
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
        child: Column(
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

            // Row 1b — the finish, web's italic `VariantLabel`. The line is
            // held even for the plain print: the grid gives every tile one
            // fixed height, and a row that came and went would push the plain
            // tiles' prices out of line with their neighbours'.
            Text(
              card.variantLabel ?? '',
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
      ),
    );
  }
}
