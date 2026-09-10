import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/widgets/app_search_field.dart';
import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/condition_badge.dart';
import '../../../shared/widgets/inline_pill.dart';
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
import '../utils/order_status_display.dart';
import 'widgets/order_thumbnail.dart';

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
                icon: LucideIcons.receipt,
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
                  icon: LucideIcons.circleAlert,
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

    // No early return for "nothing at all": web always renders the search box
    // and the tab strip, and puts the empty state inside the tab body. Cutting
    // straight to a bare message hid the tabs, so a buyer with no orders
    // couldn't see that the shelves existed — and the Semua tab's own copy
    // ("Belum ada pesanan") already covers this case.

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
          child: AppSearchField(
            hintText: 'Cari kartu, penjual, atau nomor resi',
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value.trim()),
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
                      // Per-tab copy and icon, as web's `ORDER_EMPTY_COPY`
                      // and `TAB_ICON` do — a search that matched nothing
                      // keeps its own message, since that's about the query
                      // rather than the shelf.
                      EmptyState(
                        icon: _query.isEmpty
                            ? _tabIcon(_tab)
                            : LucideIcons.searchX,
                        title: _query.isEmpty
                            ? _tab.emptyHeadline
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
/// Ports `TAB_ICON` — each shelf gets its own mark, so an empty tab still
/// says which shelf it is.
IconData _tabIcon(OrderTab tab) => switch (tab) {
  OrderTab.all => LucideIcons.listChecks,
  OrderTab.unpaid => LucideIcons.wallet,
  OrderTab.processing => LucideIcons.package,
  OrderTab.shipped => LucideIcons.truck,
  OrderTab.completed => LucideIcons.circleCheck,
  OrderTab.cancelled => LucideIcons.circleX,
  OrderTab.dispute => LucideIcons.shieldAlert,
};

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

/// Ports `features/orders/components/card/order-card.tsx` — four bands: who
/// it's from and where it stands, what was bought, the one fact that matters
/// at this stage, then the total and the actions.
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
    final first = order.items.isEmpty ? null : order.items.first;
    final extra = order.items.length - 1;
    final display = describeOrderForBuyer(order);

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
            _CardHeader(order: order, display: display),
            _CardBody(order: order, first: first, extraCount: extra),
            _InfoRow(order: order, display: display),
            _CardFooter(
              order: order,
              onTap: onTap,
              onConfirmReceipt: onConfirmReceipt,
            ),
          ],
        ),
      ),
    );
  }
}

/// Band 1 — `order-card-header.tsx`: the seller, and the order's standing.
class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.order, required this.display});

  final OrderModel order;
  final OrderStatusDisplay display;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
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
                  style: AppTypography.captionSemibold(colors.onSurface),
                ),
                // Only when the store picked a name of its own — web hides
                // it when the two are the same.
                if (order.sellerSecondaryName != null)
                  Text(
                    order.sellerSecondaryName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          StatusPill.tone(label: display.label, tone: display.tone),
        ],
      ),
    );
  }
}

