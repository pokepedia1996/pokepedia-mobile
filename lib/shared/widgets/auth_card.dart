import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// Ports `components/auth/auth-card.tsx` — the centered card wrapper used
/// by every auth screen.
class AuthCard extends StatelessWidget {
  const AuthCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.formBody,
    required this.footer,
  });

  final String title;
  final String? subtitle;
  final Widget formBody;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: context.borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTypography.h2(colors.onSurface),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle!,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySm(context.mutedForeground),
                      ),
                    ],
                    const SizedBox(height: 20),
                    formBody,
                    const SizedBox(height: 20),
                    Divider(color: context.borderColor),
                    const SizedBox(height: 16),
                    footer,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
