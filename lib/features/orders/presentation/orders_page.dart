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
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/seller_avatar.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../cart/presentation/payment_webview_page.dart';
import '../repository/models/order_model.dart';
import '../repository/models/pending_checkout.dart';
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

  bool _confirming = false;

  Future<void> _confirmReceipt(OrderModel order) async {
    final itemId = order.firstItemId;
    if (itemId == null) return;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Konfirmasi Penerimaan?',
      description:
          'Dana akan diteruskan ke penjual. Lakukan hanya setelah kartu '
          'kamu terima dan sesuai.',
      confirmLabel: 'Konfirmasi',
      loadingLabel: 'Mengonfirmasi...',
      onConfirm: () async {
        setState(() => _confirming = true);
        final error = await ref
            .read(ordersRepositoryProvider)
            .confirmReceipt(itemId);
        if (!mounted) return;
        setState(() => _confirming = false);
        _toast(error ?? 'Penerimaan dikonfirmasi');
        if (error == null) _reload();
      },
    );
    return confirmed;
  }

  bool _matchesPending(PendingCheckout checkout) {
    if (_query.isEmpty) return true;
    final needle = _query.toLowerCase();
    if (checkout.externalId.toLowerCase().contains(needle)) return true;
    return checkout.items.any(
      (item) => item.cardName.toLowerCase().contains(needle),
    );
  }

  /// Reopens the hosted invoice so the buyer can finish paying.
  Future<void> _resumePayment(PendingCheckout checkout) async {
    final invoiceUrl = checkout.invoiceUrl;
    if (invoiceUrl == null) {
      _toast('Tagihan belum dibuat untuk pesanan ini.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<PaymentOutcome>(
        builder: (_) => PaymentWebViewPage(invoiceUrl: invoiceUrl),
      ),
    );
    if (!mounted) return;
    // Returning is not proof of payment — the webhook decides — so just
    // re-read both sources.
    ref.invalidate(myPendingCheckoutsProvider);
    _reload();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), persist: false));
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
    // Unpaid checkouts aren't orders yet — the webhook creates those — so
    // they are read separately and shown under Belum Bayar, which is the
    // only place a buyer would look for them.
    final pending =
        ref.watch(myPendingCheckoutsProvider).valueOrNull ?? const [];

    if (orders.isEmpty && pending.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Belum ada pesanan',
        description: 'Pesananmu muncul di sini setelah checkout berhasil.',
      );
    }

    final searched = orders.where(_matches).toList();
    // Counted against the search, like web: the numbers describe what each
    // tab would show now, not everything that exists.
    final searchedPending = pending.where(_matchesPending).toList();
    final counts = {
      for (final tab in OrderTab.values)
        tab: switch (tab) {
          OrderTab.all => searched.length + searchedPending.length,
          OrderTab.unpaid =>
            searched.where((o) => o.tab == tab).length + searchedPending.length,
          _ => searched.where((order) => order.tab == tab).length,
        },
    };
    final visible = _tab == OrderTab.all
        ? searched
        : searched.where((order) => order.tab == _tab).toList();
    // Newest first, above the settled orders — an unpaid checkout is the
    // one thing on this screen with a clock running.
    final visiblePending = _tab == OrderTab.all || _tab == OrderTab.unpaid
        ? searchedPending
        : const <PendingCheckout>[];

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
            child: visible.isEmpty && visiblePending.isEmpty
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
                    itemCount: visiblePending.length + visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      if (i < visiblePending.length) {
                        return _PendingCheckoutCard(
                          checkout: visiblePending[i],
                          onPay: () => _resumePayment(visiblePending[i]),
                        );
                      }
                      final order = visible[i - visiblePending.length];
                      return _OrderCard(
                        order: order,
                        onTap: () =>
                            context.push(Routes.orderDetail(order.slug)),
                        onConfirmReceipt: _confirming
                            ? null
                            : () => _confirmReceipt(order),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

/// The seven filter tabs with their counts, and web's urgency dot on the two
/// that cost the buyer something if ignored.
/// Ports web's order tab strip — a segmented control on a muted track,
/// with the active tab lifted onto the card colour, an urgency dot on the
/// two tabs that cost the buyer something, and the count in parentheses.
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

    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      // Scrolls rather than squeezing: seven labels never fit a phone, and
      // web's `overflow-x-auto` does the same thing.
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: OrderTab.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, i) {
          final tab = OrderTab.values[i];
          final selected = tab == active;
          final count = counts[tab] ?? 0;
          final urgent = tab.isUrgent && count > 0;

          return GestureDetector(
            onTap: () => onSelect(tab),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).cardColor
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (urgent) ...[
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

/// Ports `features/orders/components/card/order-card.tsx` — three bands: the
/// seller strip, the item body, and the total footer.
class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.onTap,
    this.onConfirmReceipt,
  });

  final OrderModel order;
  final VoidCallback onTap;

  /// Null while a confirmation is in flight, which disables the button.
  final VoidCallback? onConfirmReceipt;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final first = order.items.isEmpty ? null : order.items.first;
    final extra = order.items.length - 1;
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
            // Band 1 — who it's from, and where it stands.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.secondary.withValues(alpha: 0.3),
                border: Border(bottom: BorderSide(color: context.borderColor)),
              ),
              child: Row(
                children: [
                  SellerAvatar(
                    name: order.storeName,
                    imageUrl: order.sellerImageUrl,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          order.storeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.captionSemibold(
                            colors.onSurface,
                          ),
                        ),
                        // Only when the store picked a name of its own —
                        // web hides it when the two are the same.
                        if (order.sellerSecondaryName != null)
                          Text(
                            order.sellerSecondaryName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption(
                              context.mutedForeground,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  StatusPill(
                    label: unpaid ? 'Belum Dibayar' : order.status.label,
                    color: unpaid
                        ? context.appSemantic.condMp
                        : orderStatusColor(context, order.status),
                  ),
                ],
              ),
            ),

            // Band 2 — what was bought.
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 56,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CardArt(
                          imageUrl: first?.card.imageUrl,
                          borderRadius: AppRadius.sm,
                        ),
                        // Web's `+N` chip, so a multi-item package doesn't
                        // read as a single card.
                        if (extra >= 1)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: colors.onSurface,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Theme.of(context).cardColor,
                                ),
                              ),
                              child: Text(
                                '+$extra',
                                style: AppTypography.badge(colors.surface),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.orderNumber.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          first?.card.name ?? 'Pesanan',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmSemibold(colors.onSurface),
                        ),
                        const SizedBox(height: 4),
                        if (extra >= 1)
                          Text(
                            '+ $extra item lain · ×${order.totalQuantity}',
                            style: AppTypography.caption(
                              context.mutedForeground,
                            ),
                          )
                        else if (first != null)
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (first.card.expansionCode.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.secondary,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.xs,
                                    ),
                                  ),
                                  child: Text(
                                    first.card.expansionCode.toUpperCase(),
                                    style: AppTypography.badge(
                                      context.mutedForeground,
                                    ),
                                  ),
                                ),
                              Text(
                                '#${first.card.collectorNumber}',
                                style: AppTypography.caption(
                                  context.mutedForeground,
                                ),
                              ),
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
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Web's InfoRow: the one fact that matters at this stage.
            if (order.trackingNumber != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: context.borderColor)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.local_shipping_outlined,
                      size: 14,
                      color: context.mutedForeground,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Resi',
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        order.trackingNumber!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.captionSemibold(colors.onSurface),
                      ),
                    ),
                    if (order.courier != null)
                      Text(
                        order.courier!.toUpperCase(),
                        style: AppTypography.badge(context.mutedForeground),
                      ),
                  ],
                ),
              ),

            // Band 3 — what it cost, and the way in.
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                color: colors.secondary.withValues(alpha: 0.2),
                border: Border(top: BorderSide(color: context.borderColor)),
              ),
              child: Row(
                children: [
                  Text(
                    'Total Pesanan:',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      formatRupiah(order.total),
                      style: AppTypography.bodySmSemibold(colors.onSurface),
                    ),
                  ),
                  if (order.canConfirmReceipt && onConfirmReceipt != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ElevatedButton(
                        onPressed: onConfirmReceipt,
                        style: ElevatedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text('Konfirmasi Diterima'),
                      ),
                    ),
                  TextButton(
                    onPressed: onTap,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Lihat Detail'),
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

/// An unpaid checkout, shown above the settled orders under Belum Bayar.
///
/// Visibly not an order: it has no order number, no shipment and no detail
/// page to open — just a countdown and the way back to paying. Dressing it
/// as an order would promise a page that doesn't exist yet.
class _PendingCheckoutCard extends StatelessWidget {
  const _PendingCheckoutCard({required this.checkout, required this.onPay});

  final PendingCheckout checkout;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final first = checkout.items.isEmpty ? null : checkout.items.first;
    final extra = checkout.items.length - 1;
    final remaining = checkout.remaining;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        // Tinted edge so it reads as the one row that still needs the buyer.
        border: Border.all(
          color: context.appSemantic.condMp.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  first?.cardName ?? 'Pesanan',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
              ),
              const SizedBox(width: 6),
              StatusPill(
                label: 'Belum Dibayar',
                color: context.appSemantic.condMp,
              ),
            ],
          ),
          if (extra > 0)
            Text(
              '+ $extra item lain',
              style: AppTypography.caption(context.mutedForeground),
            ),
          const SizedBox(height: 4),
          Text(
            formatRupiah(checkout.total),
            style: AppTypography.bodySemibold(colors.onSurface),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.schedule, size: 14, color: context.mutedForeground),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  remaining == null
                      ? 'Selesaikan pembayaran'
                      : 'Bayar dalam ${_countdown(remaining)}',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ),
              TextButton(onPressed: onPay, child: const Text('Bayar sekarang')),
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
