import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/listing_card.dart';
import '../../../market/usecase/market_filters.dart';
import '../../usecase/home_feed_notifier.dart';

/// The Beranda marketplace feed: recent listings in a two-up grid, with the
/// sort control and a way through to the full market.
///
/// This runs off its own providers rather than the market page's, so
/// changing the sort here doesn't quietly reconfigure that screen.
class MarketplaceFeedSection extends ConsumerWidget {
  const MarketplaceFeedSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final async = ref.watch(homeFeedProvider);
    final sort = ref.watch(homeFeedSortProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Marketplace',
                style: AppTypography.h3(colors.onSurface),
              ),
              const Spacer(),
              InkWell(
                onTap: () => context.go(Routes.market),
                child: Row(
                  children: [
                    Text(
                      'Lihat semua',
                      style: AppTypography.captionSemibold(colors.primary),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.north_east, size: 13, color: colors.primary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _SortRow(
            sort: sort,
            onSelect: (next) =>
                ref.read(homeFeedSortProvider.notifier).state = next,
          ),
          const SizedBox(height: 10),

          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Gagal memuat listing',
                  style: AppTypography.bodySm(context.mutedForeground),
                ),
              ),
            ),
            data: (listings) {
              if (listings.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Belum ada listing',
                      style: AppTypography.bodySm(context.mutedForeground),
                    ),
                  ),
                );
              }
              return GridView.builder(
                // The feed is one section of a scrolling page, so it lays
                // out in full rather than scrolling itself.
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: listings.length,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.46,
                    ),
                itemBuilder: (context, i) =>
                    ListingCard(listing: listings[i]),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SortRow extends StatelessWidget {
  const _SortRow({required this.sort, required this.onSelect});

  final MarketSort sort;
  final ValueChanged<MarketSort> onSelect;

  static const _labels = {
    MarketSort.createdDesc: 'Relevan',
    MarketSort.priceAsc: 'Harga terendah',
    MarketSort.priceDesc: 'Harga tertinggi',
    MarketSort.createdAsc: 'Terlama',
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Sort by:',
          style: AppTypography.caption(context.mutedForeground),
        ),
        const SizedBox(width: 4),
        InkWell(
          onTap: () => _open(context),
          child: Row(
            children: [
              Text(
                _labels[sort] ?? 'Relevan',
                style: AppTypography.captionSemibold(
                  context.appColors.onSurface,
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color: context.mutedForeground,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<MarketSort>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in _labels.entries)
              ListTile(
                title: Text(
                  entry.value,
                  style: AppTypography.bodySm(context.appColors.onSurface),
                ),
                trailing: entry.key == sort
                    ? Icon(Icons.check, color: context.appColors.primary)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(entry.key),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onSelect(picked);
  }
}
