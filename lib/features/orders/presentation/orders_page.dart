import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/condition_badge.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../repository/models/order_model.dart';
import '../usecase/orders_notifier.dart';

/// Ports `features/orders/components/orders-page.tsx` — the buyer's orders
/// behind a search box and the seven-tab filter strip, each order drawn as
/// the web's card: thumbnail, what was bought, and a footer carrying the
/// total and the way into the order.
class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key});

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  final _searchController = TextEditingController();

  OrderTab _tab = OrderTab.all;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Card name, seller and tracking number — what web's box searches, plus
  /// the order number, which is the thing people paste from a receipt.
  bool _matches(OrderModel order) {
    if (_query.isEmpty) return true;
    final needle = _query.toLowerCase();
    if (order.orderNumber.toLowerCase().contains(needle)) return true;
    if (order.storeName.toLowerCase().contains(needle)) return true;
    if ((order.trackingNumber ?? '').toLowerCase().contains(needle)) {
      return true;
    }
    return order.items.any(
      (item) => item.card.name.toLowerCase().contains(needle),
    );
  }

  /// Postgrest errors carry the useful part in `message`; anything else
  /// gets its `toString`, trimmed to something a snackbar-sized box holds.
  String _describe(Object error) {
    final text = error is PostgrestException
        ? '${error.message}${error.code == null ? '' : ' (${error.code})'}'
        : error.toString();
    return text.length > 240 ? '${text.substring(0, 240)}...' : text;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ordersProvider);
    final signedIn = ref.watch(authProvider).valueOrNull != null;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: !signedIn
            ? EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Masuk untuk melihat pesanan',
                action: ElevatedButton(
                  onPressed: () => context.push(Routes.login),
                  child: const Text('Masuk'),
                ),
              )
            : async.when(
                data: _buildBody,
                loading: () => const PikachuLoader(),
                error: (error, _) => EmptyState(
                  icon: Icons.error_outline,
                  title: 'Gagal memuat pesanan',
                  // The message itself, not just that something went wrong:
                  // "gagal memuat" alone is unactionable for the person
                  // seeing it and undiagnosable for the person fixing it.
                  description: _describe(error),
                  action: OutlinedButton(
                    onPressed: _reload,
                    child: const Text('Coba lagi'),
                  ),
                ),
              ),
      ),
    );
  }

  void _reload() => ref.invalidate(ordersProvider);

  Widget _buildBody(List<OrderModel> orders) {
    if (orders.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Belum ada pesanan',
        description: 'Pesananmu muncul di sini setelah checkout berhasil.',
      );
    }

    final searched = orders.where(_matches).toList();
    // Counted against the search, like web: the numbers describe what each
    // tab would show now, not everything that exists.
    final counts = {
      for (final tab in OrderTab.values)
        tab: tab == OrderTab.all
            ? searched.length
            : searched.where((order) => order.tab == tab).length,
    };
    final visible = _tab == OrderTab.all
        ? searched
        : searched.where((order) => order.tab == _tab).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _query = value.trim()),
            decoration: InputDecoration(
              hintText: 'Cari kartu, penjual, atau nomor resi',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _TabStrip(
          active: _tab,
          counts: counts,
          onSelect: (tab) => setState(() => _tab = tab),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: visible.isEmpty
                // Still a scroll view, so pull-to-refresh works from the
                // empty state too.
                ? ListView(
                    children: [
                      const SizedBox(height: 48),
                      EmptyState(
                        icon: Icons.filter_list_off,
                        title: _query.isEmpty
                            ? 'Tidak ada pesanan di tab ini'
                            : 'Tidak ada pesanan yang cocok',
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _OrderCard(
                      order: visible[i],
                      onTap: () =>
                          context.push(Routes.orderDetail(visible[i].slug)),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// The seven filter tabs with their counts, and web's urgency dot on the two
/// that cost the buyer something if ignored.
class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.active,
    required this.counts,
    required this.onSelect,
  });

  final OrderTab active;
  final Map<OrderTab, int> counts;
  final ValueChanged<OrderTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: OrderTab.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final tab = OrderTab.values[i];
          final selected = tab == active;
          final count = counts[tab] ?? 0;

          return GestureDetector(
            onTap: () => onSelect(tab),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).cardColor
                    : colors.secondary,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: selected ? context.borderColor : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tab.isUrgent && count > 0) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tab == OrderTab.dispute
                            ? colors.error
                            : context.appSemantic.condMp,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    tab.label,
                    style: selected
                        ? AppTypography.captionSemibold(colors.onSurface)
                        : AppTypography.caption(context.mutedForeground),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      '($count)',
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

Color orderStatusColor(BuildContext context, OrderStatus status) {
  final semantic = context.appSemantic;
  final colors = context.appColors;
  switch (status) {
    case OrderStatus.awaitingShipment:
      return semantic.condMp;
    case OrderStatus.shipped:
      return semantic.bid;
    case OrderStatus.received:
      return colors.primary;
    case OrderStatus.completed:
      return semantic.success;
    case OrderStatus.issue:
      return colors.error;
    case OrderStatus.cancelled:
      return context.mutedForeground;
  }
}

/// Ports `features/orders/components/card/order-card.tsx`.
class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});

  final OrderModel order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final first = order.items.isEmpty ? null : order.items.first;
    // An unpaid order is still `awaiting_shipment` server-side, but telling
    // the buyer it's waiting on the seller would be the wrong way round.
    final unpaid =
        order.isUnpaid && order.status == OrderStatus.awaitingShipment;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
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
            // Header — who it's from, and where it stands.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.storefront_outlined,
                    size: 15,
                    color: context.mutedForeground,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      order.storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.captionSemibold(colors.onSurface),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(
                    label: unpaid ? 'Belum Dibayar' : order.status.label,
                    color: unpaid
                        ? context.appSemantic.condMp
                        : orderStatusColor(context, order.status),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Thumbnail(order: order),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.orderNumber,
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          first == null
                              ? '${order.items.length} kartu'
                              : first.card.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmSemibold(colors.onSurface),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (first != null) ...[
                              ConditionBadge(
                                condition: first.condition,
                                dense: true,
                              ),
                              Text(
                                '×${first.matchedQuantity}',
                                style: AppTypography.caption(
                                  context.mutedForeground,
                                ),
                              ),
                            ],
                            Text(
                              formatRelativeId(
                                order.createdAt,
                                now: DateTime.now(),
                              ),
                              style: AppTypography.caption(
                                context.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                        if (order.trackingNumber != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${order.courier ?? "Kurir"} · '
                            '${order.trackingNumber}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption(
                              context.mutedForeground,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Footer — total on the left, the way in on the right.
            Container(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
              decoration: BoxDecoration(
                color: colors.secondary.withValues(alpha: 0.4),
                border: Border(top: BorderSide(color: context.borderColor)),
              ),
              child: Row(
                children: [
                  Text(
                    'Total ',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                  Text(
                    formatRupiah(order.total),
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onTap,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: const Text('Lihat detail'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The artwork web leads each card with, carrying a count when the order
/// holds more than one line.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final items = order.items;
    if (items.isEmpty) return const SizedBox(width: 56, height: 72);

    return SizedBox(
      width: 56,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CardArt(
              imageUrl: items.first.card.imageUrl,
              borderRadius: AppRadius.sm,
            ),
          ),
          if (items.length > 1)
            Positioned(
              right: -6,
              bottom: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.appColors.onSurface,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(color: Theme.of(context).cardColor),
                ),
                child: Text(
                  '+${items.length - 1}',
                  style: AppTypography.badge(context.appColors.surface),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
