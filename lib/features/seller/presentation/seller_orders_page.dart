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
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../orders/repository/models/order_model.dart';
import '../../orders/repository/models/pending_checkout.dart';
import '../../orders/repository/models/seller_order.dart';
import '../../orders/usecase/orders_notifier.dart';

/// Ports `app/seller/orders` — the seller's side of Pesanan.
///
/// Not the buyer's list with the names swapped, which is what this used to
/// be: the buckets are different (a seller cares about "perlu dikirim", a
/// buyer about "belum bayar"), and one whole tab — unpaid checkouts — isn't
/// in `orders` at all, because the order doesn't exist until the money
/// lands.
class SellerOrdersPage extends ConsumerStatefulWidget {
  const SellerOrdersPage({super.key});

  @override
  ConsumerState<SellerOrdersPage> createState() => _SellerOrdersPageState();
}

class _SellerOrdersPageState extends ConsumerState<SellerOrdersPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    ref.invalidate(sellerOrdersProvider);
    ref.invalidate(sellerPendingCheckoutsProvider);
  }

  /// Order number, card, buyer and tracking number — what web's box covers.
  bool _matches(OrderModel order, String needle) {
    if (needle.isEmpty) return true;
    if (order.orderNumber.toLowerCase().contains(needle)) return true;
    if (order.storeName.toLowerCase().contains(needle)) return true;
    if ((order.trackingNumber ?? '').toLowerCase().contains(needle)) {
      return true;
    }
    return order.items.any(
      (item) => item.card.name.toLowerCase().contains(needle),
    );
  }

  bool _matchesPending(PendingCheckout checkout, String needle) {
    if (needle.isEmpty) return true;
    if (checkout.reference.toLowerCase().contains(needle)) return true;
    if ((checkout.buyerUsername ?? '').toLowerCase().contains(needle)) {
      return true;
    }
    return checkout.items.any(
      (item) => item.cardName.toLowerCase().contains(needle),
    );
  }

  String _describe(Object error) {
    final text = error is PostgrestException
        ? '${error.message}${error.code == null ? '' : ' (${error.code})'}'
        : error.toString();
    return text.length > 240 ? '${text.substring(0, 240)}...' : text;
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authProvider).valueOrNull != null;
    final async = ref.watch(sellerOrdersProvider);
    final pendingAsync = ref.watch(sellerPendingCheckoutsProvider);
    final tab = ref.watch(sellerOrderTabProvider);

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
                loading: () => const PikachuLoader(),
                error: (error, _) => EmptyState(
                  icon: Icons.error_outline,
                  title: 'Gagal memuat pesanan',
                  description: _describe(error),
                  action: OutlinedButton(
                    onPressed: _reload,
                    child: const Text('Coba lagi'),
                  ),
                ),
                data: (orders) => _body(
                  tab,
                  orders,
                  // A failure here shouldn't take the whole page down: unpaid
                  // checkouts are one tab, and the rest still works without
                  // them.
                  pendingAsync.valueOrNull ?? const [],
                ),
              ),
      ),
    );
  }

  Widget _body(
    SellerOrderTab tab,
    List<OrderModel> orders,
    List<PendingCheckout> pending,
  ) {
    final colors = context.appColors;
    final needle = ref.watch(sellerOrderQueryProvider).trim().toLowerCase();
    final courier = ref.watch(sellerOrderCourierProvider);
    final sort = ref.watch(sellerOrderSortProvider);

    final buckets = {for (final o in orders) o.slug: bucketSellerOrder(o)};

    var searched = orders.where((o) => _matches(o, needle)).toList();
    if (courier != null) {
      searched = searched.where((o) => o.courier == courier).toList();
    }
    final searchedPending = pending
        .where((c) => _matchesPending(c, needle))
        .toList();

    // Counted after the search, like web: each number describes what the tab
    // would show right now.
    final counts = {
      for (final t in SellerOrderTab.values)
        t: t == SellerOrderTab.awaitingPayment
            ? searchedPending.length
            : searched
                  .where((o) => tabMatchesSellerOrder(t, buckets[o.slug]))
                  .length,
    };

    final visible = sort.apply(
      searched
          .where((o) => tabMatchesSellerOrder(tab, buckets[o.slug]))
          .toList(),
    );
    final couriers =
        orders.map((o) => o.courier).whereType<String>().toSet().toList()
          ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabStrip(
          active: tab,
          counts: counts,
          onSelect: (next) =>
              ref.read(sellerOrderTabProvider.notifier).state = next,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tab.headerTitle, style: AppTypography.h1(colors.onSurface)),
              const SizedBox(height: 4),
              Text(
                tab.headerSubtitle,
                style: AppTypography.bodySm(context.mutedForeground),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            style: AppTypography.bodySm(colors.onSurface),
            onChanged: (v) =>
                ref.read(sellerOrderQueryProvider.notifier).state = v,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              hintText: 'Cari order ID, kartu, pembeli, atau no. resi',
              hintStyle: AppTypography.bodySm(context.mutedForeground),
              prefixIcon: const Icon(Icons.search, size: 18),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 0,
              ),
              suffixIcon: needle.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        _search.clear();
                        ref.read(sellerOrderQueryProvider.notifier).state = '';
                      },
                    ),
            ),
          ),
        ),
        _FilterBar(
          sort: sort,
          courier: courier,
          couriers: couriers,
          // The courier filter is meaningless where nothing has shipped yet.
          showCourier: tab != SellerOrderTab.awaitingPayment,
          onSort: (v) => ref.read(sellerOrderSortProvider.notifier).state = v,
          onCourier: (v) =>
              ref.read(sellerOrderCourierProvider.notifier).state = v,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: tab == SellerOrderTab.awaitingPayment
                ? _pendingList(searchedPending, hasAny: pending.isNotEmpty)
                : _orderList(visible, tab: tab, hasAny: orders.isNotEmpty),
          ),
        ),
      ],
    );
  }

  Widget _orderList(
    List<OrderModel> orders, {
    required SellerOrderTab tab,
    required bool hasAny,
  }) {
    if (orders.isEmpty) return _empty(tab, hasAny: hasAny);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => SellerOrderCard(
        order: orders[i],
        // The seller's detail, not the buyer's. Both render the same row —
        // `orders_select_own` covers either side — but a seller opening the
        // buyer view saw what they had "paid" for their own listing.
        onTap: () => context.push(Routes.sellerOrderDetail(orders[i].slug)),
      ),
    );
  }

  Widget _pendingList(List<PendingCheckout> checkouts, {required bool hasAny}) {
    if (checkouts.isEmpty) {
      return _empty(SellerOrderTab.awaitingPayment, hasAny: hasAny);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      itemCount: checkouts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _PendingCard(checkout: checkouts[i]),
    );
  }

  /// Web draws two different empty states: nothing at all, versus nothing in
  /// this tab.
  Widget _empty(SellerOrderTab tab, {required bool hasAny}) {
    return ListView(
      children: [
        const SizedBox(height: 40),
        EmptyState(
          icon: Icons.inventory_2_outlined,
          title: hasAny ? tab.emptyHeadline : 'Belum ada pesanan',
          description: hasAny
              ? (tab.emptySub ?? 'Coba ganti filter atau tab.')
              : 'Pesanan dari pembeli akan muncul di sini.',
        ),
      ],
    );
  }
}

