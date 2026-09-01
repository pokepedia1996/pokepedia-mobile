import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';

/// The card-shaped cutout the user aligns against.
///
/// This is not decoration — it *is* the detector. Capture crops exactly this
/// rectangle and the embedder compares the result against catalog renders with
/// no further localization, so how faithfully the user fills the box is
/// directly how well recognition works. Hence the deliberately loud framing:
/// a dimmed surround that makes the live region unmistakable, and corner
/// brackets that give the card's edges something to be aligned to.
class ScanGuideOverlay extends StatelessWidget {
  const ScanGuideOverlay({
    super.key,
    required this.guideRect,
    this.hint = 'Posisikan kartu memenuhi bingkai',
  });

  final Rect guideRect;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _GuidePainter(guideRect)),
          ),
          Positioned(
            top: guideRect.bottom + 16,
            left: 24,
            right: 24,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: AppTypography.caption(Colors.white.withValues(
                    alpha: 0.92,
                  )),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter(this.guideRect);

  final Rect guideRect;

  static const _radius = Radius.circular(14);
  static const _bracketLength = 28.0;
  static const _bracketWidth = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cutout = RRect.fromRectAndRadius(guideRect, _radius);

    // Punch the guide box out of a full-screen scrim in one pass — cheaper and
    // artifact-free compared with painting four surrounding rectangles.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(cutout),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    canvas.drawRRect(
      cutout,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.35),
    );

    final bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _bracketWidth
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;

    void corner(Offset origin, double dx, double dy) {
      canvas.drawLine(
        origin,
        origin.translate(_bracketLength * dx, 0),
        bracket,
      );
      canvas.drawLine(
        origin,
        origin.translate(0, _bracketLength * dy),
        bracket,
      );
    }

    corner(guideRect.topLeft, 1, 1);
    corner(guideRect.topRight, -1, 1);
    corner(guideRect.bottomLeft, 1, -1);
    corner(guideRect.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(_GuidePainter oldDelegate) =>
      oldDelegate.guideRect != guideRect;
}
