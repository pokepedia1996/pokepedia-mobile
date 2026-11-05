import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The colours of the 2026 redesign screens (onboarding, the empty
/// portfolio), exact in light mode.
///
/// The designs have no dark version, so dark mode takes the theme's own
/// equivalents rather than putting a cream page in a dark app.
class DesignPalette {
  const DesignPalette({
    required this.background,
    required this.surface,
    required this.border,
    required this.ink,
    required this.muted,
    required this.brand,
    required this.brandSoft,
    required this.brandBorder,
    required this.chip,
    required this.success,
    required this.successText,
    required this.successSoft,
    required this.error,
    required this.ctaBackground,
    required this.ctaForeground,
  });

  factory DesignPalette.of(BuildContext context) {
    final colors = context.appColors;
    if (Theme.of(context).brightness == Brightness.light) {
      return DesignPalette(
        background: const Color(0xFFFAF8F4),
        surface: const Color(0xFFFFFFFF),
        border: const Color(0xFFEDE6D6),
        ink: const Color(0xFF1C1413),
        muted: const Color(0xFF6B6564),
        brand: const Color(0xFFAC403A),
        brandSoft: const Color(0xFFF4E3DE),
        brandBorder: const Color(0xFFE3BDB4),
        chip: const Color(0xFFF4F1E8),
        success: const Color(0xFF16A34A),
        successText: const Color(0xFF15803D),
        successSoft: const Color(0xFFDCFCE7),
        error: colors.error,
        ctaBackground: const Color(0xFF1C1413),
        ctaForeground: const Color(0xFFFFFFFF),
      );
    }
    return DesignPalette(
      background: Theme.of(context).scaffoldBackgroundColor,
      surface: Theme.of(context).cardColor,
      border: context.borderColor,
      ink: colors.onSurface,
      muted: context.mutedForeground,
      brand: colors.primary,
      brandSoft: colors.primary.withValues(alpha: 0.18),
      brandBorder: colors.primary.withValues(alpha: 0.4),
      chip: colors.secondary,
      success: context.appSemantic.success,
      successText: context.appSemantic.success,
      successSoft: context.appSemantic.success.withValues(alpha: 0.16),
      error: colors.error,
      ctaBackground: colors.onSurface,
      ctaForeground: colors.surface,
    );
  }

  final Color background;
  final Color surface;
  final Color border;
  final Color ink;
  final Color muted;
  final Color brand;

  /// The brand tint behind a selected icon or an avatar initial.
  final Color brandSoft;

  /// The outline of something drawn in [brandSoft].
  final Color brandBorder;

  /// Chips, unselected icon tiles, the quieter of two action tiles.
  final Color chip;
  final Color success;
  final Color successText;

  /// Behind a success mark: the "Aktif" pill, a finished step's tick.
  final Color successSoft;
  final Color error;

  /// The dark pill and dark tile; [ctaForeground] is what sits on them.
  final Color ctaBackground;
  final Color ctaForeground;
}
