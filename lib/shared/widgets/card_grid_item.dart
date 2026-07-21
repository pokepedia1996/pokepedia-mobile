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
            Stack(
              children: [
                CardArt(imageUrl: card.imageUrl),
                if (owned)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: _OwnedBadge(quantity: card.owned),
                  ),
              ],
            ),
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
            Text(
              card.marketPrice != null
                  ? formatRupiah(card.marketPrice!)
                  : 'Rp-',
              style: AppTypography.bodySmSemibold(colors.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnedBadge extends StatelessWidget {
  const _OwnedBadge({required this.quantity});

  final int quantity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.appSemantic.success,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text('×$quantity', style: AppTypography.badge(Colors.white)),
    );
  }
}