/// Band 2 — the thumbnail, the order number, and what was bought.
class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.order,
    required this.first,
    required this.extraCount,
  });

  final OrderModel order;
  final OrderItemModel? first;
  final int extraCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final second = order.items.length > 1 ? order.items[1] : null;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OrderThumbnailStack(
            imageUrl: first?.card.imageUrl,
            secondImageUrl: second?.card.imageUrl,
            extraCount: extraCount,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Web draws this in the foreground, semibold: it's the
                // handle you quote when asking about the order, not a
                // caption. Mobile had it muted.
                Text(
                  order.orderNumber.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.captionSemibold(colors.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  first?.card.name ?? 'Pesanan',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
                const SizedBox(height: 4),
                if (extraCount >= 1)
                  Text(
                    '+ $extraCount item lain · ×${order.totalQuantity}',
                    style: AppTypography.caption(context.mutedForeground),
                  )
                else if (first != null)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (first!.card.expansionCode.isNotEmpty)
                        ExpansionChip(code: first!.card.expansionCode),
                      Text(
                        '#${first!.card.collectorNumber}',
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                      ConditionBadge(condition: first!.condition, dense: true),
                      Text(
                        '×${first!.matchedQuantity}',
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Band 3 — web's `InfoRow`: one line about where the order actually is.
///
/// Mobile only ever drew the tracking number, so an unpaid order showed no
/// deadline, a preparing one showed nothing at all, and a finished one said
/// nothing about when it finished.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.order, required this.display});

  final OrderModel order;
  final OrderStatusDisplay display;

  @override
  Widget build(BuildContext context) {
    final pills = <Widget>[];
    Widget? trackingLine;

    final dispatched = isShipmentDispatched(order.shipmentStatus);
    final disputed = order.openDispute != null;
    final unpaid = order.isUnpaid;
    final processing =
        !disputed &&
        !unpaid &&
        order.effectiveStatus == 'awaiting_shipment' &&
        !dispatched;
    final shipped =
        !disputed && (dispatched || order.effectiveStatus == 'shipped');

    if (unpaid && order.paymentDeadline != null) {
      pills.add(
        InlinePill(
          tone: InlinePillTone.warning,
          icon: LucideIcons.clock,
          label: 'Bayar sebelum ${formatDeadlineId(order.paymentDeadline!)}',
        ),
      );
    } else if (processing) {
      final status = order.shipmentStatus;
      final isIssue = status == 'issue';
      final isCancelled = status == 'cancelled';
      pills.add(
        InlinePill(
          tone: isIssue
              ? InlinePillTone.danger
              : isCancelled
              ? InlinePillTone.neutral
              : InlinePillTone.progress,
          icon: isIssue
              ? LucideIcons.triangleAlert
              : isCancelled
              ? LucideIcons.ban
              : LucideIcons.package,
          label: status == null
              ? 'Menunggu pengiriman'
              : shipmentStatusLabel(status),
        ),
      );
      if (order.trackingNumber == null &&
          !isIssue &&
          !isCancelled &&
          order.shipmentDeadline != null) {
        pills.add(
          InlinePill(
            tone: InlinePillTone.warning,
            icon: LucideIcons.truck,
            label:
                'Dikirim sebelum ${formatDeadlineId(order.shipmentDeadline!)}',
          ),
        );
      }
    } else if (shipped) {
      final delivered = order.shipmentStatus == 'received';
      pills.add(
        InlinePill(
          tone: delivered ? InlinePillTone.success : InlinePillTone.info,
          icon: delivered ? LucideIcons.circleCheck : LucideIcons.truck,
          label: shipmentStatusLabel(order.shipmentStatus),
        ),
      );
    } else if (display.key == 'completed' || display.key == 'resolved') {
      final at = order.deliveredAt;
      pills.add(
        InlinePill(
          tone: InlinePillTone.success,
          icon: LucideIcons.circleCheck,
          label: at == null ? 'Selesai' : 'Selesai ${formatShortDateId(at)}',
        ),
      );
    } else if (disputed) {
      pills.add(
        const InlinePill(
          tone: InlinePillTone.danger,
          icon: LucideIcons.ban,
          label: 'Komplain dibuka',
        ),
      );
    }

    if (order.trackingNumber != null) {
      trackingLine = Row(
        children: [
          Text('Resi', style: AppTypography.caption(context.mutedForeground)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              order.trackingNumber!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.captionSemibold(context.appColors.onSurface),
            ),
          ),
          if (order.courier != null)
            Text(
              '· ${order.courier!.toUpperCase()}',
              style: AppTypography.caption(context.mutedForeground),
            ),
        ],
      );
    }

    if (pills.isEmpty && trackingLine == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        // `bg-muted/20` — web fills this band rather than leaving it on the
        // card's own surface with only a rule above it.
        color: context.appColors.secondary.withValues(alpha: 0.2),
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pills.isNotEmpty)
            Wrap(spacing: 6, runSpacing: 6, children: pills),
          if (trackingLine != null) ...[
            if (pills.isNotEmpty) const SizedBox(height: 6),
            trackingLine,
          ],
        ],
      ),
    );
  }
}

