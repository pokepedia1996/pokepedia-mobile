import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../models/listing_model.dart';

/// Ports `SellerRatingBadge` (`features/card-detail/components/
/// seller-rating-badge.tsx`): a green thumbs-up with the positive share,
/// then the sales count — or "Penjual baru" for a seller nobody has rated.
/// The review breakdown web shows on hover is the long-press tooltip here.
class SellerRatingBadge extends StatelessWidget {
  const SellerRatingBadge({super.key, required this.rating});

  /// Null reads as a new seller, as a missing reputation row does on web.
  final SellerRating? rating;

  /// Web's `pct.toFixed(pct % 1 === 0 ? 0 : 1)`.
  static String percentLabel(double pct) =>
      '${pct.toStringAsFixed(pct % 1 == 0 ? 0 : 1)}%';

  @override
  Widget build(BuildContext context) {
    final muted = AppTypography.caption(context.mutedForeground);
    final pct = rating?.positivePct;
    if (rating == null || pct == null) {
      return Text('Penjual baru', style: muted);
    }

    final success = context.appSemantic.success;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message:
              '${rating!.positiveCount} Positif · ${rating!.neutralCount} '
              'Netral · ${rating!.negativeCount} Negatif',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.thumbsUp, size: 12, color: success),
              const SizedBox(width: 3),
              Text(percentLabel(pct), style: AppTypography.caption(success)),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            rating!.totalSales > 0
                ? '${rating!.totalSales} penjualan'
                : 'Penjual baru',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
        ),
      ],
    );
  }
}
