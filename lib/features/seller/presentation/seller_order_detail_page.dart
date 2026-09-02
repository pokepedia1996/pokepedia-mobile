import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
import '../../orders/repository/models/order_model.dart';
import '../../orders/repository/models/seller_order_detail.dart';
import '../../orders/usecase/orders_notifier.dart';
import '../usecase/seller_order_detail_notifier.dart';
import 'widgets/dispatch_sheet.dart';

/// Ports `/seller/orders/[matchId]` — one order from the side that has to
/// pack it.
///
/// Web lays this out as a two-column grid: items and shipping on the left, a
/// summary rail on the right. On a phone the rail becomes the last section,
/// which keeps web's reading order (what sold → where it's going → what it
/// pays) without a column that has nowhere to sit.
class SellerOrderDetailPage extends ConsumerWidget {
  const SellerOrderDetailPage({super.key, required this.orderSlug});

  final String orderSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final async = ref.watch(sellerOrderDetailProvider(orderSlug));

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: TransparentAppBar(
        title: Text(
          'Detail pesanan',
          style: AppTypography.bodySemibold(colors.onSurface),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: PikachuLoader()),
        error: (_, _) => const EmptyState(
          icon: LucideIcons.circleAlert,
          title: 'Gagal memuat pesanan',
          description: 'Tarik ke bawah untuk mencoba lagi.',
        ),
        data: (detail) {
          if (detail == null) {
            // `orders_select_own` covers buyers too, so the query filters on
            // `seller_id`. A miss here means the order isn't this user's to
            // sell — not that it doesn't exist.
            return const EmptyState(
              icon: LucideIcons.receipt,
              title: 'Pesanan tidak ditemukan',
              description: 'Pesanan ini bukan milik tokomu.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(sellerOrderDetailProvider(orderSlug)),
            child: _Body(detail: detail),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.detail});

  final SellerOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final order = detail.order;
    final colors = context.appColors;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Text(
          order.orderNumber.toUpperCase(),
          style: AppTypography.bodySmSemibold(context.mutedForeground),
        ),
        const SizedBox(height: 2),
        Text(
          'Dibuat ${formatSaleDate(order.createdAt)}',
          style: AppTypography.caption(context.mutedForeground),
        ),
        const SizedBox(height: 16),

        _Section(
          title: 'Item (${order.items.length})',
          child: Column(
            children: [
              for (var i = 0; i < order.items.length; i++) ...[
                if (i > 0) Divider(color: context.borderColor, height: 20),
                _ItemRow(item: order.items[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (detail.awaitingPayment)
          _Notice(
            title: 'Menunggu pembayaran pembeli',
            body:
                'Pengiriman akan tersedia setelah dana masuk ke sistem'
                '${_deadlineSuffix(order)}.',
          )
        else
          _Section(
            title: 'Pengiriman',
            child: _ShipmentBlock(detail: detail),
          ),
        const SizedBox(height: 12),

        if (detail.destination != null) ...[
          _Section(
            title: 'Alamat tujuan',
            child: _DestinationBlock(destination: detail.destination!),
          ),
          const SizedBox(height: 12),
        ],

        _Section(
          title: 'Rincian',
          child: Column(
            children: [
              _MoneyRow(label: 'Subtotal', amount: detail.subtotal),
              _MoneyRow(label: 'Ongkir', amount: detail.shippingCost),
              if (detail.insuranceFee > 0)
                _MoneyRow(label: 'Asuransi', amount: detail.insuranceFee),
              Divider(color: context.borderColor, height: 20),
              _MoneyRow(
                label: 'Dibayar pembeli ke kamu',
                amount: detail.buyerPaid,
                emphasis: true,
              ),
              _MoneyRow(
                label: 'Komisi platform',
                amount: -detail.commissionAmount,
              ),
              Divider(color: context.borderColor, height: 20),
              _MoneyRow(
                label: 'Kamu terima',
                amount: detail.sellerNetAmount,
                emphasis: true,
                color: colors.primary,
              ),
              const SizedBox(height: 8),
              Text(
                _payoutNote(detail),
                style: AppTypography.caption(context.mutedForeground),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        _Section(
          title: 'Pembeli',
          child: Row(
            children: [
              Expanded(
                child: Text(
                  detail.buyerUsername == null
                      ? 'Pembeli'
                      : '@${detail.buyerUsername}',
                  style: AppTypography.bodySm(colors.onSurface),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Web shows the buyer's payment deadline. The app has it only once a
/// settlement row carries one, so the sentence adapts rather than printing
/// "sampai null".
String _deadlineSuffix(OrderModel order) {
  for (final item in order.items) {
    final deadline = item.paymentDeadline;
    if (deadline != null) {
      return '. Pembeli punya waktu sampai ${formatSaleDate(deadline)} '
          '${formatClockId(deadline)}';
    }
  }
  return '';
}

String _payoutNote(SellerOrderDetail detail) {
  if (detail.hasOpenDispute) {
    return 'Dana ditahan sampai ${detail.disputedCount} komplain selesai.';
  }
  if (detail.inEscrow) {
    return 'Dana ditahan sampai pembeli mengonfirmasi penerimaan.';
  }
  return 'Komisi sudah dipotong dari jumlah yang kamu terima.';
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final OrderItemModel item;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          height: 61,
          child: CardArt(imageUrl: item.card.imageUrl),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.card.nameId,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmSemibold(colors.onSurface),
              ),
              const SizedBox(height: 2),
              Text(
                '${item.card.expansionCode} · ${item.card.collectorNumber}',
                style: AppTypography.caption(context.mutedForeground),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  ConditionBadge(condition: item.condition),
                  const SizedBox(width: 6),
                  Text(
                    '${item.matchedQuantity}x',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                  const Spacer(),
                  Text(
                    formatRupiah(item.subtotal),
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                ],
              ),
              if (item.dispute != null) ...[
                const SizedBox(height: 6),
                StatusPill(label: 'Komplain dibuka', color: colors.error),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Status, courier, tracking — and, while the order is still waiting on the
/// seller, the button that dispatches it.
///
/// Booking goes through `/api/shipments/[shipmentSlug]/dispatch` rather than
/// Biteship directly: the key and the `service_role` writes behind it stay on
/// the server, exactly as they do for the web's own form.
class _ShipmentBlock extends ConsumerWidget {
  const _ShipmentBlock({required this.detail});

  final SellerOrderDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = detail.order;
    final colors = context.appColors;
    final tracking = order.trackingNumber;
    final bookError = order.biteshipBookError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            StatusPill(
              label: _shipmentLabel(order),
              color: _shipmentColor(context, order),
            ),
            const Spacer(),
            if (order.courier != null)
              Text(
                order.courier!.toUpperCase(),
                style: AppTypography.captionSemibold(colors.onSurface),
              ),
          ],
        ),

        if (tracking != null && tracking.isNotEmpty) ...[
          const SizedBox(height: 10),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: tracking));
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(
                  const SnackBar(
                    content: Text('Nomor resi disalin'),
                    persist: false,
                  ),
                );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colors.secondary,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tracking,
                      style: AppTypography.bodySmSemibold(colors.onSurface),
                    ),
                  ),
                  Icon(
                    LucideIcons.copy,
                    size: 15,
                    color: context.mutedForeground,
                  ),
                ],
              ),
            ),
          ),
        ],

        if (bookError != null && bookError.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Gagal booking kurir: $bookError',
            style: AppTypography.caption(colors.error),
          ),
        ],

        if (detail.awaitingShipment &&
            (tracking == null || tracking.isEmpty)) ...[
          const SizedBox(height: 10),
          if (order.shipmentSlug == null)
            // No shipment row yet: the courier is booked when the buyer pays,
            // so this is a moment in the flow, not something to act on.
            Text(
              'Pengiriman belum siap diatur. Muat ulang sebentar lagi.',
              style: AppTypography.caption(context.mutedForeground),
            )
          else ...[
            Text(
              'Pesanan ini menunggu dikirim. Atur penjemputan kurir atau isi '
              'nomor resi kalau kamu antar sendiri.',
              style: AppTypography.caption(context.mutedForeground),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final done = await showDispatchSheet(
                    context,
                    shipmentSlug: order.shipmentSlug!,
                    detail: detail,
                  );
                  if (done == true) {
                    ref.invalidate(sellerOrderDetailProvider(order.slug));
                    ref.invalidate(sellerOrdersProvider);
                  }
                },
                icon: const Icon(LucideIcons.truck, size: 16),
                label: const Text('Atur Pengiriman'),
              ),
            ),
          ],
        ],

        if (order.shipmentDeadline != null) ...[
          const SizedBox(height: 8),
          Text(
            'Batas kirim ${formatSaleDate(order.shipmentDeadline!)}',
            style: AppTypography.caption(context.mutedForeground),
          ),
        ],
      ],
    );
  }
}

class _DestinationBlock extends StatelessWidget {
  const _DestinationBlock({required this.destination});

  final ShipmentDestination destination;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (destination.contactName != null)
          Text(
            destination.contactName!,
            style: AppTypography.bodySmSemibold(colors.onSurface),
          ),
        if (destination.contactPhone != null)
          Text(
            destination.contactPhone!,
            style: AppTypography.caption(context.mutedForeground),
          ),
        if (destination.fullAddress != null) ...[
          const SizedBox(height: 4),
          Text(
            destination.fullAddress!,
            style: AppTypography.bodySm(colors.onSurface),
          ),
        ],
        if (destination.areaLine.isNotEmpty)
          Text(
            destination.areaLine,
            style: AppTypography.caption(context.mutedForeground),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.borderColor)),
            ),
            child: Text(
              title,
              style: AppTypography.bodySmSemibold(context.appColors.onSurface),
            ),
          ),
          Padding(padding: const EdgeInsets.all(14), child: child),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.tertiary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.tertiary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.bodySmSemibold(colors.onSurface)),
          const SizedBox(height: 4),
          Text(body, style: AppTypography.caption(context.mutedForeground)),
        ],
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.amount,
    this.emphasis = false,
    this.color,
  });

  final String label;
  final int amount;
  final bool emphasis;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final valueStyle = emphasis
        ? AppTypography.bodySmSemibold(color ?? colors.onSurface)
        : AppTypography.bodySm(color ?? colors.onSurface);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: emphasis
                  ? AppTypography.bodySmSemibold(colors.onSurface)
                  : AppTypography.bodySm(context.mutedForeground),
            ),
          ),
          Text(
            // A negative amount is a deduction, so it reads as one rather
            // than as "Rp-12.000".
            amount < 0 ? '-${formatRupiah(-amount)}' : formatRupiah(amount),
            style: valueStyle,
          ),
        ],
      ),
    );
  }
}

String _shipmentLabel(OrderModel order) => switch (order.shipmentStatus) {
  'awaiting_shipment' || null => 'Menunggu dikirim',
  'confirmed' || 'allocated' || 'picking_up' => 'Menunggu kurir',
  'picked' || 'dropping_off' || 'on_hold' => 'Dalam perjalanan',
  'delivered' => 'Terkirim',
  'cancelled' || 'rejected' || 'returned' => 'Dibatalkan',
  final other => other,
};

Color _shipmentColor(BuildContext context, OrderModel order) {
  final colors = context.appColors;
  return switch (order.shipmentStatus) {
    'delivered' => colors.primary,
    'cancelled' || 'rejected' || 'returned' => colors.error,
    'awaiting_shipment' || null => colors.tertiary,
    _ => context.mutedForeground,
  };
}