/// Band 4 — the total, and the actions this order actually offers.
class _CardFooter extends StatelessWidget {
  const _CardFooter({
    required this.order,
    required this.onTap,
    required this.onConfirmReceipt,
  });

  final OrderModel order;
  final VoidCallback onTap;
  final VoidCallback? onConfirmReceipt;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final first = order.items.isEmpty ? null : order.items.first;
    final states = BuyerOrderStates(order);
    final display = describeOrderForBuyer(order);
    final actions = <Widget>[];

    if (order.cancelStatus == 'pending_seller') {
      actions.add(
        const InlinePill(
          tone: InlinePillTone.warning,
          icon: LucideIcons.clock,
          label: 'Menunggu konfirmasi seller',
        ),
      );
    }

    // Gated on `isShipped` — the settlement still reading `shipped` — for the
    // same reason the detail's block is: `canConfirmReceipt` keys off a
    // delivery timestamp that never clears, so without this a finished order
    // kept offering to confirm itself.
    if (states.isShipped &&
        order.canConfirmReceipt &&
        onConfirmReceipt != null) {
      actions.add(
        ElevatedButton(
          onPressed: onConfirmReceipt,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.appSemantic.success,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: const Text(
            'Konfirmasi Diterima',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    // Web only offers a complaint once the package is on its way and there
    // isn't already one open.
    if (states.showReport) {
      actions.add(
        OutlinedButton.icon(
          onPressed: () => context.push(Routes.orderOpenDispute(order.slug)),
          icon: const Icon(LucideIcons.triangleAlert, size: 14),
          label: const Text(
            'Ajukan Komplain',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.appSemantic.condMp,
            side: BorderSide(
              color: context.appSemantic.condMp.withValues(alpha: 0.4),
            ),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
        ),
      );
    }

    if (order.openDispute != null) {
      actions.add(
        OutlinedButton.icon(
          onPressed: () => context.push(Routes.orderDispute(order.slug)),
          icon: const Icon(LucideIcons.triangleAlert, size: 14),
          label: const Text(
            'Lihat Komplain',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // Web's destructive variant — tinted, not merely outlined:
          // `border border-destructive/20 bg-destructive/10`.
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.error,
            backgroundColor: colors.error.withValues(alpha: 0.10),
            side: BorderSide(color: colors.error.withValues(alpha: 0.20)),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
        ),
      );
    }

    // `(isCompleted || isCancelled) && Cari Serupa` — web's way back into
    // the catalogue once an order is done or fell through. This was missing
    // entirely, so a settled card offered nothing at all.
    // From the resolved display, not `orders.status`: that row lags, so a
    // finished order was never offered "Cari Serupa".
    const terminal = {
      'completed',
      'resolved',
      'cancelled',
      'expired',
      'rejected',
      'refunded',
    };
    final settled = terminal.contains(display.key);
    if (settled && first != null && first.card.name.trim().isNotEmpty) {
      actions.add(
        OutlinedButton.icon(
          onPressed: () =>
              context.push(Routes.searchResults(first.card.name.trim())),
          icon: const Icon(LucideIcons.search, size: 14),
          label: const Text(
            'Cari Serupa',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
        ),
      );
    }

    // Web only offers this while the order is being processed — everywhere
    // else the card itself is the way in, and a permanent button crowded the
    // row enough to squeeze the actions that matter.
    if (states.preparing && !states.disputeOpen) {
      actions.add(
        OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: const Text(
            'Lihat Detail',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return Container(
      // `p-3` on web, all round.
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.secondary.withValues(alpha: 0.2),
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Total Pesanan:',
                style: AppTypography.caption(context.mutedForeground),
              ),
              const SizedBox(width: 6),
              Text(
                formatRupiah(order.total),
                style: AppTypography.bodySemibold(colors.onSurface),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            // Web's mobile footer is `flex w-full` with every button
            // `flex-1`, so the actions share the row edge to edge rather
            // than huddling on the right. Two actions each take half, three
            // each take a third — which is what makes the two cards read
            // the same.
            Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: actions[i]),
                ],
              ],
            ),
          ],
        ],
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
              Icon(LucideIcons.clock, size: 14, color: context.mutedForeground),
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
