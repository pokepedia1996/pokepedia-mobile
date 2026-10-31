import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/design_palette.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/setup_kit.dart';
import '../../../shared/widgets/store_card.dart' show TopSellerBadge;
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../orders/repository/models/seller_order.dart';
import '../repository/models/my_reliability.dart';
import '../repository/models/seller_dashboard.dart';
import '../repository/seller_repository.dart';
import '../usecase/offers_notifier.dart';
import '../usecase/seller_listings_notifier.dart';
import '../usecase/seller_notifier.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import 'store_setup/store_setup_launcher.dart';
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
            ? Center(
                child: EmptyState(
                  icon: LucideIcons.store,
                  title: 'Masuk untuk membuka dasbor',
                  description: 'Dasbor penjual hanya untuk pemilik toko.',
                  action: ElevatedButton(
                    onPressed: () => context.push(Routes.login),
                    child: const Text('Masuk'),
                  ),
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
      // No store yet: Buka Toko's launcher, where the dashboard would be.
      data: (has) =>
          has ? const _DashboardScroll() : const StoreSetupLauncher(),
    );
  }
}

class _DashboardScroll extends ConsumerWidget {
  const _DashboardScroll();

  /// Space between the sticky button and the nav pill under it.
  static const _stickyGap = 12.0;
  static const _stickyHeight = 54.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = DesignPalette.of(context);
    final async = ref.watch(sellerDashboardProvider);
    final identity =
        ref.watch(sellerIdentityProvider).valueOrNull ?? const SellerIdentity();
    final window = ref.watch(sellerWindowProvider);
    final reliability = ref.watch(myReliabilityProvider).valueOrNull;

    if (async.isLoading && !async.hasValue) return const PikachuLoader();

    // A null payload means the RPC failed. The web keeps the whole layout
    // and puts a banner on top of zeroed numbers rather than swapping in an
    // error screen, so the seller can still navigate.
    final payload = async.valueOrNull ?? DashboardPayload.empty(window.days);
    final failed = async.hasError || async.valueOrNull == null;
    final displayName = identity.username ?? 'Penjual';
    final storeHandle = identity.storeHandle;

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
    final tasks = <({String label, int count, String route})>[
      (
        label: 'Perlu dikirim',
        count: kpi.toShip,
        route: Routes.sellerOrdersFiltered(SellerOrderTab.urgent.filterKey),
      ),
      (
        label: 'Ada penawaran masuk',
        count: offers,
        // The listings with offers on them, filtered — not the whole list
        // on whichever tab happened to be open last.
        route: Routes.sellerProductsWithOffers(),
      ),
      (
        label: 'Komplain terbuka',
        count: kpi.disputesOpen,
        route: Routes.sellerOrdersFiltered(SellerOrderTab.disputed.filterKey),
      ),
    ];
    // Web's heading counts the work, not the rows: "Tugas · 0" is a clear
    // day, where "Tugas · 3" over three zeros read as three things to do.
    final openTaskCount = tasks.fold<int>(0, (sum, t) => sum + t.count);

