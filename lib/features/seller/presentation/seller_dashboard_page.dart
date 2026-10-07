import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../repository/models/seller_dashboard.dart';
import '../repository/seller_repository.dart';
import '../usecase/offers_notifier.dart';
import '../usecase/seller_listings_notifier.dart';
import '../usecase/seller_notifier.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import 'widgets/seller_header.dart';
import 'widgets/daily_gmv_chart.dart';

/// Ports `app/seller/page.tsx` — the seller's home: today's queue, the
/// performance window with its metric cards and daily net-revenue chart, and
/// the rolling revenue summary.
///
/// Every number here comes from `get_seller_performance`, which the app
/// calls on the seller's own session (it's granted to `authenticated` and
/// scopes itself with `auth.uid()`), so this screen needs no server route.
class SellerDashboardPage extends ConsumerWidget {
  const SellerDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;

    // No app bar. This is a tab, not a pushed page: there is nothing to go
    // back to, and the bar's back arrow sat directly on top of the wordmark
    // while `AppBarOverlayBody` pushed the whole dashboard down by its
    // height. The page carries its own header instead.
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: user == null
            ? EmptyState(
                icon: LucideIcons.store,
                title: 'Masuk untuk membuka dasbor',
                description: 'Dasbor penjual hanya untuk pemilik toko.',
                action: ElevatedButton(
                  onPressed: () => context.push(Routes.login),
                  child: const Text('Masuk'),
                ),
              )
            : const _DashboardBody(),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasStore = ref.watch(hasStoreProvider);

    return hasStore.when(
      loading: () => const PikachuLoader(),
      error: (_, __) => const _DashboardScroll(),
      data: (has) => has ? const _DashboardScroll() : const _NoStoreState(),
    );
  }
}

/// Opening a store writes details the app has no form for, so this points
/// at the web rather than dead-ending.
class _NoStoreState extends StatelessWidget {
  const _NoStoreState();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: LucideIcons.store,
      title: 'Belum punya toko',
      description:
          'Buka toko dulu di pokepedia.id, lalu kelola penjualannya dari sini.',
      action: ElevatedButton(
        onPressed: () => context.push(Routes.settings),
        child: const Text('Buka Pengaturan'),
      ),
    );
  }
}

class _DashboardScroll extends ConsumerStatefulWidget {
  const _DashboardScroll();

  @override
  ConsumerState<_DashboardScroll> createState() => _DashboardScrollState();
}

class _DashboardScrollState extends ConsumerState<_DashboardScroll> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final async = ref.watch(sellerDashboardProvider);
    final identity =
        ref.watch(sellerIdentityProvider).valueOrNull ?? const SellerIdentity();
    final window = ref.watch(sellerWindowProvider);

    if (async.isLoading && !async.hasValue) return const PikachuLoader();

    // A null payload means the RPC failed. The web keeps the whole layout
    // and puts a banner on top of zeroed numbers rather than swapping in an
    // error screen, so the seller can still navigate.
    final payload = async.valueOrNull ?? DashboardPayload.empty(window.days);
    final failed = async.hasError || async.valueOrNull == null;
    final displayName = identity.username ?? 'Penjual';

    final counts = ref.watch(sellerListingCountsProvider).valueOrNull;
    final drafts = ref.watch(sellerDraftsProvider).valueOrNull?.length ?? 0;
    final offers = ref
        .watch(offerCountsProvider)
        .values
        .fold<int>(0, (sum, c) => sum + c.needsResponse);
    final kpi = payload.kpi;
    final openOrders =
        kpi.awaitingPayment + kpi.toShip + kpi.inTransit + kpi.arrived;

    // What the seller has to *do*, in the order it costs them if ignored:
    // an unshipped order is a clock already running, an offer is money
    // waiting on an answer, a complaint is already someone else's move.
    final tasks = <({String label, int count, bool urgent, String route})>[
      (
        label: 'Perlu dikirim',
        count: kpi.toShip,
        urgent: kpi.toShip > 0,
        route: Routes.sellerOrdersFiltered('to_ship'),
      ),
      (
        label: 'Ada penawaran masuk',
        count: offers,
        urgent: offers > 0,
        // The listings with offers on them, filtered — not the whole list
        // on whichever tab happened to be open last.
        route: Routes.sellerProductsWithOffers(),
      ),
      (
        label: 'Komplain terbuka',
        count: kpi.disputesOpen,
        urgent: kpi.disputesOpen > 0,
        route: Routes.sellerOrdersFiltered('disputes'),
      ),
    ];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(sellerDashboardProvider);
        ref.invalidate(sellerIdentityProvider);
        ref.invalidate(sellerListingTabCountsProvider);
        await ref.read(sellerDashboardProvider.future);
      },
      child: ListView(
        padding: EdgeInsets.only(
          bottom: AppBottomNav.reservedSpace(context) + 16,
        ),
        children: [
          SellerHeader(controller: _search),
          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'Halo, $displayName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.h3(colors.onSurface),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => context.push(Routes.sellerStore),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(LucideIcons.arrowUpRight, size: 14),
                  label: const Text('Atur Toko'),
                  style: TextButton.styleFrom(
                    foregroundColor: context.mutedForeground,
                    textStyle: AppTypography.bodySmSemibold(
                      context.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (failed) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ErrorBanner(
                onRetry: () => ref.invalidate(sellerDashboardProvider),
              ),
            ),
          ],

          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InkWell(
              onTap: () => context.push(Routes.sellerPerformance),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: _RevenueBlock(summary: payload.summary),
            ),
          ),

          const SizedBox(height: 14),
          _StatStrip(
            active: counts?.active,
            orders: openOrders,
            drafts: drafts,
            inactive: counts?.inactive,
          ),

          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Tugas \u00b7 ${tasks.length}',
              style: AppTypography.bodySemibold(colors.onSurface),
            ),
          ),
          const SizedBox(height: 10),
          for (final task in tasks)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _TaskRow(
                label: task.label,
                count: task.count,
                urgent: task.urgent,
                onTap: () => context.push(task.route),
              ),
            ),

          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: context.borderColor, height: 1),
          ),
          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Pembayaran',
              style: AppTypography.bodySemibold(colors.onSurface),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _WalletPill(balance: payload.walletBalance),
          ),

          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              onPressed: () => context.push(Routes.sellerProductsTab('draft')),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Tambahkan Listing'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.onSurface,
                foregroundColor: Theme.of(context).cardColor,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "OMZET 30 HARI" and what it did — the one number a seller opens this
