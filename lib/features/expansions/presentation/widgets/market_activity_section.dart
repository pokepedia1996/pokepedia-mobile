import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/condition_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/card_condition.dart';
import '../../../../shared/widgets/image_lightbox.dart';
import '../../repository/models/market_models.dart';
import '../../usecase/expansions_notifier.dart';
import 'card_market_header.dart';
import 'market_price_chart.dart';

/// How many transactions the inline table loads, matching web's
/// `inlineSalesCount`.
const _salesPageSize = 20;

const _ranges = <({String label, int? days})>[
  (label: '7H', days: 7),
  (label: '30H', days: 30),
  (label: '90H', days: 90),
  (label: '1 Thn', days: null),
];

/// Ports the chart half of
/// `features/card-detail/components/market-activity.tsx` — the price chart
/// with its range selector and condition legend.
///
/// The sales table that used to sit underneath is [SalesHistorySection] now:
/// the card page stacks its market blocks in its own order, and the two
/// don't have to travel together.
///
/// The legend lists the conditions this card actually has data for (web
/// renders all 21 grades and dims the empty ones, which would be a long
/// scroll on a phone).
/// "Histori Transaksi" — what this card has actually sold for.
class SalesHistorySection extends ConsumerWidget {
  const SalesHistorySection({super.key, required this.cardId});

  final int cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final salesAsync = ref.watch(
      cardSalesProvider((cardId: cardId, limit: _salesPageSize)),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'Histori Transaksi',
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
              ),
              if ((salesAsync.valueOrNull?.total ?? 0) > 0)
                Text(
                  '${salesAsync.value!.total} transaksi',
                  style: AppTypography.caption(context.mutedForeground),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _SalesHistoryTable(
            page: salesAsync.valueOrNull,
            loading: salesAsync.isLoading,
          ),
        ],
      ),
    );
  }
}

class MarketActivitySection extends ConsumerStatefulWidget {
  const MarketActivitySection({super.key, required this.cardId});

  final int cardId;

  @override
  ConsumerState<MarketActivitySection> createState() =>
      _MarketActivitySectionState();
}

class _MarketActivitySectionState extends ConsumerState<MarketActivitySection> {
  int? _rangeDays = 7;
  Set<CardCondition>? _visible;

  /// Defaults to NM, falling back to whichever condition has data when the
  /// card has never sold in NM — web's `hasAppliedFallback` effect.
  Set<CardCondition> _visibleFor(List<MarketPricePoint> points) {
    final selected = _visible;
    if (selected != null) return selected;
    if (points.any((p) => p.condition == CardCondition.nm)) {
      return {CardCondition.nm};
    }
    if (points.isEmpty) return {CardCondition.nm};
    return {points.first.condition};
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final seriesAsync = ref.watch(
      marketPriceSeriesProvider((cardId: widget.cardId, days: _rangeDays)),
    );
    final points = seriesAsync.valueOrNull ?? const <MarketPricePoint>[];
    final visible = _visibleFor(points);
    final headline = _headlineFor(points, visible);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        headline == null
                            ? 'Belum ada harga'
                            : 'Harga ${headline.condition.short} terkini · '
                                  '${_rangeDays == null ? '1 tahun' : '$_rangeDays hari'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                    ),
                    for (final range in _ranges)
                      _RangePill(
                        label: range.label,
                        active: _rangeDays == range.days,
                        onTap: () => setState(() => _rangeDays = range.days),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      headline == null ? '-' : formatRupiah(headline.price),
                      style: AppTypography.h2(colors.onSurface),
                    ),
                    if (headline != null && headline.delta != 0)
                      PriceDeltaPill(
                        delta: headline.delta,
                        deltaPct: headline.deltaPct,
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
            child: seriesAsync.isLoading
                ? const SizedBox(height: 180)
                : MarketPriceChart(points: points, visibleConditions: visible),
          ),
          if (points.isNotEmpty)
            _ConditionLegend(
              conditions: _conditionsWithData(points),
              visible: visible,
              onToggle: (condition) => setState(() {
                final next = {...visible};
                if (!next.remove(condition)) next.add(condition);
                _visible = next;
              }),
            ),
        ],
      ),
    );
  }

  /// The visible condition with data, preferring NM — web's `headline` memo.
  MarketHeadline? _headlineFor(
    List<MarketPricePoint> points,
    Set<CardCondition> visible,
  ) {
    if (visible.isEmpty) return null;
    final ordered = [
      if (visible.contains(CardCondition.nm)) CardCondition.nm,
      ...CardCondition.values.where(
        (c) => c != CardCondition.nm && visible.contains(c),
      ),
    ];
    for (final condition in ordered) {
      final rows = points.where((p) => p.condition == condition).toList();
      if (rows.isEmpty) continue;
      final headline = MarketHeadline.fromSeries(rows);
      if (headline == null) continue;
      // The "1 Thn" range shows the price without a delta, like the web.
      return _rangeDays == null
          ? MarketHeadline(
              condition: headline.condition,
              price: headline.price,
              delta: 0,
              deltaPct: 0,
            )
          : headline;
    }
    return null;
  }

  List<CardCondition> _conditionsWithData(List<MarketPricePoint> points) {
    final present = points.map((p) => p.condition).toSet();
    return CardCondition.values.where(present.contains).toList();
  }
}

