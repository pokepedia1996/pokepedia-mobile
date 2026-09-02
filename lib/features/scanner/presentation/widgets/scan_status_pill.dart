import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';

/// Ports `ScanStatusPill` — the "is anything happening?" indicator.
///
/// It exists because every stage of a scan is otherwise invisible: the shutter
/// fires, and then nothing visibly changes for the length of a network round
/// trip. [ScanPillStatus.processing] deliberately covers that whole window.
enum ScanPillStatus { ready, capturing, processing }

class ScanStatusPill extends StatelessWidget {
  const ScanStatusPill({super.key, required this.status});

  final ScanPillStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color, showSpinner) = switch (status) {
      ScanPillStatus.ready => ('Siap memindai', Colors.white, false),
      ScanPillStatus.capturing => ('Mengambil gambar…', Colors.white, true),
      ScanPillStatus.processing => (
        'Mengenali kartu…',
        Colors.amberAccent,
        true,
      ),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Container(
        key: ValueKey(status),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSpinner)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            const SizedBox(width: 8),
            Text(label, style: AppTypography.caption(color)),
          ],
        ),
      ),
    );
  }
}
