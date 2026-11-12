// The condition picker in the card detail page's "Menambah ke" panel: the
// trigger, the open picker with a badge per condition held, and the
// "Di koleksi" row.
//
// Design: Pencil frames "pokepedia · Web · Detail Kartu (Ideal)",
// "... · Kondisi Aktif" and "Komponen · Kondisi Toggle" (handoff 08).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/card_condition.dart';

/// One row of the picker: a label (text or grader logo) and its chips.
class ConditionPickerGroup {
  const ConditionPickerGroup({
    required this.conditions,
    this.label,
    this.logoAsset,
    this.logoHeight = 15,
  });

  final String? label;
  final String? logoAsset;
  final double logoHeight;
  final List<CardCondition> conditions;

  bool get isRaw => label != null;
}

/// Whether a collection can hold graded copies.
///
/// On since `collection_cards_condition_check` takes every Market condition
/// (pokepedia-web `20261112160738_collection_graded_conditions`). Before that
/// migration is applied a graded copy is refused on save, so a build with
/// this on must not ship ahead of it; turning it off hides the graded rows.
const collectionTakesGraded = true;

/// Order and grouping as designed: RAW first, then PSA, EGS, CGC, Beckett.
/// This is the picker's own order; `conditionCompanies` (used by the market
/// filters) is left alone.
///
/// RAW carries DMG as well as the design's four: a collection can hold
/// damaged copies, and one already held has to stay visible and editable.
const conditionPickerGroups = <ConditionPickerGroup>[
  ConditionPickerGroup(
    label: 'RAW',
    conditions: [
      CardCondition.nm,
      CardCondition.lp,
      CardCondition.mp,
      CardCondition.hp,
      CardCondition.dmg,
    ],
  ),
  ConditionPickerGroup(
    logoAsset: 'assets/images/grader/psa.webp',
    logoHeight: 16,
    conditions: [CardCondition.psa10, CardCondition.psa9, CardCondition.psaLow],
  ),
  ConditionPickerGroup(
    logoAsset: 'assets/images/grader/egs.webp',
    conditions: [
      CardCondition.egs10,
      CardCondition.egs95,
      CardCondition.egs9,
      CardCondition.egsLow,
    ],
  ),
  ConditionPickerGroup(
    logoAsset: 'assets/images/grader/cgc.webp',
    logoHeight: 14,
    conditions: [
      CardCondition.cgcPr10,
      CardCondition.cgc10,
      CardCondition.cgc95,
      CardCondition.cgc9,
      CardCondition.cgcLow,
    ],
  ),
  ConditionPickerGroup(
    logoAsset: 'assets/images/grader/bgs.webp',
    logoHeight: 12,
    conditions: [
      // BGS Black Label (BGS_BL10), first in the row like CGC's Pristine 10.
      CardCondition.bgsBl10,
      CardCondition.bgsGd10,
      CardCondition.bgs95,
      CardCondition.bgs9,
      CardCondition.bgsLow,
    ],
  ),
];

/// Ungraded: the raw grades and DMG — anything with no grading company.
/// (`isRaw` is the four sellable raw grades only, and leaves DMG out.)
bool _ungraded(CardCondition c) => c.gradingCompany == null;

/// Text on a chip inside its group: "NM", "DMG", "10", "Pristine 10", "≤8".
String pickerChipLabel(CardCondition c) =>
    _ungraded(c) ? c.short : c.gradeLabel;

/// Text on the trigger: "Near Mint" / "Damaged" for raw, "PSA 10" /
/// "CGC Pristine 10" for graded.
String pickerTriggerLabel(CardCondition c) =>
    _ungraded(c) ? c.label : '${c.gradingCompany} ${c.gradeLabel}';

/// Text on a "Di koleksi" pill: "NM", "PSA 10".
String pickerPillLabel(CardCondition c) =>
    _ungraded(c) ? c.short : '${c.gradingCompany} ${c.gradeLabel}';

/// The groups the picker shows: RAW alone until [collectionTakesGraded].
List<ConditionPickerGroup> get shownPickerGroups => collectionTakesGraded
    ? conditionPickerGroups
    : [conditionPickerGroups.first];

/// The order pills and defaults are sorted in: picker order, top to bottom.
final List<CardCondition> conditionPickerOrder = [
  for (final g in conditionPickerGroups) ...g.conditions,
];

/// Which condition the row opens on: the one the user holds most of (ties go
/// to picker order), or Near Mint when they hold none.
CardCondition defaultPickerCondition(Map<CardCondition, int> owned) {
  CardCondition? best;
  var bestQty = 0;
  for (final c in conditionPickerOrder) {
    final q = owned[c] ?? 0;
    if (q > bestQty) {
      best = c;
      bestQty = q;
    }
  }
  return best ?? CardCondition.nm;
}

/// "Near Mint ⌄" — opens and closes the picker.
class ConditionTrigger extends StatelessWidget {
  const ConditionTrigger({
    super.key,
    required this.condition,
    required this.open,
    required this.onTap,
  });

