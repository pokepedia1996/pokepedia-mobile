import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// Ports `getReputationTier` from `lib/seller/reputation-star.ts`.
///
/// [hasTrail] marks the tiers web draws a comet trail behind — every tier at
/// 10,000 and above.
({Color color, bool isNew, bool hasTrail}) reputationTier(int score) {
  if (score < 10) {
    return (color: const Color(0xFFD1D5DB), isNew: true, hasTrail: false);
  }
  const thresholds = [
    (1000000, Color(0xFFC0C0C0), true),
    (500000, Color(0xFF16A34A), true),
    (100000, Color(0xFFDC2626), true),
    (50000, Color(0xFF9333EA), true),
    (25000, Color(0xFF14B8B8), true),
    (10000, Color(0xFFFFCC00), true),
    (5000, Color(0xFF16A34A), false),
    (1000, Color(0xFFDC2626), false),
    (500, Color(0xFF9333EA), false),
    (100, Color(0xFF14B8B8), false),
    (50, Color(0xFF3B82F6), false),
    (10, Color(0xFFFFCC00), false),
  ];
  for (final (min, color, trail) in thresholds) {
    if (score >= min) return (color: color, isNew: false, hasTrail: trail);
  }
  return (color: const Color(0xFFFFCC00), isNew: false, hasTrail: false);
}

/// Ports `components/seller/reputation-star.tsx`.
///
/// Drawn rather than taken from the icon set: web's star is filled with the
/// tier colour for an established seller and left hollow for a new one, and
/// Lucide ships only the outline glyph — so an icon could never show the
/// difference. This paints web's own star path, which also keeps the two
/// surfaces on the same geometry instead of two vendors' idea of a star.
class ReputationStar extends StatelessWidget {
  const ReputationStar({
    super.key,
    required this.score,
    this.size = 12,
    this.showCount = true,
  });

  final int score;
  final double size;
  final bool showCount;

  @override
  Widget build(BuildContext context) {
    final tier = reputationTier(score);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size.square(size),
          painter: _StarPainter(
            color: tier.color,
            filled: !tier.isNew,
            trail: tier.hasTrail,
          ),
        ),
        if (showCount) ...[
          const SizedBox(width: 2),
          Text('$score', style: AppTypography.caption(context.mutedForeground)),
        ],
      ],
    );
  }
}

/// The 5-point star from `reputation-star.tsx`: outer R=9, inner r=3.8,
/// centred at (10,10) in a 20x20 box. The coordinates are web's verbatim so
/// the shape can't drift from it.
class _StarPainter extends CustomPainter {
  const _StarPainter({
    required this.color,
    required this.filled,
    required this.trail,
  });

  final Color color;
  final bool filled;
  final bool trail;

  static const _points = <Offset>[
    Offset(10, 1),
    Offset(12.23, 6.93),
    Offset(18.56, 7.22),
    Offset(13.61, 11.17),
    Offset(15.29, 17.28),
    Offset(10, 13.8),
    Offset(4.71, 17.28),
    Offset(6.39, 11.17),
    Offset(1.44, 7.22),
    Offset(7.77, 6.93),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 20;
    canvas.save();
    canvas.scale(scale);

    if (trail) {
      // The two quadratic strokes web puts behind the high tiers.
      final trailPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.65)
        ..strokeWidth = 1.8;
      canvas.drawPath(
        Path()
          ..moveTo(1, 14)
          ..quadraticBezierTo(3, 10.5, 5.5, 8),
        trailPaint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(2.5, 16.5)
          ..quadraticBezierTo(4.5, 13, 7, 11),
        trailPaint
          ..color = color.withValues(alpha: 0.4)
          ..strokeWidth = 1.2,
      );
    }

    final star = Path()..addPolygon(_points, true);
    if (filled) {
      canvas.drawPath(star, Paint()..color = color);
    } else {
      // A new seller's star is hollow, outlined at web's 1.5.
      canvas.drawPath(
        star,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StarPainter old) =>
      old.color != color || old.filled != filled || old.trail != trail;
}
