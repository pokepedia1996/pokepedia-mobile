import 'package:flutter/material.dart';

/// The "Rp" in front of a money field, shown whether or not the field has
/// focus.
///
/// `prefixText` is hidden while the field is empty and unfocused, which left
/// a bare "0" with no unit until it was tapped. A `prefixIcon` always shows,
/// but it sits outside the content padding and takes no text style, so this
/// puts both back: it lines up where `prefixText` drew and reads in the
/// field's own size in the hint colour.
///
/// Use with [constraints] so the icon slot doesn't pad it out to 48px:
///
/// ```dart
/// InputDecoration(
///   prefixIcon: const RupiahPrefix(),
///   prefixIconConstraints: RupiahPrefix.constraints,
/// )
/// ```
class RupiahPrefix extends StatelessWidget {
  const RupiahPrefix({super.key, this.inset = 14, this.style});

  static const constraints = BoxConstraints();

  /// The field's horizontal content padding — the theme's 14 unless the
  /// field sets its own.
  final double inset;

  /// The field's text style, when it sets one.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = style ?? theme.textTheme.bodyLarge ?? const TextStyle();
    return Padding(
      // `prefixText` sits a 4px input gap inside the content padding.
      padding: EdgeInsetsDirectional.only(start: inset + 4, end: 2),
      child: Text(
        'Rp',
        style: base.copyWith(
          color: theme.inputDecorationTheme.hintStyle?.color ?? theme.hintColor,
        ),
      ),
    );
  }
}
