import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';

import 'inline_pill.dart';

/// Ports `components/ui/status-pill.tsx`.
///
/// Web gives each tone three values, not one: a light tint behind, a *shifted*
/// text shade (700/800 in light, 300 in dark), and a ring. Painting the label
/// in the same colour as its own tint — which this used to do — leaves a dim
/// colour on a dim background, and the pill all but disappears in dark mode.
class StatusPill extends StatelessWidget {
  /// A pill tinted from an arbitrary accent — a proposal count, a grade —
  /// where web has no tone for it.
  const StatusPill({super.key, required this.label, required this.color})
    : tone = null;

  /// A pill carrying one of web's seven status tones, which come with their
  /// own three values rather than being derived. Prefer this wherever the
  /// label *is* a status.
  const StatusPill.tone({super.key, required this.label, required this.tone})
    : color = null;

  final String label;
  final Color? color;
  final InlinePillTone? tone;

  @override
  Widget build(BuildContext context) {
    final scheme = tone != null
        ? tonePillColors(context, tone!)
        : statusPillColors(context, color!);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.background,
        borderRadius: BorderRadius.circular(AppRadius.full),
        // `ring-1 ring-inset` — it's what holds the shape against a card of
        // a similar value.
        border: Border.all(color: scheme.ring),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.captionSemibold(scheme.foreground),
      ),
    );
  }
}

/// The three values a tinted pill needs, derived from one accent colour.
///
/// Only for tints web has no table for — the graded [ConditionBadge]. Status
/// tones must go through [tonePillColors], which carries web's own values;
/// this approximation lands near them but not on them, and "near" is exactly
/// what made the brand red read as a different red.
({Color background, Color foreground, Color ring}) statusPillColors(
  BuildContext context,
  Color color,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return (
    background: color.withValues(alpha: isDark ? 0.20 : 0.14),
    // Away from the background in both directions: lighter on dark, darker
    // on light. A flat tone can't be legible on both.
    foreground: _shiftLightness(color, isDark ? 0.22 : -0.18),
    ring: color.withValues(alpha: isDark ? 0.38 : 0.30),
  );
}

/// Moves a colour along HSL lightness, clamped so it never blows out to
/// white or collapses to black.
Color _shiftLightness(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withLightness((hsl.lightness + amount).clamp(0.18, 0.88))
      .toColor();
}
