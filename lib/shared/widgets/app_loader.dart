import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// Shared page and section loading state.
class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.size = 140, this.label = 'Memuat...'});

  /// Requested indicator size, capped at 32 logical pixels for page loaders.
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = context.appColors.primary;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: size.clamp(16.0, 32.0),
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: color,
              semanticsLabel: label ?? 'Memuat...',
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 12),
            Text(
              label!,
              textAlign: TextAlign.center,
              style: AppTypography.h3(
                Theme.of(context).brightness == Brightness.dark
                    ? color
                    : context.mutedForeground,
              ).copyWith(fontSize: 18),
            ),
          ],
        ],
      ),
    );
  }
}