/// The nine tabs with their counts, and web's dot on the ones waiting on the
/// seller.
class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.active,
    required this.counts,
    required this.onSelect,
  });

  final SellerOrderTab active;
  final Map<SellerOrderTab, int> counts;
  final ValueChanged<SellerOrderTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: SellerOrderTab.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final tab = SellerOrderTab.values[i];
          final selected = tab == active;
          final count = counts[tab] ?? 0;
          final foreground = selected
              ? colors.primary
              : context.mutedForeground;

          return GestureDetector(
            onTap: () => onSelect(tab),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? colors.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? colors.primary : context.borderColor,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tab.isUrgent && count > 0) ...[
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tab == SellerOrderTab.disputed
                            ? colors.error
                            : context.appSemantic.condMp,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(tab.label, style: AppTypography.badge(foreground)),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      '$count',
                      style: AppTypography.badge(context.mutedForeground),
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

/// Ports web's filter row: the courier picker and the sort selector.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.sort,
    required this.courier,
    required this.couriers,
    required this.showCourier,
    required this.onSort,
    required this.onCourier,
  });

  final SellerOrderSort sort;
  final String? courier;
  final List<String> couriers;
  final bool showCourier;
  final ValueChanged<SellerOrderSort> onSort;
  final ValueChanged<String?> onCourier;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          if (showCourier && couriers.isNotEmpty) ...[
            Flexible(
              child: _Dropdown<String?>(
                icon: Icons.local_shipping_outlined,
                value: courier,
                label: courier == null
                    ? 'Semua kurir'
                    : courierDisplayName(courier!),
                items: [
                  const PopupMenuItem<String?>(
                    value: null,
                    child: Text('Semua kurir'),
                  ),
                  for (final c in couriers)
                    PopupMenuItem<String?>(
                      value: c,
                      child: Text(courierDisplayName(c)),
                    ),
                ],
                onSelected: onCourier,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: _Dropdown<SellerOrderSort>(
              icon: Icons.swap_vert,
              value: sort,
              label: sort.label,
              items: [
                for (final option in SellerOrderSort.values)
                  PopupMenuItem(value: option, child: Text(option.label)),
              ],
              onSelected: onSort,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.icon,
    required this.value,
    required this.label,
    required this.items,
    required this.onSelected,
  });

  final IconData icon;
  final T value;
  final String label;
  final List<PopupMenuEntry<T>> items;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (context) => items,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: context.mutedForeground),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption(colors.onSurface),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: 15,
              color: context.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

/// Biteship's courier codes are what the column holds; web maps them to the
/// names people recognise before printing them.
String courierDisplayName(String code) {
  const names = {
    'jne': 'JNE',
    'jnt': 'J&T',
    'sicepat': 'SiCepat',
    'anteraja': 'AnterAja',
    'ninja': 'Ninja Xpress',
    'tiki': 'TIKI',
    'pos': 'POS Indonesia',
    'wahana': 'Wahana',
    'lion': 'Lion Parcel',
    'idexpress': 'ID Express',
    'rpx': 'RPX',
    'sap': 'SAP Express',
    'jet': 'JET Express',
    'first': 'First Logistics',
    'gojek': 'GoSend',
    'grab': 'GrabExpress',
    'paxel': 'Paxel',
    'lalamove': 'Lalamove',
    'borzo': 'Borzo',
  };
  return names[code.toLowerCase()] ?? code.toUpperCase();
}

/// Ports `order-row.tsx`'s `OrderCard` — the layout web itself falls back to
/// below `md`.
class SellerOrderCard extends StatelessWidget {
  const SellerOrderCard({super.key, required this.order, required this.onTap});

  final OrderModel order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final first = order.items.isEmpty ? null : order.items.first;
    final extra = order.items.length - 1;
    final status = _status(context, order);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 44,
                  child: CardArt(
                    imageUrl: first?.card.imageUrl,
                    borderRadius: AppRadius.sm,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              order.orderNumber.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.captionSemibold(
                                colors.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _StatusDot(label: status.$1, color: status.$2),
                        ],
                      ),
                      Text(
                        '@${order.storeName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        first?.card.name ?? 'Pesanan',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmSemibold(colors.onSurface),
                      ),
                      const SizedBox(height: 2),
                      if (extra > 0)
                        Text(
                          '+ $extra item lain · Total ×${order.totalQuantity}',
                          style: AppTypography.caption(context.mutedForeground),
                        )
                      else if (first != null)
                        Text(
                          '${first.card.expansionCode.toUpperCase()} · '
                          '#${first.card.collectorNumber} · '
                          '×${first.matchedQuantity}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      const SizedBox(height: 3),
                      Text(
                        formatRupiah(order.total),
                        style: AppTypography.bodySmSemibold(colors.onSurface),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            ..._footer(context),
          ],
        ),
      ),
    );
  }

  /// Web's footer strip: whichever one thing the seller has to do next.
  List<Widget> _footer(BuildContext context) {
    final colors = context.appColors;
    final bookError = order.biteshipBookError;
    final hasBookError =
        bookError != null &&
        order.biteshipOrderId == null &&
        order.originCollectionMethod != null &&
        !bookError.startsWith('seller_cancel');
    final needsDispatch =
        order.shipmentStatus == 'awaiting_shipment' &&
        order.biteshipOrderId == null &&
        order.originCollectionMethod == null;
    final awaitingPickup = order.shipmentStatus == 'awaiting_pickup';
    final shipped = order.shipmentStatus == 'shipped';

    Widget? content;
    if (hasBookError) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 14, color: colors.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Booking kurir gagal. Buka pesanan untuk memesan ulang.',
              style: AppTypography.caption(colors.error),
            ),
          ),
        ],
      );
    } else if (needsDispatch) {
      content = Row(
        children: [
          Icon(Icons.local_shipping_outlined, size: 14, color: colors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Pilih cara kirim',
              style: AppTypography.captionSemibold(colors.primary),
            ),
          ),
          Icon(Icons.chevron_right, size: 15, color: colors.primary),
        ],
      );
    } else if (awaitingPickup) {
      content = Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 14,
            color: context.mutedForeground,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Menunggu kurir menjemput paket',
              style: AppTypography.caption(context.mutedForeground),
            ),
          ),
        ],
      );
    } else if (shipped && order.trackingNumber != null) {
      content = Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 14,
            color: context.appSemantic.bid,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: AppTypography.caption(context.mutedForeground),
                children: [
                  const TextSpan(text: 'Resi '),
                  TextSpan(
                    text: order.trackingNumber,
                    style: AppTypography.captionSemibold(colors.onSurface),
                  ),
                  if (order.courier != null)
                    TextSpan(text: ' · ${courierDisplayName(order.courier!)}'),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    if (content == null) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Divider(height: 1, color: context.borderColor),
      ),
      content,
    ];
  }

  /// Ports the card's status pill. The order of these tests is the point: a
  /// dispute or a pending cancellation outranks whatever the courier says,
  /// because that's the thing the seller has to answer.
  (String, Color) _status(BuildContext context, OrderModel order) {
    final colors = context.appColors;
    final semantic = context.appSemantic;
    final latest = latestBiteshipStatus(order.statusHistory);

    if (isDisputeOpen(order.disputeStatus)) return ('Dikomplain', colors.error);
    if (order.transactionStatus == 'awaiting_payment') {
      return ('Menunggu pembayaran', semantic.condMp);
    }
    if (order.cancelStatus == 'pending_seller') {
      return ('Permintaan batal', semantic.condMp);
    }
    if (latest == 'returned') {
      return order.itemStatusRaw == 'cancelled' ||
              order.shipmentStatus == 'cancelled'
          ? ('Selesai · Dikembalikan', semantic.success)
          : ('Dikembalikan', semantic.condMp);
    }
    if (latest == 'disposed') return ('Dihancurkan', colors.error);

    return switch (order.shipmentStatus) {
      'awaiting_shipment' => ('Perlu dikirim', semantic.condMp),
      'awaiting_pickup' => ('Menunggu kurir', semantic.condMp),
      'shipped' => ('Dikirim', semantic.bid),
      'received' => ('Tiba di pembeli', colors.primary),
      'completed' => ('Selesai', semantic.success),
      'cancelled' => ('Dibatalkan', context.mutedForeground),
      'issue' => ('Bermasalah', colors.error),
      _ => ('Menunggu', context.mutedForeground),
    };
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 5),
          Text(label, style: AppTypography.badge(color)),
        ],
      ),
    );
  }
}

