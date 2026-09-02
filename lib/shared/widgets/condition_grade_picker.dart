import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/condition_colors.dart';
import '../models/card_condition.dart';

/// Ports `components/conditions/condition-grade-picker.tsx` — a horizontally
/// scrolling pill row with the four raw grades inline and each grading
/// company collapsed behind one pill that opens its grades in a menu (web
/// uses an anchored popover for the same reason: 21 grades don't fit on one
/// line).
///
/// The default constructor is web's `mode="single"`; [ConditionGradePicker.multi]
/// is `mode="multi"`, where several grades can be active at once.
class ConditionGradePicker extends StatelessWidget {
  const ConditionGradePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.showAllOption = true,
  }) : selected = null,
       onToggled = null,
       facetCounts = null;

  /// Multi-select form, used by filter surfaces that narrow a listing feed to
  /// several grades at once (web's `mode="multi"`). The "Semua" pill is
  /// dropped, as it is on web — an empty selection already means "all".
  const ConditionGradePicker.multi({
    super.key,
    required this.selected,
    required this.onToggled,
    this.facetCounts,
  }) : value = null,
       onChanged = null,
       showAllOption = false;

  final CardCondition? value;

  /// Null means "Semua" — no condition filter.
  final ValueChanged<CardCondition?>? onChanged;
  final bool showAllOption;

  /// The selected grades in multi mode; null in single mode.
  final Set<CardCondition>? selected;

  /// Multi mode's toggle — fires with the grade that was tapped.
  final ValueChanged<CardCondition>? onToggled;

  /// How many listings each grade has, keyed by [CardConditionX.raw]. Shown
  /// beside the grade the way web's `facetCounts` are.
  final Map<String, int>? facetCounts;

  bool get _multi => selected != null;

  /// The graded companies in `CONDITION_COMPANIES` order, each with its
  /// grades in declaration order.
  static final _gradedByCompany = <String, List<CardCondition>>{
    for (final company in conditionCompanies.where((c) => c != 'Raw'))
      company: CardCondition.values
          .where((c) => c.gradingCompany == company)
          .toList(),
  };

  bool _isSelected(CardCondition condition) =>
      _multi ? selected!.contains(condition) : value == condition;

  /// Null unless there is a non-zero count to show — a grade nobody has
  /// listed reads better bare than trailing a "0", as on web.
  int? _countOf(CardCondition condition) {
    final count = facetCounts?[condition.raw];
    return count != null && count > 0 ? count : null;
  }

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
              onTap: () => onChanged!(null),
            ),
          for (final condition in rawConditions)
            _Pill(
              label: condition.short,
              count: _countOf(condition),
              active: _isSelected(condition),
              color: conditionColorOf(context, condition),
              onTap: () => _multi
                  ? onToggled!(condition)
                  : onChanged!(value == condition ? null : condition),
            ),
          for (final entry in _gradedByCompany.entries)
            _CompanyPill(
              company: entry.key,
              grades: entry.value,
              selected: entry.value.where(_isSelected).toSet(),
              counts: {
                for (final grade in entry.value)
                  if (_countOf(grade) != null) grade: _countOf(grade)!,
              },
              multi: _multi,
              onSelected: (condition) => _multi
                  ? onToggled!(condition)
                  : onChanged!(value == condition ? null : condition),
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
    this.count,
    this.trailing,
  });

  final String label;
  final bool active;

  /// The facet count trailing the label, when there is one.
  final int? count;

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
              color: active
                  ? accent.withValues(alpha: 0.5)
                  : context.borderColor,
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
              if (count != null) ...[
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: AppTypography.caption(
                    (active ? accent : context.mutedForeground).withValues(
                      alpha: 0.7,
                    ),
                  ),
                ),
              ],
              if (trailing != null) ...[const SizedBox(width: 2), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// One grading company's pill — shows the company name until a grade under
/// it is picked, then the grade itself, like the web popover's trigger. In
/// multi mode the name stays put and a count badge replaces it, again
/// following the web picker.
class _CompanyPill extends StatelessWidget {
  const _CompanyPill({
    required this.company,
    required this.grades,
    required this.selected,
    required this.onSelected,
    this.counts = const {},
    this.multi = false,
  });

  final String company;
  final List<CardCondition> grades;

  /// The company's selected grades — at most one in single mode.
  final Set<CardCondition> selected;

  /// Listing counts per grade, shown in the menu.
  final Map<CardCondition, int> counts;
  final ValueChanged<CardCondition> onSelected;
  final bool multi;

  @override
  Widget build(BuildContext context) {
    final active = selected.isNotEmpty;
    // One selected grade colors the pill as itself, the way single mode does;
    // a mixed selection has no one color to borrow, so it falls back to the
    // foreground accent.
    final accent = selected.length == 1
        ? conditionColorOf(context, selected.first)
        : context.appColors.onSurface;

    final pill = _Pill(
      label: !multi && active ? selected.first.short : company,
      active: active,
      color: active ? accent : null,
      onTap: null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (multi && active) ...[
            const SizedBox(width: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                '${selected.length}',
                style: AppTypography.badge(accent),
              ),
            ),
          ],
          Icon(
            LucideIcons.chevronDown,
            size: 14,
            color: active ? accent : context.mutedForeground,
          ),
        ],
      ),
    );

    // Multi-select keeps its menu open across taps, like the web popover —
    // otherwise filtering by three PSA grades costs three trips to reopen it.
    if (multi) {
      return MenuAnchor(
        alignmentOffset: const Offset(0, 4),
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(Theme.of(context).cardColor),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: BorderSide(color: context.borderColor),
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 4),
          ),
        ),
        menuChildren: [
          for (final grade in grades)
            MenuItemButton(
              closeOnActivate: false,
              onPressed: () => onSelected(grade),
              child: SizedBox(
                width: 148,
                child: _GradeRow(
                  grade: grade,
                  selected: selected.contains(grade),
                  count: counts[grade],
                ),
              ),
            ),
        ],
        builder: (context, controller, _) => GestureDetector(
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: pill,
        ),
      );
    }

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
            child: _GradeRow(grade: grade, selected: selected.contains(grade)),
          ),
      ],
      child: pill,
    );
  }
}

/// One grade inside a company's menu — web's `GradeRow`.
class _GradeRow extends StatelessWidget {
  const _GradeRow({required this.grade, required this.selected, this.count});

  final CardCondition grade;
  final bool selected;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Row(
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
            style: selected
                ? AppTypography.bodySmSemibold(context.appColors.onSurface)
                : AppTypography.bodySm(context.appColors.onSurface),
          ),
        ),
        if (count != null)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              '$count',
              style: AppTypography.caption(context.mutedForeground),
            ),
          ),
        if (selected)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(
              LucideIcons.check,
              size: 16,
              color: context.appColors.primary,
            ),
          ),
      ],
    );
  }
}
