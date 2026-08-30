import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
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
import '../repository/models/order_model.dart';
import '../usecase/orders_notifier.dart';
import 'orders_page.dart' show orderStatusColor;

/// Ports `features/orders/components/detail/order-detail.tsx`.
///
/// Web lays this out as a main column plus a right rail; a phone has one
/// column, so the rail's cards (Pembayaran, Riwayat) fall to the bottom in
/// the order a buyer would reach for them.
class OrderDetailPage extends ConsumerStatefulWidget {
  const OrderDetailPage({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends ConsumerState<OrderDetailPage> {
  bool _busy = false;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), persist: false));
  }

  Future<void> _confirmReceipt(OrderModel order) {
    final itemId = order.firstItemId;
    if (itemId == null) return Future.value();

    return showConfirmDialog(
      context,
      title: 'Konfirmasi Penerimaan?',
      description:
          'Dana akan diteruskan ke penjual. Lakukan hanya setelah kartu '
          'kamu terima dan sesuai.',
      confirmLabel: 'Konfirmasi',
      loadingLabel: 'Mengonfirmasi...',
      onConfirm: () async {
        setState(() => _busy = true);
        final error = await ref
            .read(ordersRepositoryProvider)
            .confirmReceipt(itemId);
        if (!mounted) return;
        setState(() => _busy = false);
        _toast(error ?? 'Penerimaan dikonfirmasi');
        if (error == null) ref.invalidate(orderDetailProvider(widget.slug));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final async = ref.watch(orderDetailProvider(widget.slug));
    final disputeAsync = ref.watch(orderDisputeProvider(widget.slug));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: async.when(
          loading: () => const PikachuLoader(),
          error: (_, __) => const Center(child: Text('Gagal memuat pesanan')),
          data: (order) {
            if (order == null) {
              return const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Pesanan tidak ditemukan',
              );
            }

            final unpaid =
                order.isUnpaid && order.status == OrderStatus.awaitingShipment;

            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(orderDetailProvider(widget.slug));
                await ref.read(orderDetailProvider(widget.slug).future);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    'Detail pesanan',
                    style: AppTypography.h1(colors.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          order.orderNumber.toUpperCase(),
                          style: AppTypography.bodySm(context.mutedForeground),
                        ),
                      ),
                      StatusPill(
                        label: unpaid ? 'Belum Dibayar' : order.status.label,
                        color: unpaid
                            ? context.appSemantic.condMp
                            : orderStatusColor(context, order.status),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  _SellerCard(order: order),
                  const SizedBox(height: 12),

                  // Web shows this while the seller is preparing, in place
                  // of tracking that doesn't exist yet.
                  if (order.status == OrderStatus.awaitingShipment && !unpaid)
                    _Section(
                      icon: Icons.inventory_2_outlined,
                      title: 'Penjual sedang menyiapkan pesanan',
                      children: [
                        Text(
                          order.shipmentDeadline == null
                              ? 'Status pelacakan muncul di sini setelah '
                                    'paket dikirim.'
                              : 'Pesanan akan dikirim sebelum '
                                    '${formatShortDateId(order.shipmentDeadline!)}. '
                                    'Status pelacakan muncul di sini setelah '
                                    'paket dikirim.',
                          style: AppTypography.bodySm(context.mutedForeground),
                        ),
                      ],
                    ),

                  if (order.trackingNumber != null) ...[
                    _TrackingCard(order: order),
                    const SizedBox(height: 12),
                  ],

                  _ItemsSection(order: order),
                  const SizedBox(height: 12),

                  _PaymentCard(order: order),
                  const SizedBox(height: 12),

                  _HistoryCard(order: order),

                  if (order.canConfirmReceipt) ...[
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _busy ? null : () => _confirmReceipt(order),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                      child: const Text('Konfirmasi Diterima'),
                    ),
                  ],

                  if (order.status == OrderStatus.shipped ||
                      order.status == OrderStatus.received) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () =>
                          context.push(Routes.orderOpenDispute(widget.slug)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        foregroundColor: colors.error,
                        side: BorderSide(
                          color: colors.error.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Text('Ajukan Sengketa'),
                    ),
                  ],

                  if (order.status == OrderStatus.issue)
                    disputeAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (dispute) {
                        if (dispute == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: OutlinedButton(
                            onPressed: () =>
                                context.push(Routes.orderDispute(widget.slug)),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(46),
                            ),
                            child: const Text('Lihat Detail Sengketa'),
                          ),
                        );
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Web's card shell: a bordered box with an optional titled header.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.icon});

  final String title;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: context.mutedForeground),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.bodySemibold(colors.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _SellerCard extends StatelessWidget {
  const _SellerCard({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          SellerAvatar(
            name: order.storeName,
            imageUrl: order.sellerImageUrl,
            size: 36,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.storeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
                if (order.sellerSecondaryName != null)
                  Text(
                    order.sellerSecondaryName!,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
              ],
            ),
          ),
          if (order.sellerSlug != null)
            TextButton(
              onPressed: () =>
                  context.push(Routes.storeDetail(order.sellerSlug!)),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('Lihat Toko'),
            ),
        ],
      ),
    );
  }
}