    // Sticky above the nav pill, per the design team: the one action this
    // page exists for stays in reach however far down the seller is.
    final stickyBottom = AppBottomNav.reservedSpace(context) + _stickyGap;
    const gap = SizedBox(height: 24);

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(sellerDashboardProvider);
            ref.invalidate(sellerIdentityProvider);
            ref.invalidate(sellerListingTabCountsProvider);
            ref.invalidate(myReliabilityProvider);
            await ref.read(sellerDashboardProvider.future);
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              // The last section scrolls clear of the button and the pill.
              stickyBottom + _stickyHeight + 24,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 20),
                child: Row(
                  children: [
                    Text('Jual', style: setupHeading(32, palette.ink)),
                    const Spacer(),
                    const SellerNotificationBell(framed: true),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Halo, $displayName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: setupHeading(22, palette.ink),
                    ),
                  ),
                  if (storeHandle != null) ...[
                    _HeaderLink(
                      label: 'Lihat Toko',
                      onTap: () =>
                          context.push(Routes.storeDetail(storeHandle)),
                    ),
                    const SizedBox(width: 16),
                  ],
                  _HeaderLink(
                    label: 'Atur Toko',
                    onTap: () => context.push(Routes.sellerStore),
                  ),
                ],
              ),
              if (failed) ...[
                const SizedBox(height: 16),
                _ErrorBanner(
                  onRetry: () => ref.invalidate(sellerDashboardProvider),
                ),
              ],
              gap,
              InkWell(
                onTap: () => context.push(Routes.sellerPerformance),
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: _RevenueBlock(summary: payload.summary),
              ),
              gap,
              _StatStrip(
                active: counts?.active,
                orders: openOrders,
                drafts: drafts,
                inactive: counts?.inactive,
              ),
              gap,
              Text(
                'Tugas · $openTaskCount',
                style: setupHeading(22, palette.ink),
              ),
              const SizedBox(height: 10),
              for (final task in tasks) ...[
                _TaskRow(
                  label: task.label,
                  count: task.count,
                  onTap: () => context.push(task.route),
                ),
                if (task != tasks.last) const SizedBox(height: 10),
              ],
              if (reliability != null) ...[
                gap,
                _ReliabilitySection(reliability: reliability),
              ],
              gap,
              _Section(
                title: 'Pembayaran',
                child: _WalletPill(balance: payload.walletBalance),
              ),
            ],
          ),
        ),
        // Fades the list out under the button so the two don't collide.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: stickyBottom + _stickyHeight + 48,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    palette.background.withValues(alpha: 0),
                    palette.background.withValues(alpha: 0.95),
                    palette.background,
                  ],
                  stops: const [0, 0.35, 1],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: stickyBottom,
          child: _StickyAddButton(
            height: _stickyHeight,
            onPressed: () => context.push(Routes.sellerProductsTab('draft')),
          ),
        ),
      ],
    );
  }
}

/// "Lihat Toko ↗" / "Atur Toko ↗" beside the greeting.
class _HeaderLink extends StatelessWidget {
  const _HeaderLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: setupText(14, palette.ink, FontWeight.w500)),
            const SizedBox(width: 3),
            Icon(LucideIcons.arrowUpRight, size: 14, color: palette.ink),
          ],
        ),
      ),
    );
  }
}

class _StickyAddButton extends StatelessWidget {
  const _StickyAddButton({required this.height, required this.onPressed});

  final double height;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1C1413).withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: palette.ctaBackground,
        shape: const StadiumBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const StadiumBorder(),
          child: SizedBox(
            height: height,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.plus, size: 20, color: palette.ctaForeground),
                const SizedBox(width: 8),
                Text(
                  'Tambahkan Listing',
                  style: setupText(17, palette.ctaForeground, FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "OMZET 90 HARI" and what it did — the one number a seller opens this
/// page for.
class _RevenueBlock extends StatelessWidget {
  const _RevenueBlock({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final up = summary.delta90 >= 0;
    final tone = up ? palette.successText : palette.brand;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'OMZET 90 HARI',
              style: setupText(
                12,
                palette.muted,
                FontWeight.w600,
              ).copyWith(letterSpacing: 1),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message:
                  'Nilai transaksi selesai dalam 90 hari terakhir, '
                  'dibandingkan 90 hari sebelumnya.',
              triggerMode: TooltipTriggerMode.tap,
              child: Icon(LucideIcons.info, size: 14, color: palette.muted),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatRupiah(summary.last90),
                  maxLines: 1,
                  style: setupHeading(38, palette.ink),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              up ? LucideIcons.trendingUp : LucideIcons.trendingDown,
              size: 14,
              color: tone,
            ),
            const SizedBox(width: 3),
            Text(
              '${up ? '+' : ''}${summary.delta90.toStringAsFixed(0)}%',
              style: setupText(13, tone, FontWeight.w600),
            ),
          ],
        ),
      ],
    );
  }
}

