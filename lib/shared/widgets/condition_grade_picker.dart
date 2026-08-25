import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/condition_colors.dart';
import '../models/card_condition.dart';

/// Ports `components/conditions/condition-grade-picker.tsx` in single-select
/// mode — a horizontally scrolling pill row with the four raw grades inline
/// and each grading company collapsed behind one pill that opens its grades
/// in a menu (web uses an anchored popover for the same reason: 21 grades
/// don't fit on one line).
class ConditionGradePicker extends StatelessWidget {
  const ConditionGradePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.showAllOption = true,
  });

  final CardCondition? value;

  /// Null means "Semua" — no condition filter.
  final ValueChanged<CardCondition?> onChanged;
  final bool showAllOption;

  /// The graded companies in `CONDITION_COMPANIES` order, each with its
  /// grades in declaration order.
  static final _gradedByCompany = <String, List<CardCondition>>{
    for (final company in conditionCompanies.where((c) => c != 'Raw'))
      company: CardCondition.values
          .where((c) => c.gradingCompany == company)
          .toList(),
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          if (showAllOption)
            _Pill(
              label: 'Semua',
              active: value == null,
              onTap: () => onChanged(null),
            ),
          for (final condition in rawConditions)
            _Pill(
              label: condition.short,
              active: value == condition,
              color: conditionColorOf(context, condition),
              onTap: () => onChanged(value == condition ? null : condition),
            ),
          for (final entry in _gradedByCompany.entries)
            _CompanyPill(
              company: entry.key,
              grades: entry.value,
              selected: entry.value.contains(value) ? value : null,
              onSelected: (condition) =>
                  onChanged(value == condition ? null : condition),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.active,
    required this.onTap,
    this.color,
    this.trailing,
  });

  final String label;
  final bool active;

  /// Null inside [_CompanyPill], where the enclosing menu button owns the
  /// tap — an InkWell with a callback here would swallow it instead.
  final VoidCallback? onTap;

  /// The condition's own color, tinting the pill while it's selected.
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? context.appColors.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: 0.14) : Colors.transparent,
            border: Border.all(
              color: active ? accent.withValues(alpha: 0.5) : context.borderColor,
            ),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTypography.captionSemibold(
                  active ? accent : context.mutedForeground,
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 2), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// One grading company's pill — shows the company name until a grade under
/// it is picked, then the grade itself, like the web popover's trigger.
class _CompanyPill extends StatelessWidget {
  const _CompanyPill({
    required this.company,
    required this.grades,
    required this.selected,
    required this.onSelected,
  });

  final String company;
  final List<CardCondition> grades;
  final CardCondition? selected;
  final ValueChanged<CardCondition> onSelected;

  @override
  Widget build(BuildContext context) {
    final active = selected != null;
    final accent = active
        ? conditionColorOf(context, selected!)
        : context.appColors.onSurface;

    return PopupMenuButton<CardCondition>(
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: context.borderColor),
      ),
      itemBuilder: (context) => [
        for (final grade in grades)
          PopupMenuItem(
            value: grade,
            height: 40,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: conditionColorOf(context, grade),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    grade.gradeLabel,
                    style: AppTypography.bodySm(context.appColors.onSurface),
                  ),
                ),
                if (grade == selected)
                  Icon(Icons.check, size: 16, color: context.appColors.primary),
              ],
            ),
          ),
      ],
      child: _Pill(
        label: active ? selected!.short : company,
        active: active,
        color: active ? accent : null,
        onTap: null,
        trailing: Icon(
          Icons.expand_more,
          size: 14,
          color: active ? accent : context.mutedForeground,
        ),
      ),
    );
  }
}
