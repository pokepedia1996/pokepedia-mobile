import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// The running-Pikachu Lottie used for every page- and section-level loading
/// state, so waiting for data looks the same everywhere instead of a bare
/// Material spinner. Extracted from `HomeLoadingGate`, which had the only
/// copy of this animation.
///
/// Deliberately *not* used for the small (14–20px) spinners inside buttons
/// and inline rows — a Lottie at that size is an unreadable smudge, and
/// those keep using [CircularProgressIndicator].
class PikachuLoader extends StatelessWidget {
  const PikachuLoader({super.key, this.size = 140, this.label});

  /// Width of the animation. The default suits a full page or tab body;
  /// pass something smaller for a short section (a carousel strip, say).
  final double size;

  /// Optional caption under the animation. Left off by default — most
  /// call sites sit inside a screen whose heading already says what's
  /// loading.
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            child: Lottie.asset('assets/animation/pikachu.json', repeat: true),
          ),
          if (label != null)
            // The artboard carries empty space under Pikachu's feet, so the
            // caption needs pulling up to not read as detached from it.
            Transform.translate(
              offset: Offset(0, -size * 0.13),
              child: Text(
                label!,
                textAlign: TextAlign.center,
                style: AppTypography.h3(context.mutedForeground),
              ),
            ),
        ],
      ),
    );
  }
}
