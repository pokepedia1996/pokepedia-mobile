import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../models/card_model.dart';
import 'card_art.dart';

/// Ports the list-mode branch of `components/card/card-item.tsx` — a
/// compact row (thumbnail, name/number, price and the quantity held) used
/// when `ViewToggle` is set to list.
class CardListItem extends StatelessWidget {
  const CardListItem({super.key, required this.card, required this.onTap});

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
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          children: [
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
                  Row(
                    children: [
                      Text(
                        card.marketPrice != null
                            ? formatRupiah(card.marketPrice!)
                            : 'Rp-',
                        style: AppTypography.bodySmSemibold(colors.onSurface),
                      ),
                      const Spacer(),
                      if (owned)
                        Text(
                          'Qty: ${card.owned}',
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                    ],
                  ),
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
