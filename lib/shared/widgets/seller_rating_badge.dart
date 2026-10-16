import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../models/listing_model.dart';
import 'reputation_star.dart';

/// The rating line under a seller's name on card listing rows: the tiered
/// reputation star with its score, then the sales count — or "Penjual baru"
/// for a seller with neither. Web's `SellerRatingBadge` leads with a
/// positive %, which mobile drops in favour of the star used everywhere
/// else in the app; the review breakdown it shows on hover is the
/// long-press tooltip here.
class SellerRatingBadge extends StatelessWidget {
  const SellerRatingBadge({super.key, required this.score, this.rating});

  /// The seller's feedback score (`positive − negative`), as on the star.
  final int score;

  /// Null reads as a seller without a reputation row.
  final SellerRating? rating;

  /// Nothing worth showing yet: no sales, and a score still in the star's
  /// hollow "new" tier.
  bool get isNew =>
      (rating?.totalSales ?? 0) == 0 && reputationTier(score).isNew;

  @override
  Widget build(BuildContext context) {
    final muted = AppTypography.caption(context.mutedForeground);
    if (isNew) return Text('Penjual baru', style: muted);

    final sales = rating?.totalSales ?? 0;
    final line = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ReputationStar(score: score, showCount: false),
        const SizedBox(width: 3),
        Text(
          formatCountId(score),
          style: AppTypography.captionSemibold(context.appColors.onSurface),
        ),
        if (sales > 0)
          Flexible(
            child: Text(
              ' · ${formatCountId(sales)} penjualan',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          ),
      ],
    );

    final r = rating;
    if (r == null) return line;
    return Tooltip(
      message:
          '${r.positiveCount} Positif · ${r.neutralCount} Netral · '
          '${r.negativeCount} Negatif',
      child: line,
    );
  }
}
