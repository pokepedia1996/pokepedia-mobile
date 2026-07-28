import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// Ports `getReputationTier` from `lib/seller/reputation-star.ts`, minus its
/// decorative comet-trail SVG paths — the tier color + count is what
/// actually carries meaning for a seller's reputation at this size.
({Color color, bool isNew}) reputationTier(int score) {
  if (score < 10) return (color: const Color(0xFFD1D5DB), isNew: true);
  const thresholds = [
    (1000000, Color(0xFFC0C0C0)),
    (500000, Color(0xFF16A34A)),
    (100000, Color(0xFFDC2626)),
    (50000, Color(0xFF9333EA)),
    (25000, Color(0xFF14B8B8)),
    (10000, Color(0xFFFFCC00)),
    (5000, Color(0xFF16A34A)),
    (1000, Color(0xFFDC2626)),
    (500, Color(0xFF9333EA)),
    (100, Color(0xFF14B8B8)),
    (50, Color(0xFF3B82F6)),
    (10, Color(0xFFFFCC00)),
  ];
  for (final (min, color) in thresholds) {
    if (score >= min) return (color: color, isNew: false);
  }
  return (color: const Color(0xFFFFCC00), isNew: false);
}

/// Ports `components/store/reputation-star.tsx`.
class ReputationStar extends StatelessWidget {
  const ReputationStar({super.key, required this.score, this.size = 12});

  final int score;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tier = reputationTier(score);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(tier.isNew ? Icons.star_border : Icons.star, size: size, color: tier.color),
        const SizedBox(width: 2),
        Text('$score', style: AppTypography.caption(context.mutedForeground)),
      ],
    );
  }
}
