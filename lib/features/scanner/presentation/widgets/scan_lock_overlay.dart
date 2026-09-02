import 'package:flutter/material.dart';

/// Guidance text over the live preview while auto-capture runs.
///
/// Deliberately draws nothing over the card. The web paints no outline either,
/// and a box is worse than nothing here: it invites the user to line the card
/// up with it, which is the guide-box behaviour the corner model replaces —
/// the whole point is that the card can sit anywhere in frame.
///
/// What the copy has to do is separate "I can't see a card" from "hold still",
/// because those call for opposite actions from the user.
class ScanLockOverlay extends StatelessWidget {
  const ScanLockOverlay({
    super.key,
    required this.detected,
    required this.locking,
  });

  /// Whether the detector currently has a card that passed its gates.
  final bool detected;

  /// Whether that card is holding still enough to be building a lock.
  final bool locking;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 180),
          child: _Hint(
            text: !detected
                ? 'Arahkan kamera ke kartu'
                : locking
                ? 'Tahan sebentar...'
                : 'Kartu terdeteksi',
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: Container(
        key: ValueKey(text),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