/// Ports the tracking block — "Resi" with a copy action, which is the one
/// thing on this page a buyer needs to paste elsewhere.
class _TrackingCard extends StatelessWidget {
  const _TrackingCard({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tracking = order.trackingNumber!;

    return _Section(
      icon: Icons.local_shipping_outlined,
      title: 'Lacak paket',
      children: [
        Row(
          children: [
            Text('Resi', style: AppTypography.caption(context.mutedForeground)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tracking,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmSemibold(colors.onSurface),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Salin nomor resi',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: tracking));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('Nomor resi disalin'),
                      persist: false,
                    ),
                  );
              },
              icon: Icon(
                Icons.copy_outlined,
                size: 16,
                color: context.mutedForeground,
              ),
            ),
          ],
        ),
        if (order.courier != null)
          Text(
            order.courier!.toUpperCase(),
            style: AppTypography.caption(context.mutedForeground),
          ),
      ],
    );
  }
}

/// Ports `buyer-order-items-section.tsx` — the lines, then the money.
class _ItemsSection extends StatelessWidget {
  const _ItemsSection({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return _Section(
      title: 'Item dipesan',
      children: [
        for (final item in order.items) _OrderItemRow(item: item),
        const SizedBox(height: 8),
        Divider(height: 1, color: context.borderColor),
        const SizedBox(height: 10),
        _MoneyRow(label: 'Subtotal', amount: order.itemsSubtotal),
        if (order.shippingTotal > 0)
          _MoneyRow(label: 'Ongkir', amount: order.shippingTotal),
        const SizedBox(height: 6),
        Divider(height: 1, color: context.borderColor),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                'Total dibayar',
                style: AppTypography.bodySemibold(colors.onSurface),
              ),
            ),
            Text(
              formatRupiah(order.total),
              style: AppTypography.bodySemibold(colors.onSurface),
            ),
          ],
        ),
      ],
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({required this.label, required this.amount});

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
          ),
          Text(
            formatRupiah(amount),
            style: AppTypography.bodySm(context.appColors.onSurface),
          ),
        ],
      ),
    );
  }
}

class _OrderItemRow extends StatelessWidget {
  const _OrderItemRow({required this.item});

  final OrderItemModel item;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: CardArt(
              imageUrl: item.card.imageUrl,
              borderRadius: AppRadius.sm,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.card.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${item.card.expansionCode.toUpperCase()} · '
                      '#${item.card.collectorNumber}',
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                    const SizedBox(width: 6),
                    ConditionBadge(condition: item.condition, dense: true),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatRupiah(item.matchPrice),
                style: AppTypography.bodySmSemibold(colors.onSurface),
              ),
              Text(
                '×${item.matchedQuantity}',
                style: AppTypography.caption(context.mutedForeground),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return _Section(
      icon: Icons.payments_outlined,
      title: 'Pembayaran',
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Metode pembayaran',
                style: AppTypography.bodySm(context.mutedForeground),
              ),
            ),
            Text(
              // The channel isn't stored on the order the app reads, so this
              // states what is known rather than guessing a brand.
              order.paidAt == null ? 'Belum dibayar' : 'Xendit',
              style: AppTypography.bodySm(colors.onSurface),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                'Nomor pesanan',
                style: AppTypography.bodySm(context.mutedForeground),
              ),
            ),
            Text(
              order.orderNumber.toUpperCase(),
              style: AppTypography.bodySm(colors.onSurface),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Salin nomor pesanan',
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: order.orderNumber.toUpperCase()),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('Nomor pesanan disalin'),
                      persist: false,
                    ),
                  );
              },
              icon: Icon(
                Icons.copy_outlined,
                size: 16,
                color: context.mutedForeground,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Ports the rail's Riwayat — the four moments an order passes through,
/// dated where a timestamp exists and greyed where it hasn't happened.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final steps = <({String label, DateTime? at})>[
      (label: 'Pesanan dibuat', at: order.createdAt),
      (label: 'Pembayaran diterima', at: order.paidAt),
      (label: 'Pesanan dikirim', at: order.shippedAt),
      (
        label: 'Pesanan selesai',
        at: order.status == OrderStatus.completed
            ? order.deliveredAt ?? order.createdAt
            : null,
      ),
    ];

    return _Section(
      icon: Icons.history,
      title: 'Riwayat',
      children: [
        for (var i = 0; i < steps.length; i++)
          _HistoryRow(
            label: steps[i].label,
            at: steps[i].at,
            isLast: i == steps.length - 1,
          ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.label,
    required this.at,
    required this.isLast,
  });

  final String label;
  final DateTime? at;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final done = at != null;
    final tone = done ? colors.primary : context.borderColor;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: context.borderColor),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: done
                        ? AppTypography.bodySmSemibold(colors.onSurface)
                        : AppTypography.bodySm(context.mutedForeground),
                  ),
                  if (at != null)
                    Text(
                      formatSaleDate(at!),
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
