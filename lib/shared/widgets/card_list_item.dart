import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../models/card_model.dart';
import 'card_art.dart';
import 'card_price_note.dart';
import 'selection_mark.dart';

/// Ports the list-mode branch of `components/card/card-item.tsx` — a
/// compact row (thumbnail, name/number, price and the quantity held) used
/// when `ViewToggle` is set to list.
class CardListItem extends StatelessWidget {
  const CardListItem({
    super.key,
    required this.card,
    required this.onTap,
    this.footer,
    this.selected,
  });

  final CardModel card;
  final VoidCallback onTap;

  /// An extra row under the price — where edit mode puts the quantity
  /// stepper, the same as [CardGridItem.footer].
  final Widget? footer;

  /// Whether the row is ticked in a multi-select list, or null when the
  /// list isn't selecting.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final owned = card.owned > 0;
    final selected = this.selected;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected == true ? colors.primary : context.borderColor,
            width: selected == true ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // A row has a leading edge to spare, so the tick takes it
            // rather than covering the thumbnail.
            if (selected != null) ...[
              SelectionMark(selected: selected, size: 20),
              const SizedBox(width: 10),
            ],
            SizedBox(
              width: 48,
              child: CardArt(
                imageUrl: card.imageUrl,
                borderRadius: AppRadius.sm,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    card.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  Text(
                    card.collectorNumber,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                  const SizedBox(height: 2),
                  // Quantity on the left, price on the right — the same
                  // reading order as the grid tile.
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
                            Flexible(child: CardPriceNote(card: card)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (footer != null) ...[const SizedBox(height: 6), footer!],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: context.borderColor),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(
                card.expansionCode,
                style: AppTypography.caption(context.mutedForeground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