/// page for.
class _RevenueBlock extends StatelessWidget {
  const _RevenueBlock({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final up = summary.delta30 >= 0;
    final tone = up ? context.appSemantic.success : colors.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'OMZET 30 HARI',
              style: AppTypography.overline(context.mutedForeground),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message:
                  'Nilai transaksi selesai dalam 30 hari terakhir, '
                  'dibandingkan 30 hari sebelumnya.',
              triggerMode: TooltipTriggerMode.tap,
              child: Icon(
                LucideIcons.info,
                size: 13,
                color: context.mutedForeground,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatRupiah(summary.last30),
                  maxLines: 1,
                  style: AppTypography.h2(colors.onSurface),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    up ? LucideIcons.trendingUp : LucideIcons.trendingDown,
                    size: 15,
                    color: tone,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${up ? '+' : ''}${summary.delta30.toStringAsFixed(0)}%',
                    style: AppTypography.bodySmSemibold(tone),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// AKTIF / PESANAN / DRAFT / INAKTIF. Scrolls sideways rather than squeezing
/// four columns onto a phone, which is what the design does: the first two
/// are the ones that matter daily and they stay in view.
class _StatStrip extends StatelessWidget {
  const _StatStrip({
    required this.active,
    required this.orders,
    required this.drafts,
    required this.inactive,
  });

  final int? active;
  final int orders;
  final int drafts;
  final int? inactive;

  @override
  Widget build(BuildContext context) {
    // Each tile opens the tab it counted. They all used to land on Kelola
    // Listing as it was last left, so tapping "DRAFT" and arriving on Aktif
    // read as the tap having gone somewhere else entirely.
    final tiles = <({String label, int? value, String route})>[
      (
        label: 'AKTIF',
        value: active,
        route: Routes.sellerProductsTab('active'),
      ),
      (label: 'PESANAN', value: orders, route: Routes.sellerOrders),
      (label: 'DRAFT', value: drafts, route: Routes.sellerProductsTab('draft')),
      (
        label: 'INAKTIF',
        value: inactive,
        route: Routes.sellerProductsTab('inactive'),
      ),
    ];

    return SizedBox(
      height: 66,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final tile = tiles[i];
          return _StatTile(
            label: tile.label,
            value: tile.value,
            onTap: () => context.push(tile.route),
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;

  /// Null while the count is still being fetched — shown as a dash rather
  /// than a zero, which would read as "you have none" for as long as the
  /// query takes.
  final int? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        width: 100,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: context.mutedForeground.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        // Both lines scale down rather than overflow: the tile is a fixed
        // height in a horizontal strip, so it has nowhere to grow, and the
        // label is a word whose length varies with translation.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  style: AppTypography.overline(context.mutedForeground),
                ),
              ),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value == null ? '-' : '$value',
                  maxLines: 1,
                  style: AppTypography.bodySemibold(
                    context.appColors.onSurface,
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

/// One line of the Tugas list: what needs doing and how much of it.
class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.label,
    required this.count,
    required this.urgent,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool urgent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySm(colors.onSurface),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(minWidth: 24),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // Red only when there is something to do. A zero in the
                // same red would train the seller to ignore the colour.
                color: urgent
                    ? colors.error
                    : context.mutedForeground.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                '$count',
                style: AppTypography.captionSemibold(
                  urgent ? Colors.white : context.mutedForeground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The wallet row under "Pembayaran".
///
/// No pill around it and no border: it is the only row in its section, and a
/// card drawn around a single row is a box with nothing to separate it from.
/// The section heading above already says what it is.
class _WalletPill extends StatelessWidget {
  const _WalletPill({required this.balance});

  final int balance;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return InkWell(
      onTap: () => context.push(Routes.wallet),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            // A rounded square in the neutral fill, not a red circle. Red is
            // the brand's alert colour and this is a balance, not a warning;
            // the square matches the icon tiles in the bulk menu, which are
            // the same kind of thing — a label for the row beside it.
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: context.mutedForeground.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(
                LucideIcons.wallet,
                size: 18,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Saldo dompet',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatRupiah(balance),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySemibold(colors.onSurface),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: context.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Gagal memuat data dasbor. Beberapa angka mungkin belum akurat.',
              style: AppTypography.bodySm(colors.error),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Muat ulang')),
        ],
      ),
    );
  }
}

/// Ports `KpiStrip` — the three counters worth acting on today, each one a
/// link into the orders list filtered to what it counted, as on web.
/// The performance detail the dashboard's headline opens.
///
/// These charts used to sit on the dashboard itself, under everything else.
/// The dashboard is a page about what to do next — what is selling, what
/// needs shipping, what is owed — and a seller comparing thirty days to the
/// previous thirty is asking a different question, at a different moment.
/// Kept rather than dropped with the redesign: it is the only place the shop
/// can be seen over time.
class SellerPerformancePage extends ConsumerWidget {
  const SellerPerformancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sellerDashboardProvider);
    final window = ref.watch(sellerWindowProvider);
    final payload = async.valueOrNull ?? DashboardPayload.empty(window.days);

    return Scaffold(
      appBar: const TransparentAppBar(title: Text('Performa')),
      body: async.isLoading && !async.hasValue
          ? const PikachuLoader()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _WindowSwitcher(
                  selected: window,
                  onSelect: (next) =>
                      ref.read(sellerWindowProvider.notifier).state = next,
                ),
                const SizedBox(height: 12),
                _MetricGrid(performance: payload.performance),
                const SizedBox(height: 12),
                _ChartCard(
                  performance: payload.performance,
                  summary: payload.summary,
                ),
                const SizedBox(height: 20),
                const _SellerTools(),
              ],
            ),
    );
  }
}

class _WindowSwitcher extends StatelessWidget {
  const _WindowSwitcher({required this.selected, required this.onSelect});

  final SellerWindow selected;
  final ValueChanged<SellerWindow> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          for (final window in SellerWindow.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelect(window),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: window == selected
                        ? Theme.of(context).cardColor
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    window.label,
                    style: window == selected
                        ? AppTypography.captionSemibold(colors.onSurface)
                        : AppTypography.caption(context.mutedForeground),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ports the four `MetricCard`s. Two per row on a phone rather than the
/// web's four-across.
class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.performance});

  final DashboardPerformance performance;

  @override
  Widget build(BuildContext context) {
    final cards = [
      (
        'Omzet',
        formatRupiahCompact(performance.gmv),
        performance.gmv,
        performance.prevGmv,
      ),
      (
        'Pesanan',
        '${performance.orders}',
        performance.orders,
        performance.prevOrders,
      ),
      (
        'Item terjual',
        '${performance.items}',
        performance.items,
        performance.prevItems,
      ),
      (
        'Pembeli unik',
        '${performance.uniqueBuyers}',
        performance.uniqueBuyers,
        performance.prevUniqueBuyers,
      ),
    ];

    return Column(
      children: [
        for (var i = 0; i < cards.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = i; j < i + 2 && j < cards.length; j++) ...[
                  if (j > i) const SizedBox(width: 10),
                  Expanded(
                    child: _MetricCard(
                      label: cards[j].$1,
                      value: cards[j].$2,
                      current: cards[j].$3,
                      previous: cards[j].$4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.current,
    required this.previous,
  });

  final String label;
  final String value;
  final int current;
  final int previous;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final delta = percentDelta(current: current, previous: previous);
    final hasData = previous > 0 || current > 0;
    final positive = delta > 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.caption(context.mutedForeground)),
          const SizedBox(height: 4),
          Text(value, style: AppTypography.h3(colors.onSurface)),
          const SizedBox(height: 4),
          if (!hasData)
            Text(
              'Belum ada data',
              style: AppTypography.caption(context.mutedForeground),
            )
          else
            Row(
              children: [
                Icon(
                  positive ? LucideIcons.trendingUp : LucideIcons.trendingDown,
                  size: 13,
                  color: positive ? context.appSemantic.success : colors.error,
                ),
                const SizedBox(width: 3),
                Text(
                  '${delta.abs().toStringAsFixed(1)}%',
                  style: AppTypography.caption(
                    positive ? context.appSemantic.success : colors.error,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.performance, required this.summary});

  final DashboardPerformance performance;
  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pendapatan bersih harian (${performance.window} hari terakhir)',
            style: AppTypography.caption(context.mutedForeground),
          ),
          const SizedBox(height: 12),
          DailyGmvChart(data: performance.dailyGmv),
          const SizedBox(height: 14),
          Divider(height: 1, color: context.borderColor),
          const SizedBox(height: 10),
          _SummaryRow(label: 'Hari ini', value: summary.today),
          _SummaryRow(label: '7 hari terakhir', value: summary.last7),
          _SummaryRow(
            label: '30 hari terakhir',
            value: summary.last30,
            delta: summary.delta30,
          ),
          _SummaryRow(label: '90 hari terakhir', value: summary.last90),
          const SizedBox(height: 2),
          Text(
            'Ringkasan selalu dihitung dari 90 hari terakhir.',
            style: AppTypography.caption(context.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.delta});

  final String label;
  final int value;
  final double? delta;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final delta = this.delta;
    final positive = (delta ?? 0) >= 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
          ),
          if (delta != null) ...[
            Text(
              '${positive ? '+' : ''}${delta.toStringAsFixed(1)}%',
              style: AppTypography.caption(
                positive ? context.appSemantic.success : colors.error,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            formatRupiah(value),
            style: AppTypography.bodySmSemibold(colors.onSurface),
          ),
        ],
      ),
    );
  }
}

/// The seller workspace's other sections — web's `SECTIONS` in
/// `lib/seller/workspace-nav.ts`, minus Beranda, which is this page.

class _SellerTools extends StatelessWidget {
  const _SellerTools();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Alat penjual',
          style: AppTypography.bodySmSemibold(colors.onSurface),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: context.borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _ToolRow(
                icon: LucideIcons.package,
                label: 'Listing',
                description: 'Kelola produk, stok, dan arsip',
                onTap: () => context.push(Routes.sellerProducts),
              ),
              Divider(height: 1, color: context.borderColor),
              _ToolRow(
                icon: LucideIcons.receipt,
                label: 'Pesanan',
                description: 'Pesanan masuk dan pengiriman',
                onTap: () => context.push(Routes.sellerOrders),
              ),
              Divider(height: 1, color: context.borderColor),
              _ToolRow(
                icon: LucideIcons.store,
                label: 'Toko',
                description: 'Profil toko, kurir, dan chat pembeli',
                onTap: () => context.push(Routes.sellerStore),
              ),
              // No "Komplain" row: "Penting hari ini" already carries open
              // disputes, with the count on it and the same destination, so
              // a second entry here was the same link stated twice.
            ],
          ),
        ),
      ],
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;

  /// Null where the destination doesn't exist yet — the row says so rather
  /// than sending the seller somewhere that isn't what it promises.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final enabled = onTap != null;
    final foreground = enabled ? colors.onSurface : context.mutedForeground;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: context.mutedForeground),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.bodySmSemibold(foreground)),
                  const SizedBox(height: 1),
                  Text(
                    enabled ? description : 'Segera hadir',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
            if (enabled)
              Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: context.mutedForeground,
              ),
          ],
        ),
      ),
    );
  }
}