/// AKTIF / PESANAN / DRAFT / INAKTIF, four across as the design has them.
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
      (
        label: 'PESANAN',
        value: orders,
        route: Routes.sellerOrdersFiltered(SellerOrderTab.all.filterKey),
      ),
      (label: 'DRAFT', value: drafts, route: Routes.sellerProductsTab('draft')),
      (
        label: 'INAKTIF',
        value: inactive,
        route: Routes.sellerProductsTab('inactive'),
      ),
    ];

    return Row(
      children: [
        for (final tile in tiles) ...[
          if (tile != tiles.first) const SizedBox(width: 10),
          Expanded(
            child: _StatTile(
              label: tile.label,
              value: tile.value,
              onTap: () => context.push(tile.route),
            ),
          ),
        ],
      ],
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
    final palette = DesignPalette.of(context);
    final radius = BorderRadius.circular(14);
    return Material(
      color: palette.chip,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.all(12),
          // Scaled down rather than overflowing: four tiles share a phone's
          // width, and "PESANAN" or a four-digit count has to fit either way.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: setupText(
                    11,
                    palette.muted,
                    FontWeight.w600,
                  ).copyWith(letterSpacing: 0.8),
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value == null ? '-' : '$value',
                  maxLines: 1,
                  style: setupText(20, palette.ink, FontWeight.w700),
                ),
              ),
            ],
          ),
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
    required this.onTap,
  });

  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final urgent = count > 0;
    final radius = BorderRadius.circular(14);

    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: palette.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: setupText(15, palette.ink, FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(
                  // Red only when there is something to do. A zero in the
                  // same red would train the seller to ignore the colour.
                  color: urgent ? palette.brand : palette.chip,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  '$count',
                  style: setupText(
                    12,
                    urgent ? Colors.white : palette.ink,
                    FontWeight.w600,
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

/// A titled block under a hairline, as web's lower sections are.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: setupHeading(22, palette.ink)),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Ports web's `ReliabilityCard`: the last 90 days at a glance, what is
/// still between the seller and Top Seller over the last 30, and which
/// orders were counted against them.
class _ReliabilitySection extends StatelessWidget {
  const _ReliabilitySection({required this.reliability});

  final MyReliability reliability;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final completion = reliability.completionPct;
    final median = reliability.medianShipHours;

    Widget metric(String label, String value, {Color? tone}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: setupText(13, palette.muted),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: setupText(18, tone ?? palette.ink, FontWeight.w700),
          ),
        ],
      ),
    );

    return _Section(
      title: 'Keandalan toko · 90 hari',
      trailing: reliability.topRated ? const TopSellerBadge() : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              metric(
                'Pesanan selesai',
                completion == null ? '-' : '$completion%',
              ),
              const SizedBox(width: 8),
              metric(
                'Batal karena penjual',
                '${reliability.cancelPct}%',
                tone: reliability.belowStandard ? palette.error : null,
              ),
              const SizedBox(width: 8),
              metric('Median kirim', median == null ? '-' : '$median jam'),
            ],
          ),
          // Already there, nothing to work towards; web hides it too.
          if (!reliability.topRated) ...[
            const SizedBox(height: 12),
            _TopSellerChecklist(
              requirements: reliability.topSellerRequirements,
            ),
          ],
          if (reliability.failures.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Pesanan yang dihitung gagal',
              style: setupText(15, palette.ink, FontWeight.w600),
            ),
            const SizedBox(height: 6),
            for (final f in reliability.failures)
              InkWell(
                onTap: () => context.push(Routes.sellerOrderDetail(f.itemSlug)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          f.orderNumber,
                          style: setupText(13, palette.ink, FontWeight.w500),
                        ),
                      ),
                      Text(f.faultLabel, style: setupText(13, palette.muted)),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// "Menuju Top Seller · 30 hari": each requirement ticked or not, with how
/// far off it is.
class _TopSellerChecklist extends StatelessWidget {
  const _TopSellerChecklist({required this.requirements});

  final List<TopSellerRequirement> requirements;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.chip,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Menuju Top Seller · 30 hari',
            style: setupText(15, palette.ink, FontWeight.w600),
          ),
          for (final r in requirements) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    r.met ? LucideIcons.check : LucideIcons.x,
                    size: 15,
                    color: r.met ? palette.success : palette.muted,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${r.label} · ${r.detail}',
                    style: setupText(13, palette.muted),
                  ),
                ),
              ],
            ),
          ],
        ],
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