/// An unpaid checkout. Deliberately not tappable: there's no order behind it
/// to open, and nothing for the seller to do but wait out the clock.
class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.checkout});

  final PendingCheckout checkout;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final first = checkout.items.first;
    final extra = checkout.items.length - 1;
    final remaining = checkout.remaining;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 44,
                child: CardArt(
                  imageUrl: first.imageUrl,
                  borderRadius: AppRadius.sm,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            checkout.reference,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.captionSemibold(
                              colors.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _StatusDot(
                          label: 'Menunggu pembayaran',
                          color: context.appSemantic.condMp,
                        ),
                      ],
                    ),
                    if (checkout.buyerUsername != null)
                      Text(
                        '@${checkout.buyerUsername}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      first.cardName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmSemibold(colors.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      extra > 0
                          ? '+ $extra item lain · Total ×'
                                '${checkout.totalQuantity}'
                          : '${first.expansionCode.toUpperCase()} · '
                                '#${first.collectorNumber} · ×${first.quantity}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      formatRupiah(checkout.total),
                      style: AppTypography.bodySmSemibold(colors.onSurface),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: context.borderColor),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.schedule, size: 14, color: context.mutedForeground),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  remaining == null
                      ? 'Menunggu pembayaran pembeli'
                      : 'Stok ditahan ${_countdown(remaining)} lagi',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ),
              if (!checkout.hasInvoice)
                Text(
                  'Belum ada invoice',
                  style: AppTypography.badge(context.appSemantic.condMp),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _countdown(Duration d) {
    if (d.inHours >= 1) return '${d.inHours} jam';
    if (d.inMinutes >= 1) return '${d.inMinutes} menit';
    return 'kurang dari 1 menit';
  }
}
