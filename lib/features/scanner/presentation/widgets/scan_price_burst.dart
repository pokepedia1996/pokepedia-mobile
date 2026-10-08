import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';

/// Ports `ScanPriceBurst` — the card's price, thrown up over the preview for
/// a moment after a match lands.
///
/// Decorative, and deliberately so: [ScanResultSheet] carries the same figure
/// as the readable copy. This exists because the scanner is used with the
/// phone held out and the eyes on the card in hand, not on the sheet at the
/// bottom of the screen — a number that big is the one thing readable from
/// there, and it is the answer most people are scanning to get.
///
/// Screen-centred rather than pinned to the card: the quad moves between
/// frames and a price that chased it would be unreadable.
class ScanPriceBurst extends StatelessWidget {
  const ScanPriceBurst({super.key, required this.visible, required this.price});

  final bool visible;

  /// Null while the price fetch is still out — the burst simply does not
  /// appear, rather than flashing "Rp-" at display size.
  final int? price;

  @override
  Widget build(BuildContext context) {
    final price = this.price;
    final show = visible && price != null;

    return IgnorePointer(
      child: Center(
        child: AnimatedScale(
          // Web's `back.out(1.7)`: it overshoots slightly, which is what
          // makes this read as landing rather than fading up.
          scale: show ? 1 : 0.8,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutBack,
          child: AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: const Duration(milliseconds: 350),
            child: price == null
                ? const SizedBox.shrink()
                : Text(
                    formatRupiah(price),
                    textAlign: TextAlign.center,
                    // `display`, which is what web's `typo-display` maps to.
                    style: AppTypography.display(Colors.white).copyWith(
                      fontWeight: FontWeight.w800,
                      shadows: const [
                        // The preview behind this is whatever the camera is
                        // pointed at, so the number carries its own contrast.
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
