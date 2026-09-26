import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// The seller cards' switch: green, and smaller than Material's default.
///
/// Green because these two switches are the card's only colour and they mean
/// "this listing will keep working" — the brand red the theme gives a bare
/// [Switch] reads as a warning on a control whose "on" is the good outcome.
///
/// Scaled well down because two of them share a card's width with their own
/// labels: Material's switch is 52pt before its tap target, which left
/// "Perpanjang otomatis" wrapping onto a second line and made the card a row
/// taller than the design for every draft in the list.
class SellerSwitch extends StatelessWidget {
  const SellerSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// The footprint the switch is allowed, in logical pixels.
  ///
  /// A [SizedBox] around a [FittedBox], not `Transform.scale`: scaling only
  /// changes what is painted, so the switch went on occupying its full ~52pt
  /// of layout while *looking* smaller — and the label beside it got none of
  /// the room back. This actually reclaims it.
  static const _width = 40.0;
  static const _height = 24.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      height: _height,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: context.appSemantic.success,
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: context.mutedForeground.withValues(alpha: 0.22),
          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
