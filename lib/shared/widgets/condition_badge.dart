import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/condition_colors.dart';
import '../models/card_condition.dart';
import 'status_pill.dart';

/// Ports `components/card/condition-badge.tsx` — a small pill showing the
/// short condition code (NM/LP/MP/HP/PSA.../BGS.../CGC.../EGS...) over a
/// card thumbnail.
///
/// Monochrome by default: over a card thumbnail the pill sits on artwork of
/// every colour, and black on white is the one pairing that reads over all of
/// it. Away from artwork web tints it per grade
/// (`CONDITION_BADGE_CLASSES`), which [colored] turns on.
class ConditionBadge extends StatelessWidget {
  const ConditionBadge({
    super.key,
    required this.condition,
    this.dense = false,
    this.full = false,
    this.colored = false,
  });

  final CardCondition condition;

  /// Spell the grade out — "Near Mint" rather than "NM".
  ///
  /// Opt-in because the short code is what belongs over a thumbnail, where
  /// there is no room for the long form. The purchase panel has the room and
  /// web spells it out there (`CONDITION_LABEL`, not `conditionShort`), so
  /// that one caller asks for it.
  final bool full;

  /// Tint the pill with the grade's own colour, as web does everywhere the
  /// badge is not sitting on artwork.
  ///
  /// The tint comes from [conditionColorOf] through [statusPillColors] rather
  /// than a table of literals: web writes 21 conditions x 6 Tailwind shades,
  /// but those shades are one accent lightened and darkened, which is exactly
  /// what that helper already derives — and it does so per theme, so the
  /// badge stays legible on dark without a second table.
  final bool colored;

  /// The tighter variant used inside table-like rows (the order book ladder
  /// and listing rows), matching web's `text-[9px]` inline badges.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = colored
        ? statusPillColors(context, conditionColorOf(context, condition))
        : null;
    final foreground = scheme?.foreground ?? Colors.black;

    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: scheme?.background ?? Colors.white,
        borderRadius: BorderRadius.circular(dense ? 4 : AppRadius.full),
        border: Border.all(
          color: scheme?.ring ?? Colors.black.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        full ? condition.label : condition.short,
        style: dense
            ? AppTypography.badge(foreground).copyWith(fontSize: 9)
            : AppTypography.badge(foreground),
      ),
    );
  }
}
