import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// A form field with its label sitting above it, as every form on the web
/// does — rather than Material's floating label, which rides the input's
/// border and leaves no room for a required marker.
///
/// [child] keeps its own `hintText`, so the placeholder still shows what a
/// good answer looks like once the field is focused.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.isRequired = false,
  });

  final String label;
  final Widget child;

  /// Draws web's red asterisk after the label.
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: label,
            style: AppTypography.bodySmSemibold(context.appColors.onSurface),
            children: isRequired
                ? [
                    TextSpan(
                      text: ' *',
                      style: AppTypography.bodySmSemibold(
                        context.appColors.error,
                      ),
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
