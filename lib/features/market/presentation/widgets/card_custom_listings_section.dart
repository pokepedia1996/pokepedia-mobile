import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/card_condition.dart';
import '../../../../shared/widgets/app_network_image.dart';
import '../../repository/models/card_custom_listing.dart';
import '../../usecase/market_notifier.dart';

/// "Listing custom" on a card's page — web's `CardCustomListings`: the
/// sellers' own bundles that have this card in them. Absent when none do.
class CardCustomListingsSection extends ConsumerWidget {
  const CardCustomListingsSection({super.key, required this.cardId});

  final int cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows =
        ref.watch(cardCustomListingsProvider(cardId)).valueOrNull ?? const [];
    if (rows.isEmpty) return const SizedBox.shrink();
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Listing custom',
            style: AppTypography.bodySemibold(colors.onSurface),
          ),
          const SizedBox(height: 10),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              children: [
                for (final (i, row) in rows.indexed) ...[
                  if (i > 0) Divider(height: 1, color: context.borderColor),
                  CardCustomListingRow(row: row),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

@visibleForTesting
class CardCustomListingRow extends StatelessWidget {
  const CardCustomListingRow({super.key, required this.row});

  final CardCustomListing row;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final handle = row.handle;
    final others = row.tagCount - 1;
    final seller = [
      row.storeName ?? row.username ?? '-',
      if (row.cityName case final city? when city.isNotEmpty) city,
    ].join(' · ');

    return InkWell(
      onTap: () => context.push(
        handle == null ? Routes.market : Routes.customListing(handle, row.slug),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colors.secondary,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: row.coverUrl == null
                  ? Icon(
                      LucideIcons.packageOpen,
                      size: 20,
                      color: context.mutedForeground,
                    )
                  : cachedNetworkImage(
                      row.coverUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colors.secondary,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          'CUSTOM',
                          style: AppTypography.badge(colors.onSurface),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Kartu ini ${row.tagCondition.short} '
                          '×${row.tagQuantity}'
                          '${others > 0 ? ' · +$others kartu lain' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    seller,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatRupiah(row.price),
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
                Text(
                  '${row.available} tersedia',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
