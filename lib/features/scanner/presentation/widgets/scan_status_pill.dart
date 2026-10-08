import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';

/// Ports `ScanStatusPill` — the "is anything happening?" indicator.
///
/// It exists because every stage of a scan is otherwise invisible: the
/// detector runs eight times a second and nothing on screen says so, and
/// after a capture nothing visibly changes for the length of a network round
/// trip.
///
/// The app used to show three of these: ready, capturing, processing. So the
/// whole tracking half — the part the user is actually steering, where they
/// are holding a card still and want to know whether it has been seen — read
/// as "Siap memindai" from start to finish. The states below are web's,
/// wording included.
enum ScanPillStatus {
  /// Nothing in view.
  searching,

  /// A card is being tracked but has not held still long enough.
  locking,

  /// Matched. The card can be taken away.
  done,

  /// The burst is being grabbed.
  capturing,

  /// Uploaded, waiting on the embedder.
  processing,

  /// The user stopped detection from the top bar.
  paused,
}

class ScanStatusPill extends StatelessWidget {
  const ScanStatusPill({super.key, required this.status});

  final ScanPillStatus status;

  /// Web's `emerald-400` and `amber-400` — the dot is the one coloured thing
  /// on a black preview, so it is pinned rather than themed.
  static const _live = Color(0xFF34D399);
  static const _paused = Color(0xFFFBBF24);

  @override
  Widget build(BuildContext context) {
    final (label, spinner) = switch (status) {
      ScanPillStatus.searching => ('Mencari kartu...', false),
      ScanPillStatus.locking => ('Mengunci...', false),
      ScanPillStatus.done => ('Kartu terbaca, angkat kartu', false),
      ScanPillStatus.capturing => ('Memindai...', true),
      ScanPillStatus.processing => ('Memproses...', true),
      ScanPillStatus.paused => ('Dijeda', false),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Container(
        key: ValueKey(status),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinner)
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                  backgroundColor: Colors.white24,
                ),
              )
            else
              _LiveDot(
                // Dimmed while there is nothing to lock onto, full once
                // there is — the difference between "looking" and "found",
                // read before the words are.
                dim: status == ScanPillStatus.searching,
                paused: status == ScanPillStatus.paused,
              ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTypography.caption(Colors.white.withValues(alpha: 0.9)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The pulsing dot. Web animates it in CSS; this is the same beat.
class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.dim, required this.paused});

  final bool dim;

  /// Steady amber instead of the pulsing green — nothing is being looked for.
  final bool paused;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  // Built eagerly, not as a lazy `late final`: the paused dot never reads it,
  // and a first read in `dispose` would create a ticker on a dead element.
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.paused) return _dot(ScanStatusPill._paused);
    return FadeTransition(
      opacity: Tween(
        begin: widget.dim ? 0.35 : 0.55,
        end: widget.dim ? 0.6 : 1.0,
      ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: _dot(ScanStatusPill._live),
    );
  }

  Widget _dot(Color color) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
