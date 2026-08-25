import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/routes.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../features/cart/usecase/cart_notifier.dart';

/// Shared top bar with the app logo and a tap-to-search field, ported from
/// the mobile logo+search row in `components/layout/navbar.tsx`. Tapping the
/// search field pushes [Routes.search] directly (no inline suggestions),
/// standing in for the dedicated "Pencarian" bottom-nav tab on Beranda,
/// Ekspansi and Koleksi.
class AppTopBar extends ConsumerWidget {
  const AppTopBar({super.key, this.showCart = true});

  /// The cart button on the right of the row. On by default — Beranda and
  /// the other browsing tabs all lead to buying.
  final bool showCart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              onTap: () => context.go(Routes.search),
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
          if (showCart) ...[
            const SizedBox(width: 4),
            _CartButton(count: ref.watch(cartProvider).length),
          ],
        ],
      ),
    );
  }
}

/// Cart icon with the item-count badge, as sketched beside the search field.
class _CartButton extends StatelessWidget {
  const _CartButton({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.shopping_cart_outlined, size: 22),
          onPressed: () => context.push(Routes.cart),
        ),
        if (count > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$count',
                style: AppTypography.badge(colors.onPrimary)
                    .copyWith(fontSize: 9),
              ),
            ),
          ),
      ],
    );
  }
}
