import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../usecase/seller_notifier.dart';
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

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: user == null
            ? EmptyState(
                icon: Icons.storefront_outlined,
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
      icon: Icons.storefront_outlined,
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

class _DashboardScroll extends ConsumerWidget {
  const _DashboardScroll();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(sellerDashboardProvider);
        ref.invalidate(sellerIdentityProvider);
        await ref.read(sellerDashboardProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('Halo, $displayName', style: AppTypography.h2(colors.onSurface)),
          const SizedBox(height: 2),
          Text(
            'Ringkasan aktivitas toko dan performa penjualan kamu.',
            style: AppTypography.bodySm(context.mutedForeground),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(child: _WalletPill(balance: payload.walletBalance)),
              if (identity.storeHandle != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      context.push(Routes.storeDetail(identity.storeHandle!)),
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: const Text('Toko'),
                ),
              ],
            ],
          ),

          if (failed) ...[
            const SizedBox(height: 12),
            _ErrorBanner(
              onRetry: () => ref.invalidate(sellerDashboardProvider),
            ),
          ],

          const SizedBox(height: 20),
          Text(
            'Penting hari ini',
            style: AppTypography.bodySmSemibold(colors.onSurface),
          ),
          const SizedBox(height: 8),
          _KpiStrip(kpi: payload.kpi),

          const SizedBox(height: 20),
          // Web puts these behind a nav bar across the top of every seller
          // page; on a phone that bar would compete with the app's own
          // chrome, so the same destinations live here as a section.
          const _SellerTools(),

          const SizedBox(height: 20),
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
        ],
      ),
    );
  }
}

class _WalletPill extends StatelessWidget {
  const _WalletPill({required this.balance});

  final int balance;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: () => context.push(Routes.wallet),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Saldo dompet',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                  Text(
                    formatRupiah(balance),
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, size: 16, color: context.mutedForeground),
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

/// Ports `KpiStrip` — the three counters worth acting on today. The web's
/// links carry a `?filter=` the mobile orders screen doesn't read yet, so
/// these are plain counters for now.
class _KpiStrip extends StatelessWidget {
  const _KpiStrip({required this.kpi});

  final DashboardKpi kpi;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        children: [
          _KpiCell(
            label: 'Perlu dikirim',
            count: kpi.toShip,
            icon: Icons.inventory_2_outlined,
            tone: kpi.toShip > 0 ? _KpiTone.warning : _KpiTone.neutral,
          ),
          Divider(height: 1, color: context.borderColor),
          _KpiCell(
            label: 'Sedang dikirim',
            count: kpi.inTransit,
            icon: Icons.local_shipping_outlined,
            tone: _KpiTone.neutral,
          ),
          Divider(height: 1, color: context.borderColor),
          _KpiCell(
            label: 'Komplain terbuka',
            count: kpi.disputesOpen,
            icon: Icons.gpp_maybe_outlined,
            tone: kpi.disputesOpen > 0 ? _KpiTone.danger : _KpiTone.neutral,
          ),
        ],
      ),
    );
  }
}

enum _KpiTone { neutral, warning, danger }

class _KpiCell extends StatelessWidget {
  const _KpiCell({
    required this.label,
    required this.count,
    required this.icon,
    required this.tone,
  });

  final String label;
  final int count;
  final IconData icon;
  final _KpiTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final active = count > 0;
    final accent = switch (tone) {
      _KpiTone.danger => colors.error,
      _KpiTone.warning => context.appSemantic.gold,
      _KpiTone.neutral => context.mutedForeground,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: active ? accent.withValues(alpha: 0.12) : colors.secondary,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              icon,
              size: 17,
              color: active ? accent : context.mutedForeground,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: AppTypography.bodySemibold(
                    active && tone != _KpiTone.neutral
                        ? accent
                        : colors.onSurface,
                  ),
                ),
                Text(
                  label,
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ports `WINDOW_OPTIONS`' segmented control.
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
                  positive ? Icons.trending_up : Icons.trending_down,
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
                icon: Icons.inventory_2_outlined,
                label: 'Listing',
                description: 'Kelola produk, stok, dan arsip',
                onTap: () => context.push(Routes.sellerProducts),
              ),
              Divider(height: 1, color: context.borderColor),
              _ToolRow(
                icon: Icons.receipt_long_outlined,
                label: 'Pesanan',
                description: 'Pesanan masuk dan pengiriman',
                onTap: () => context.push(Routes.sellerOrders),
              ),
              Divider(height: 1, color: context.borderColor),
              _ToolRow(
                icon: Icons.storefront_outlined,
                label: 'Toko',
                description: 'Profil toko, kurir, dan chat pembeli',
                onTap: () => context.push(Routes.sellerStore),
              ),
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
                Icons.chevron_right,
                size: 18,
                color: context.mutedForeground,
              ),
          ],
        ),
      ),
    );
  }
}
