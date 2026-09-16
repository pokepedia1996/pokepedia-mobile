import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';

/// The tick on a selectable card tile — filled when it's picked, an empty
/// ring when it isn't, so a grid in Kelola mode says it can be selected
/// before anything has been.
///
/// Deliberately the whole of the selected state alongside the tile's own
/// border: tinting the tile as well buried the artwork under the very
/// colour the page uses for its prices.
class SelectionMark extends StatelessWidget {
  const SelectionMark({super.key, required this.selected, this.size = 22});

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected
            ? colors.primary
            : Theme.of(context).cardColor.withValues(alpha: 0.85),
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? colors.primary : context.borderColor,
        ),
      ),
      child: selected
          ? Icon(LucideIcons.check, size: size * 0.64, color: colors.onPrimary)
          : null,
    );
  }
}
