import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../models/card_model.dart';
import 'card_language_badge.dart';

/// One print language in a "Bahasa" filter: the flag and its two-letter
/// label in an outlined box, tinted when it is on.
///
/// Laid out three abreast with each in an `Expanded`, so the three languages
/// split the row evenly — the market filter sheet's arrangement, which the
/// card filter bar shares rather than drawing a look of its own.
class LanguageFilterChip extends StatelessWidget {
  const LanguageFilterChip({
    super.key,
    required this.language,
    required this.active,
    required this.onTap,
  });

  final CardLanguage language;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? colors.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            border: Border.all(
              color: active ? colors.primary : context.borderColor,
            ),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CardLanguageBadge(language: language, size: 14),
              const SizedBox(width: 6),
              Text(
                language.shortLabel,
                style: active
                    ? AppTypography.captionSemibold(colors.onSurface)
                    : AppTypography.caption(context.mutedForeground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
