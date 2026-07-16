import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../features/cart/usecase/cart_notifier.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/listing_card.dart';
import '../../../shared/widgets/store_card.dart';
import '../usecase/market_notifier.dart';

/// Ports `app/market/page.tsx` — marketplace bucket tabs
/// (Semua/Listing/Buylist/Toko) with search.
class MarketPage extends ConsumerWidget {
  const MarketPage({super.key});

  static const _buckets = [
    (MarketBucket.all, 'Semua'),
    (MarketBucket.listing, 'Listing'),
    (MarketBucket.buylist, 'Buylist'),
    (MarketBucket.toko, 'Toko'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bucket = ref.watch(bucketProvider);
    final colors = context.appColors;

    final cartCount = ref.watch(cartProvider).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Market'),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined),
                onPressed: () => context.push(Routes.cart),
              ),
              if (cartCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$cartCount',
                      style: AppTypography.badge(colors.onPrimary).copyWith(fontSize: 9),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                onChanged: (v) => ref.read(marketQueryProvider.notifier).state = v,
                decoration: const InputDecoration(
                  hintText: 'Cari kartu atau toko...',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _buckets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final (value, label) = _buckets[i];
                  final selected = bucket == value;
                  return InkWell(
                    onTap: () => ref.read(bucketProvider.notifier).state = value,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? colors.primary : colors.secondary,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        label,
                        style: AppTypography.bodySmSemibold(
                          selected ? colors.onPrimary : colors.onSurface,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: bucket == MarketBucket.toko
                  ? const _StoreDirectory()
                  : const _ListingGrid(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListingGrid extends ConsumerWidget {
  const _ListingGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(marketListingsProvider);
    return async.when(
      data: (listings) {
        if (listings.isEmpty) {
          return const EmptyState(
            icon: Icons.storefront_outlined,
            title: 'Tidak ada listing',
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: listings.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.6,
          ),
          itemBuilder: (context, i) {
            final listing = listings[i];
            return ListingCard(
              listing: listing,
              onTap: () => context.push(Routes.storeDetail(listing.storeSlug)),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Gagal memuat listing')),
    );
  }
}

class _StoreDirectory extends ConsumerWidget {
  const _StoreDirectory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(marketStoresProvider);
    return async.when(
      data: (stores) {
        if (stores.isEmpty) {
          return const EmptyState(
            icon: Icons.store_mall_directory_outlined,
            title: 'Toko tidak ditemukan',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: stores.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final store = stores[i];
            return StoreCard(
              store: store,
              onTap: () => context.push(Routes.storeDetail(store.handle)),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Gagal memuat toko')),
    );
  }
}
