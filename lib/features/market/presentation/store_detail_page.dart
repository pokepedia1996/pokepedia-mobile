import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/listing_card.dart';
import '../usecase/market_notifier.dart';

/// Ports `components/store/storefront-view.tsx` — a seller's storefront.
class StoreDetailPage extends ConsumerWidget {
  const StoreDetailPage({super.key, required this.handle});

  final String handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeAsync = ref.watch(storeDetailProvider(handle));
    final listingsAsync = ref.watch(storeListingsProvider(handle));
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(
        title: storeAsync.when(
          data: (store) => Text(store?.storeName ?? 'Toko'),
          loading: () => const Text('Memuat...'),
          error: (_, __) => const Text('Toko'),
        ),
      ),
      body: storeAsync.when(
        data: (store) {
          if (store == null) {
            return const EmptyState(
              icon: Icons.store_mall_directory_outlined,
              title: 'Toko tidak ditemukan',
            );
          }
          return SafeArea(
            top: false,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        border: Border.all(color: context.borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: colors.secondary,
                                child: Text(
                                  store.storeName.substring(0, 1).toUpperCase(),
                                  style: AppTypography.h2(colors.onSurface),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            store.storeName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppTypography.h3(
                                              colors.onSurface,
                                            ),
                                          ),
                                        ),
                                        if (store.isVerified) ...[
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.verified,
                                            size: 16,
                                            color: colors.primary,
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      store.tagline,
                                      style: AppTypography.bodySm(
                                        context.mutedForeground,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (store.onVacation) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: colors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.beach_access_outlined, size: 14, color: colors.error),
                                  const SizedBox(width: 6),
                                  Text('Toko sedang libur', style: AppTypography.captionSemibold(colors.error)),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              _Stat(
                                icon: Icons.shopping_bag_outlined,
                                label: '${store.activeListingCount} listing',
                              ),
                              _Stat(
                                icon: Icons.place_outlined,
                                label: store.cityName,
                              ),
                              _Stat(
                                icon: Icons.sell_outlined,
                                label: '${store.itemsSoldCount} terjual',
                              ),
                              _Stat(
                                icon: Icons.people_outline,
                                label: '${store.followersCount} pengikut',
                              ),
                              if (store.topRated)
                                _Stat(icon: Icons.star, label: 'Top Rated'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: listingsAsync.when(
                    data: (listings) {
                      if (listings.isEmpty) {
                        return const SliverToBoxAdapter(
                          child: EmptyState(
                            icon: Icons.storefront_outlined,
                            title: 'Belum ada listing',
                          ),
                        );
                      }
                      return SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.42,
                            ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => ListingCard(listing: listings[i], showSeller: false),
                          childCount: listings.length,
                        ),
                      );
                    },
                    loading: () => const SliverToBoxAdapter(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, __) => const SliverToBoxAdapter(
                      child: Text('Gagal memuat listing'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const EmptyState(
          icon: Icons.error_outline,
          title: 'Gagal memuat toko',
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: context.mutedForeground),
        const SizedBox(width: 4),
        Text(label, style: AppTypography.caption(context.mutedForeground)),
      ],
    );
  }
}
