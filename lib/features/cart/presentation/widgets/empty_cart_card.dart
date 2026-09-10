import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';

/// Ports `features/cart/components/empty-cart.tsx` — a bordered card with a
/// circled icon, not the app's generic full-bleed empty state. On web this
/// sits in the same column the seller groups would occupy, so it reads as
/// "the cart, currently empty" rather than as an error page.
class EmptyCartCard extends StatelessWidget {
  const EmptyCartCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.secondary.withValues(alpha: 0.5),
              ),
              child: Icon(
                LucideIcons.shoppingCart,
                size: 40,
                color: context.mutedForeground,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Keranjang kamu kosong',
              style: AppTypography.bodySemibold(colors.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              'Yuk, mulai belanja kartu favoritmu!',
              textAlign: TextAlign.center,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              // Web links to `/`, which is the marketplace feed there. The
              // app's equivalent landing surface is Beranda.
              onPressed: () => context.go(Routes.home),
              style: ElevatedButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text('Mulai Belanja'),
            ),
          ],
        ),
      ),
    );
  }
}
