import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// Ports `components/ui/inline-pill.tsx` — the small tinted chip the order
/// cards carry a single fact in.
///
/// Web sets each tone from a fixed Tailwind pair (a 100-level tint under a
/// 700-level text, flipped to a 15% wash in dark). The app has no such
/// palette, so each tone names one colour and the chip derives its own
/// background from it, which lands in the same place in both themes.
/// Web's seven `StatusPillTone`s, one for one.
///
/// [shipped] used to be missing here, and "Dikirim" borrowed [info] instead.
/// That forced [info] off its own blue onto indigo to stay distinguishable,
/// which in turn left [progress] holding the blue that belongs to [info] —
/// three tones wrong to cover for one absent.
enum InlinePillTone {
  danger,
  neutral,
  success,
  progress,
  shipped,
  warning,
  info,
}

class InlinePill extends StatelessWidget {
  const InlinePill({
    super.key,
    required this.tone,
    required this.label,
    this.icon,
    this.trailing,
  });

  final InlinePillTone tone;
  final String label;
  final IconData? icon;

  /// An extra span after the label, drawn lighter — web's `opacity-80`
  /// continuation, as in "· ETA 2-3 hari".
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    // Same three-value treatment as StatusPill: a flat tint with same-colour
    // text is unreadable on a dark card.
    final scheme = tonePillColors(context, tone);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: scheme.ring),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: scheme.foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.captionSemibold(scheme.foreground),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                trailing!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption(
                  scheme.foreground.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The colour behind a tone, shared with the status pills so a "shipped"
/// order reads the same whichever chip is carrying it.
Color toneColor(BuildContext context, InlinePillTone tone) {
  final colors = context.appColors;
  final semantic = context.appSemantic;
  return switch (tone) {
    InlinePillTone.danger => colors.error,
    InlinePillTone.neutral => context.mutedForeground,
    InlinePillTone.success => semantic.success,
    // `bg-primary/10 text-primary ring-primary/20` — the brand colour, which
    // on this palette is the red. "Dalam Proses" is a red pill on the site.
    InlinePillTone.progress => colors.primary,
    // `bg-indigo-100 text-indigo-700`.
    InlinePillTone.shipped => const Color(0xFF6366F1),
    InlinePillTone.warning => semantic.condMp,
    // `bg-blue-100 text-blue-700` — the brand blue, not the indigo it was
    // pushed onto while it was standing in for [shipped].
    InlinePillTone.info => semantic.bid,
  };
}

/// Web's `toneStyles` from `components/ui/status-pill.tsx`, value for value.
///
/// Not derived from a single accent any more: web writes most tones as
/// Tailwind palette steps (`bg-red-100 text-red-700 ring-red-200`, and a
/// `/15` `/30` pair on dark), which no lighten-and-darken rule reproduces.
/// Approximating them is what left the brand red looking like a different
/// red — the pill's label was the primary darkened by 18% lightness rather
/// than the primary itself.
///
/// [InlinePillTone.progress] and [InlinePillTone.neutral] stay computed:
/// web spells those `bg-primary/10 text-primary ring-primary/20` and
/// `bg-muted text-muted-foreground ring-border`, so they must follow the
/// theme rather than a frozen hex.
({Color background, Color foreground, Color ring}) tonePillColors(
  BuildContext context,
  InlinePillTone tone,
) {
  final colors = context.appColors;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  switch (tone) {
    case InlinePillTone.neutral:
      return (
        background: colors.secondary,
        foreground: context.mutedForeground,
        ring: context.borderColor,
      );
    case InlinePillTone.progress:
      // `bg-primary/10 text-primary ring-primary/20` — no dark variant on
      // web, so the same three values serve both themes.
      return (
        background: colors.primary.withValues(alpha: 0.10),
        foreground: colors.primary,
        ring: colors.primary.withValues(alpha: 0.20),
      );
    case InlinePillTone.danger:
      return isDark
          ? _dark(const Color(0xFFFB2C36), const Color(0xFFFFA2A2))
          : _light(
              const Color(0xFFFFE2E2),
              const Color(0xFFC10007),
              const Color(0xFFFFC9C9),
            );
    case InlinePillTone.warning:
      return isDark
          ? _dark(const Color(0xFFFE9A00), const Color(0xFFFFD230))
          : _light(
              const Color(0xFFFEF3C6),
              const Color(0xFF973C00),
              const Color(0xFFFEE685),
            );
    case InlinePillTone.success:
      return isDark
          ? _dark(const Color(0xFF00BC7D), const Color(0xFF5EE9B5))
          : _light(
              const Color(0xFFD0FAE5),
              const Color(0xFF007A55),
              const Color(0xFFA4F4CF),
            );
    case InlinePillTone.info:
      return isDark
          ? _dark(const Color(0xFF2B7FFF), const Color(0xFF8EC5FF))
          : _light(
              const Color(0xFFDBEAFE),
              const Color(0xFF1447E6),
              const Color(0xFFBEDBFF),
            );
    case InlinePillTone.shipped:
      return isDark
          ? _dark(const Color(0xFF615FFF), const Color(0xFFA3B3FF))
          : _light(
              const Color(0xFFE0E7FF),
              const Color(0xFF432DD7),
              const Color(0xFFC6D2FF),
            );
  }
}

({Color background, Color foreground, Color ring}) _light(
  Color background,
  Color foreground,
  Color ring,
) => (background: background, foreground: foreground, ring: ring);

/// Web's dark rule for every palette tone: `bg-<c>-500/15`, `text-<c>-300`,
/// `ring-<c>-500/30`.
({Color background, Color foreground, Color ring}) _dark(
  Color accent,
  Color foreground,
) => (
  background: accent.withValues(alpha: 0.15),
  foreground: foreground,
  ring: accent.withValues(alpha: 0.30),
);
