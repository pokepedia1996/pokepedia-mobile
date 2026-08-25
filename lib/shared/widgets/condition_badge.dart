import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/condition_colors.dart';
import '../models/card_condition.dart';

/// Ports `components/card/condition-badge.tsx` — a small pill showing the
/// short condition code (NM/LP/MP/HP/PSA.../BGS.../CGC.../EGS...) over a
/// card thumbnail. Colors come from [conditionColorOf], which buckets the
/// 21 grading values into the 7 `--cond-*` tokens in `globals.css`.
class ConditionBadge extends StatelessWidget {
  const ConditionBadge({super.key, required this.condition, this.dense = false});

  final CardCondition condition;

  /// The tighter variant used inside table-like rows (the order book ladder
  /// and listing rows), matching web's `text-[9px]` inline badges.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = conditionColorOf(context, condition);
    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(dense ? 4 : AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        condition.short,
        style: dense
            ? AppTypography.badge(color).copyWith(fontSize: 9)
            : AppTypography.badge(color),
      ),
    );
  }
}
