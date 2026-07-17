import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/routes.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// Shared top bar with the app logo and a tap-to-search field, ported from
/// the mobile logo+search row in `components/layout/navbar.tsx`. Tapping the
/// search field pushes [Routes.search] directly (no inline suggestions),
/// standing in for the dedicated "Pencarian" bottom-nav tab on Beranda,
/// Ekspansi and Koleksi.
class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final logoAsset = Theme.of(context).brightness == Brightness.dark
        ? 'assets/images/horizontal-logo-dark.webp'
        : 'assets/images/horizontal-logo-light.webp';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Image.asset(logoAsset, height: 28),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.full),
              onTap: () => context.push(Routes.search),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: colors.secondary,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      size: 18,
                      color: context.mutedForeground,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Cari kartu...',
                      style: AppTypography.bodySm(context.mutedForeground),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
