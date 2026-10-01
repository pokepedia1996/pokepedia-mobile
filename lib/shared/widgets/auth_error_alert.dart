import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// Ports `components/ui/error-alert.tsx` — the tinted banner every auth
/// screen puts above its form for a failure that belongs to the whole
/// submission rather than to one field.
class AuthErrorAlert extends StatelessWidget {
  const AuthErrorAlert({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.circleAlert, size: 16, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: AppTypography.bodySm(colors.error)),
          ),
        ],
      ),
    );
  }
}