class _RangePill extends StatelessWidget {
  const _RangePill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? colors.primary : null,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Text(
            label,
            style: AppTypography.badge(
              active ? colors.onPrimary : context.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}

/// The chart's series toggles — a dot in the condition's own color, struck
/// through while the series is hidden.
class _ConditionLegend extends StatelessWidget {
  const _ConditionLegend({
    required this.conditions,
    required this.visible,
    required this.onToggle,
  });

  final List<CardCondition> conditions;
  final Set<CardCondition> visible;
  final ValueChanged<CardCondition> onToggle;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
      child: Row(
        children: [
          for (final condition in conditions)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                onTap: () => onToggle(condition),
                borderRadius: BorderRadius.circular(AppRadius.full),
                child: Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: visible.contains(condition)
                              ? conditionColorOf(context, condition)
                              : Colors.transparent,
                          border: Border.all(
                            color: conditionColorOf(context, condition),
                            width: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        condition.short,
                        style:
                            AppTypography.badge(
                              visible.contains(condition)
                                  ? context.appColors.onSurface
                                  : context.mutedForeground,
                            ).copyWith(
                              decoration: visible.contains(condition)
                                  ? null
                                  : TextDecoration.lineThrough,
                            ),
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

/// Ports `components/catalog/sales-history-list.tsx` — date / condition /
/// price rows, where an imported sale's date opens its Facebook post and an
/// on-platform sale's date opens the seller's photos.
class _SalesHistoryTable extends StatelessWidget {
  const _SalesHistoryTable({required this.page, required this.loading});

  final CardSalesPage? page;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final sales = page?.sales ?? const <CardSale>[];

    if (loading) {
      return Column(
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              height: 14,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: colors.secondary,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
            ),
        ],
      );
    }

    if (sales.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Icon(LucideIcons.receipt, size: 24, color: context.mutedForeground),
            const SizedBox(height: 6),
            Text(
              'Belum ada transaksi',
              style: AppTypography.bodySm(context.mutedForeground),
            ),
            const SizedBox(height: 2),
            Text(
              'Transaksi yang sudah dibayar akan muncul di sini.',
              textAlign: TextAlign.center,
              style: AppTypography.caption(context.mutedForeground),
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 212),
      decoration: BoxDecoration(
        border: Border.all(color: context.borderColor),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.borderColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    'TANGGAL',
                    style: AppTypography.overline(context.mutedForeground),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'KONDISI',
                    textAlign: TextAlign.center,
                    style: AppTypography.overline(context.mutedForeground),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    'HARGA',
                    textAlign: TextAlign.right,
                    style: AppTypography.overline(context.mutedForeground),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: sales.length,
              itemBuilder: (context, i) {
                final sale = sales[i];
                return Container(
                  color: i.isOdd
                      ? colors.secondary.withValues(alpha: 0.3)
                      : null,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(flex: 4, child: _SaleDate(sale: sale)),
                      Expanded(
                        flex: 3,
                        child: Text(
                          sale.condition?.short ?? '-',
                          textAlign: TextAlign.center,
                          style: AppTypography.captionSemibold(
                            colors.onSurface,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          formatRupiah(sale.price),
                          textAlign: TextAlign.right,
                          style: AppTypography.captionSemibold(
                            colors.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleDate extends StatelessWidget {
  const _SaleDate({required this.sale});

  final CardSale sale;

  @override
  Widget build(BuildContext context) {
    final label = formatSaleDate(sale.date);
    final external =
        sale.source == SaleSource.external && sale.facebookUrl != null;
    final hasPhotos =
        sale.source == SaleSource.internal && sale.photoUrls.isNotEmpty;

    if (!external && !hasPhotos) {
      return Text(label, style: AppTypography.caption(context.mutedForeground));
    }

    return InkWell(
      onTap: () {
        if (external) {
          launcher.launchUrl(
            Uri.parse(sale.facebookUrl!),
            mode: launcher.LaunchMode.externalApplication,
          );
        } else {
          showImageLightbox(context, imageUrl: sale.photoUrls.first);
        }
      },
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              style: AppTypography.caption(
                context.mutedForeground,
              ).copyWith(decoration: TextDecoration.underline),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            external ? LucideIcons.externalLink : LucideIcons.image,
            size: 12,
            color: context.mutedForeground,
          ),
        ],
      ),
    );
  }
}
