import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../utils/card_filtering.dart';

/// Ports `components/ui/view-toggle.tsx` — the grid/list pair shown at the
/// right of a listing toolbar. Shared by the card filter bar and the
/// expansions list, which toggle the same way.
class ViewModeToggle extends StatelessWidget {
  const ViewModeToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final CardViewMode value;
  final ValueChanged<CardViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ViewModeButton(
            icon: LucideIcons.layoutGrid,
            selected: value == CardViewMode.grid,
            onTap: () => onChanged(CardViewMode.grid),
          ),
          _ViewModeButton(
            icon: LucideIcons.list,
            selected: value == CardViewMode.list,
            onTap: () => onChanged(CardViewMode.list),
          ),
        ],
      ),
    );
  }
}

class _ViewModeButton extends StatelessWidget {
  const _ViewModeButton({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        color: selected ? colors.primary : Theme.of(context).cardColor,
        child: Icon(
          icon,
          size: 18,
          color: selected ? colors.onPrimary : context.mutedForeground,
        ),
      ),
    );
  }
}
