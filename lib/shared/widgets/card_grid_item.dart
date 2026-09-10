import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../models/card_model.dart';
import 'card_art.dart';
import 'card_language_badge.dart';
import 'card_price_note.dart';

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
    mainAxisExtent: art + cardGridItemChrome,
  );
}

/// Everything in the tile that isn't artwork: the name, expansion and
/// price rows, the gaps between them, and the tile's vertical padding.
///
/// Measured, not guessed — `card_grid_item_height_test` needs between 86 and
/// 90 in the test harness's square fallback font, so 94 keeps a few points
/// in hand for a row that grows by a point or two.
const cardGridItemChrome = 94.0;

/// Ports the grid-mode branch of `components/card/card-item.tsx` — a
/// catalog card tile showing artwork, name, where the print is from, the
/// market price and how many are held.
///
/// Laid out like the marketplace's [ListingCard]: the name on a line of its
/// own, then language / expansion / number, then the price row. The price
/// carries web's `font-bold tabular-nums` so it reads as the number on the
/// tile rather than as a second caption under the name.
class CardGridItem extends StatelessWidget {
  const CardGridItem({super.key, required this.card, required this.onTap});

  final CardModel card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final owned = card.owned > 0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardArt(imageUrl: card.imageUrl),
            const SizedBox(height: 8),

            // Row 1 — the card's name, on a line of its own.
            Text(
              card.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmSemibold(colors.onSurface),
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

            // Row 3 — how many are held, then the price and its week on the
            // right edge. The quantity is the incidental half, so the price
            // is the one that gets the tile's edge to line up against.
            Row(
              children: [
                if (owned)
                  Text(
                    'Qty: ${card.owned}',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        card.marketPrice != null
                            ? formatRupiah(card.marketPrice!)
                            : 'Rp-',
                        maxLines: 1,
                        style: AppTypography.price(colors.onSurface),
                      ),
                      // Only the note gives way when the row runs out of
                      // room — it scales itself down inside this box. The
                      // price is never flexed: a price that had to shrink or
                      // clip to fit is a number the reader can't trust.
                      Flexible(child: CardPriceNote(card: card)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
