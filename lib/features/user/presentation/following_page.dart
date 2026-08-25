import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../repository/models/profile_models.dart';
import '../usecase/user_notifier.dart';

/// Ports `app/account/following/page.tsx` — the shops the signed-in user
/// follows, each with its banner, seller line and four most recent listings.
class FollowingPage extends ConsumerWidget {
  const FollowingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final shopsAsync = ref.watch(followedShopsProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: shopsAsync.when(
          data: (shops) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                'Toko yang Diikuti',
                style: AppTypography.h2(colors.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                'Pantau listing terbaru dari toko favoritmu.',
                style: AppTypography.bodySm(context.mutedForeground),
              ),
              const SizedBox(height: 20),
              if (shops.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: Border.all(color: context.borderColor),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: EmptyState(
                    icon: Icons.favorite_border,
                    title: 'Belum ada toko yang diikuti',
                    description:
                        'Kunjungi halaman toko penjual favoritmu dan tekan '
                        '"Ikuti" untuk menambahkannya di sini.',
                    action: ElevatedButton(
                      onPressed: () => context.push(Routes.market),
                      child: const Text('Jelajahi Market'),
                    ),
                  ),
                )
              else
                for (final shop in shops)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _FollowedShopCard(shop: shop),
                  ),
            ],
          ),
          loading: () => const PikachuLoader(),
          error: (_, __) => const EmptyState(
            icon: Icons.error_outline,
            title: 'Gagal memuat toko',
          ),
        ),
      ),
    );
  }
}

class _FollowedShopCard extends StatelessWidget {
  const _FollowedShopCard({required this.shop});

  final FollowedShop shop;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: () => context.push(Routes.storeDetail(shop.slug)),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: context.borderColor),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (shop.bannerUrl != null)
              AspectRatio(
                aspectRatio: 4,
                child: Image.network(
                  shop.bannerUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      ColoredBox(color: colors.secondary),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  UserAvatar(
                    username: shop.name,
                    imageUrl: shop.logoUrl,
                    size: 52,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shop.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmSemibold(colors.onSurface),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${shop.cityName ?? '-'} · ${shop.itemsSoldCount} terjual',
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: context.mutedForeground),
                ],
              ),
            ),
            if (shop.recentListings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Row(
                  children: [
                    for (final listing in shop.recentListings)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _ListingThumb(
                            shopSlug: shop.slug,
                            listing: listing,
                          ),
                        ),
                      ),
                    // Keeps a short row left-aligned instead of stretching
                    // three thumbnails across the full width.
                    for (var i = shop.recentListings.length; i < 4; i++)
                      const Expanded(child: SizedBox.shrink()),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ListingThumb extends StatelessWidget {
  const _ListingThumb({required this.shopSlug, required this.listing});

  final String shopSlug;
  final FollowedShopListing listing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: () =>
          context.push(Routes.storeCardDetail(shopSlug, listing.cardId)),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (listing.photoUrl == null)
                Image.asset('assets/images/backcard.webp', fit: BoxFit.cover)
              else
                Image.network(
                  listing.photoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => ColoredBox(
                    color: colors.secondary,
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.6),
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    formatRupiah(listing.price),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.badge(Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
