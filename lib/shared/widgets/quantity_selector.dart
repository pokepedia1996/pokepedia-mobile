import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// The two sizes `components/ui/quantity-selector.tsx` renders.
enum QuantitySelectorSize {
  /// `h-6` buttons — for a dense row where the control sits beside text.
  sm,

  /// `h-8` buttons — the default, and what a card's own actions use.
  md,
}

/// Ports `components/ui/quantity-selector.tsx`.
///
/// Three separate rounded boxes rather than one bordered strip: the steppers
/// sit on the muted fill and the count on the card's own, which is what
/// makes the number read as the value and the signs as the buttons.
class QuantitySelector extends StatelessWidget {
  const QuantitySelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 99,
    this.size = QuantitySelectorSize.md,
    this.enabled = true,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final QuantitySelectorSize size;

  /// Whether the steppers accept taps. False is for a caller with a write in
  /// flight: both signs dim the same way a bound that has been reached does,
  /// so the control keeps its shape and the count stays readable.
  final bool enabled;

  bool get _isSmall => size == QuantitySelectorSize.sm;

  double get _boxSize => _isSmall ? 24 : 32;
  double get _countWidth => _isSmall ? 32 : 48;
  double get _iconSize => _isSmall ? 12 : 14;

  /// `gap-0.5` / `gap-1.5`.
  double get _gap => _isSmall ? 2 : 6;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: LucideIcons.minus,
          size: _boxSize,
          iconSize: _iconSize,
          onTap: enabled && value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(width: _gap),
        Container(
          width: _countWidth,
          height: _boxSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border.all(color: context.borderColor),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text(
            '$value',
            style: _isSmall
                ? AppTypography.captionSemibold(colors.onSurface)
                : AppTypography.bodySmSemibold(colors.onSurface),
          ),
        ),
        SizedBox(width: _gap),
        _StepButton(
          icon: LucideIcons.plus,
          size: _boxSize,
          iconSize: _iconSize,
          onTap: enabled && value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final radius = BorderRadius.circular(AppRadius.md);

    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Opacity(
        // `disabled:opacity-30` — a bound that has been reached is still
        // shown, so the control keeps its shape.
        opacity: enabled ? 1 : 0.3,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.appColors.secondary,
            border: Border.all(color: context.borderColor),
            borderRadius: radius,
          ),
          child: Icon(icon, size: iconSize, color: context.mutedForeground),
        ),
      ),
    );
  }
}
