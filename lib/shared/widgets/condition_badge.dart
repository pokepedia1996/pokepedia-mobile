import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';
import '../models/card_condition.dart';

/// Ports `components/card/condition-badge.tsx` — a small pill showing the
/// short condition code (NM/LP/MP/HP/PSA.../BGS.../CGC.../EGS...) over a
/// card thumbnail.
///
/// Deliberately monochrome: the pill sits on artwork of every colour, and
/// black on white is the one pairing that reads over all of it. The
/// condition's own colour is still used where it identifies a series rather
/// than a label — the market chart and the grade picker.
class ConditionBadge extends StatelessWidget {
  const ConditionBadge({
    super.key,
    required this.condition,
    this.dense = false,
  });

  final CardCondition condition;

  /// The tighter variant used inside table-like rows (the order book ladder
  /// and listing rows), matching web's `text-[9px]` inline badges.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(dense ? 4 : AppRadius.full),
        border: Border.all(color: Colors.black.withValues(alpha: 0.25)),
      ),
      child: Text(
        condition.short,
        style: dense
            ? AppTypography.badge(Colors.black).copyWith(fontSize: 9)
            : AppTypography.badge(Colors.black),
      ),
    );
  }
}
