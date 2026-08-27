import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../models/card_model.dart';
import 'card_art.dart';

/// Ports the grid-mode branch of `components/card/card-item.tsx` — a
/// catalog card tile showing artwork, name/number, market price and an
/// "owned" indicator.
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardArt(imageUrl: card.imageUrl),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    card.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                ),
                Text(
                  card.collectorNumber,
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
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
    );
  }
}