  final CardCondition condition;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = context.appColors.primary;
    return Semantics(
      button: true,
      expanded: open,
      label: 'Kondisi: ${pickerTriggerLabel(condition)}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  pickerTriggerLabel(condition),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.urbanist(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: primary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Icon(LucideIcons.chevronDown, size: 14, color: primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A graded chip's share of its row: double for a worded grade ("Pristine
/// 10", "Black 10"), single for a number.
int _chipFlex(CardCondition c) => pickerChipLabel(c).length > 4 ? 2 : 1;

/// The open picker: RAW chips stretched across, then one row per grader,
/// stretched the same way.
class ConditionTogglePicker extends StatelessWidget {
  const ConditionTogglePicker({
    super.key,
    required this.selected,
    required this.owned,
    required this.onSelected,
  });

  final CardCondition selected;

  /// Quantity held in the selected portfolio, per condition. Drives the
  /// black count badge on each chip.
  final Map<CardCondition, int> owned;

  final ValueChanged<CardCondition> onSelected;

  @override
  Widget build(BuildContext context) {
    final muted = context.mutedForeground;
    final labelStyle = GoogleFonts.urbanist(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.4,
      color: muted,
    );

    Widget chipFor(CardCondition c, {bool stretch = false}) => _ConditionChip(
      label: pickerChipLabel(c),
      semanticsLabel: pickerTriggerLabel(c),
      selected: c == selected,
      ownedCount: owned[c] ?? 0,
      stretch: stretch,
      onTap: () => onSelected(c),
    );

    final groups = shownPickerGroups;
    final rows = <Widget>[];
    for (final group in groups) {
      if (group.isRaw) {
        rows.add(
          Row(
            children: [
              SizedBox(width: 52, child: Text(group.label!, style: labelStyle)),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    for (var i = 0; i < group.conditions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 5),
                      Expanded(
                        child: chipFor(group.conditions[i], stretch: true),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
        if (groups.length > 1) rows.add(_GradedDivider(color: muted));
        continue;
      }
      rows.add(
        Row(
          children: [
            SizedBox(
              width: 52,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Image.asset(
                  group.logoAsset!,
                  height: group.logoHeight,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              // Stretched across the row like RAW's, each chip's share
              // weighted by its label, so "Pristine 10" gets the room
              // "9" doesn't need.
              child: Row(
                children: [
                  for (var i = 0; i < group.conditions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 5),
                    Expanded(
                      flex: _chipFlex(group.conditions[i]),
                      child: chipFor(group.conditions[i], stretch: true),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _GradedDivider extends StatelessWidget {
  const _GradedDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            'GRADED',
            style: GoogleFonts.urbanist(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: context.borderColor)),
        ],
      ),
    );
  }
}

class _ConditionChip extends StatelessWidget {
  const _ConditionChip({
    required this.label,
    required this.semanticsLabel,
    required this.selected,
    required this.ownedCount,
    required this.stretch,
    required this.onTap,
  });

  final String label;
  final String semanticsLabel;
  final bool selected;
  final int ownedCount;
  final bool stretch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final card = Theme.of(context).cardColor;
    final fg = colors.onSurface;
    final primary = colors.primary;

    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 28,
      constraints: const BoxConstraints(minWidth: 36),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Design token primary-soft #F4E3DE.
        color: selected ? const Color(0xFFF4E3DE) : card,
        border: Border.all(color: selected ? primary : context.borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      // Shrinks rather than clips when a stretched row is tight.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          style: GoogleFonts.urbanist(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? primary : fg,
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: ownedCount > 0
          ? '$semanticsLabel, $ownedCount di koleksi'
          : semanticsLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (stretch)
              SizedBox(width: double.infinity, child: chip)
            else
              chip,
            if (ownedCount > 0)
              Positioned(
                top: -7,
                right: -6,
                child: _OwnedBadge(count: ownedCount, ring: card),
              ),
          ],
        ),
      ),
    );
  }
}

/// The black count on a chip the user already holds.
class _OwnedBadge extends StatelessWidget {
  const _OwnedBadge({required this.count, required this.ring});

  final int count;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 15,
      constraints: const BoxConstraints(minWidth: 15),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.appColors.onSurface,
        border: Border.all(color: ring, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: GoogleFonts.urbanist(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

/// "Di koleksi  NM ×2  PSA 10 ×1" — whenever anything is held.
class OwnedConditionsRow extends StatelessWidget {
  const OwnedConditionsRow({super.key, required this.owned, this.onTap});

  final Map<CardCondition, int> owned;

  /// Optional: tapping a pill selects that condition in the row below.
  final ValueChanged<CardCondition>? onTap;

  /// Shown as soon as any copy is held, so what the user already owns is
  /// always in sight above the counter. (The handoff hid it for a single
  /// condition; the product owner wants it for one too.)
  static bool shouldShow(Map<CardCondition, int> owned) =>
      owned.values.any((q) => q > 0);

  @override
  Widget build(BuildContext context) {
    final muted = context.mutedForeground;
    final fg = context.appColors.onSurface;
    final held = [
      for (final c in conditionPickerOrder)
        if ((owned[c] ?? 0) > 0) c,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: context.borderColor)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.libraryBig, size: 13, color: muted),
          const SizedBox(width: 4),
          Text(
            'Di koleksi',
            style: GoogleFonts.urbanist(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: muted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < held.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    GestureDetector(
                      onTap: onTap == null ? null : () => onTap!(held[i]),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          border: Border.all(color: context.borderColor),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text.rich(
                          TextSpan(
                            style: GoogleFonts.urbanist(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            children: [
                              TextSpan(
                                text: pickerPillLabel(held[i]),
                                style: TextStyle(color: fg),
                              ),
                              TextSpan(
                                text: ' ×${owned[held[i]]}',
                                style: TextStyle(color: muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
