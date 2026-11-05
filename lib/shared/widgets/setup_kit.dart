import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/design_palette.dart';

/// The pieces the 2026 step-by-step screens are built from — onboarding and
/// Buka Toko: the progress bar, the two-tone headline, the dark pill.

/// How the designs' sizes come out on a phone. They are drawn on a 430pt
/// frame, wider than most phones, so taken literally everything reads a
/// size too big; this brings type and the fixed sizes down together.
const setupScale = 0.9;

/// A size from the designs, at [setupScale].
double setupSize(double designed) => designed * setupScale;

/// Urbanist, the designs' body face.
TextStyle setupText(
  double size,
  Color color, [
  FontWeight weight = FontWeight.w400,
  double? height,
]) => GoogleFonts.urbanist(
  fontSize: setupSize(size),
  fontWeight: weight,
  color: color,
  height: height,
);

/// Cal Sans, the designs' headline face — `AppTypography`'s heading family.
TextStyle setupHeading(double size, Color color, {double? height}) => TextStyle(
  fontFamily: 'CalSans',
  fontSize: setupSize(size),
  height: height,
  color: color,
);

/// The bar over each step: back when there is somewhere to go back to, a
/// segment per step filled up to this one, and "2/4".
class SetupProgress extends StatelessWidget {
  const SetupProgress({
    super.key,
    required this.step,
    required this.total,
    required this.palette,
    this.onBack,
    this.showBack = true,
  });

  /// This step, counting from 0.
  final int step;
  final int total;
  final DesignPalette palette;
  final VoidCallback? onBack;

  /// False for the first step of a flow, which has nowhere to go back to.
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: setupSize(40),
      child: Row(
        children: [
          if (showBack) ...[
            SetupCircleButton(
              icon: LucideIcons.arrowLeft,
              label: 'Kembali',
              onPressed: onBack,
              palette: palette,
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < total; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= step ? palette.brand : palette.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          Text(
            '${step + 1}/$total',
            style: setupText(13, palette.muted, FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// The 40px round white button the designs put back and close in.
class SetupCircleButton extends StatelessWidget {
  const SetupCircleButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.palette,
  });

  final IconData icon;

  /// What a screen reader says; the button has no text.
  final String label;
  final VoidCallback? onPressed;
  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.surface,
      shape: CircleBorder(side: BorderSide(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: setupSize(40),
          height: setupSize(40),
          child: Icon(icon, size: 18, color: palette.ink, semanticLabel: label),
        ),
      ),
    );
  }
}

/// A headline in two lines, the second in the brand colour.
class SetupHeadline extends StatelessWidget {
  const SetupHeadline({
    super.key,
    required this.first,
    required this.second,
    required this.palette,
    this.size = 32,
    this.lineHeight = 35,
    this.center = false,
  });

  final String first;
  final String second;
  final DesignPalette palette;
  final double size;

  /// In pixels, as the designs give it.
  final double lineHeight;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final align = center ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          first,
          textAlign: align,
          style: setupHeading(size, palette.ink, height: lineHeight / size),
        ),
        Text(
          second,
          textAlign: align,
          style: setupHeading(size, palette.brand, height: lineHeight / size),
        ),
      ],
    );
  }
}

/// The pill at the foot of each step — dark by default, green for the one
/// that finishes a store.
class SetupPrimaryButton extends StatelessWidget {
  const SetupPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.palette,
    this.busy = false,
    this.icon,
    this.background,
  });

  final String label;
  final VoidCallback? onPressed;
  final DesignPalette palette;
  final bool busy;
  final IconData? icon;

  /// In place of the dark ink, for a finishing step.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final fill = background ?? palette.ctaBackground;
    final enabled = onPressed != null;
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: fill,
        foregroundColor: palette.ctaForeground,
        // Dimmed rather than greyed, so a disabled button still reads as the
        // design's button.
        disabledBackgroundColor: fill.withValues(alpha: 0.35),
        disabledForegroundColor: palette.ctaForeground,
        padding: EdgeInsets.symmetric(
          horizontal: setupSize(20),
          vertical: setupSize(14),
        ),
        shape: const StadiumBorder(),
        minimumSize: Size.fromHeight(setupSize(50)),
      ),
      child: busy && !enabled
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.ctaForeground,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: palette.ctaForeground),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: setupText(
                      16,
                      palette.ctaForeground,
                      FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The round tick at the end of a pickable row: filled in the brand colour
/// when picked, an empty ring when not.
class SetupCheckIndicator extends StatelessWidget {
  const SetupCheckIndicator({
    super.key,
    required this.selected,
    required this.palette,
  });

  final bool selected;
  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? palette.brand : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? palette.brand : palette.border,
          width: 1.5,
        ),
      ),
      child: selected
          ? Icon(LucideIcons.check, size: 14, color: palette.ctaForeground)
          : null,
    );
  }
}

/// A small rounded label: "Opsional", "Aktif", "Populer".
class SetupPill extends StatelessWidget {
  const SetupPill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.border,
    this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color? border;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        border: border == null ? null : Border.all(color: border!),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(label, style: setupText(12, foreground, FontWeight.w600)),
        ],
      ),
    );
  }
}
