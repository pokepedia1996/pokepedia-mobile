import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/card_art.dart';
import '../../repository/models/portfolio_value.dart';
import '../../usecase/portfolio_value_notifier.dart';

/// "Nilai Tertinggi" — the selected portfolio's most valuable holdings.
class TopHoldingsSection extends ConsumerWidget {
  const TopHoldingsSection({super.key, this.limit = 3});

  /// How many rows before "Lihat semua" takes over.
  final int limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();

    final holdings = ref.watch(topHoldingsProvider);
    if (holdings.isEmpty) return const SizedBox.shrink();

    final shown = holdings.take(limit).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Text(
                'Nilai Tertinggi',
                style: AppTypography.bodySmSemibold(
                  context.appColors.onSurface,
                ),
              ),
            ),
            for (final holding in shown) ...[
              Divider(height: 1, color: context.borderColor),
              _HoldingRow(holding: holding),
            ],
            Divider(height: 1, color: context.borderColor),
            InkWell(
              onTap: () => context.push(Routes.portfolio),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Lihat semua',
                  textAlign: TextAlign.center,
                  style: AppTypography.captionSemibold(
                    context.appColors.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoldingRow extends StatelessWidget {
  const _HoldingRow({required this.holding});

  final PortfolioHolding holding;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    // "023/165 · Rare" — the sketch's "nomor + set · rarity" line.
    final meta = [
      '${holding.collectorNumber} · ${holding.expansionCode.toUpperCase()}',
      if (holding.rarity != null && holding.rarity!.isNotEmpty) holding.rarity!,
    ].join(' · ');

    return InkWell(
      onTap: () => context.push(
        Routes.cardDetail(holding.packSlug, holding.cardId),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: CardArt(
                imageUrl: holding.imageUrl,
                borderRadius: AppRadius.sm,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    holding.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  Text(
                    meta,
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
                  formatRupiah(holding.value),
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
                if (holding.quantity > 1)
                  Text(
                    '×${holding.quantity}',
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
