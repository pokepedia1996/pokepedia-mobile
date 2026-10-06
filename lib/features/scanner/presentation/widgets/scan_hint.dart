import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';

/// Ports web's opening hint — "Arahkan kamera ke kartu", shown under the top
/// bar for the first few seconds the camera is live, then gone for good.
///
/// Deliberately draws nothing over the card. The web paints no outline either,
/// and a box is worse than nothing here: it invites the user to line the card
/// up with it, which is the guide-box behaviour the corner model replaces —
/// the whole point is that the card can sit anywhere in frame. Moment-to-
/// moment tracking feedback is the status pill's job, not this.
class ScanHint extends StatelessWidget {
  const ScanHint({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      // Web's `top-28`.
      top: MediaQuery.of(context).padding.top + 112,
      left: 12,
      right: 12,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 500),
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  color: Colors.black.withValues(alpha: 0.4),
                  child: Text(
                    'Arahkan kamera ke kartu',
                    textAlign: TextAlign.center,
                    style: AppTypography.caption(
                      Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
