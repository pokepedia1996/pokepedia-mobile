import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../models/card_condition.dart';

/// Ports `components/card/condition-badge.tsx` — a small pill showing the
/// short condition code (NM/LP/MP/HP/PSA.../BGS.../CGC.../EGS...) over a
/// card thumbnail. Colors bucket the 21 grading values from
/// `listings_condition_check` into the 7 `--cond-*` tokens in
/// `globals.css`.
class ConditionBadge extends StatelessWidget {
  const ConditionBadge({super.key, required this.condition});

  final CardCondition condition;

  static const _top10 = {
    CardCondition.psa10,
    CardCondition.bgsGd10,
    CardCondition.cgc10,
    CardCondition.egs10,
  };

  static const _nine = {
    CardCondition.psa9,
    CardCondition.bgs9,
    CardCondition.bgs95,
    CardCondition.cgc9,
    CardCondition.cgc95,
    CardCondition.egs9,
    CardCondition.egs95,
  };

  Color _colorFor(BuildContext context) {
    final s = context.appSemantic;
    switch (condition) {
      case CardCondition.nm:
        return s.condNm;
      case CardCondition.lp:
        return s.condLp;
      case CardCondition.mp:
        return s.condMp;
      case CardCondition.hp:
        return s.condHp;
      default:
        if (_top10.contains(condition)) return s.condPsa10;
        if (_nine.contains(condition)) return s.condPsa9;
        return s.condPsaLow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(condition.short, style: AppTypography.badge(color)),
    );
  }
}
