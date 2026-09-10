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
import '../../../shared/widgets/inline_pill.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../orders/presentation/widgets/order_thumbnail.dart';
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
        // Web's header: the title, then the package number under it. The
        // creation date moves into the Pesanan card, where web keeps it as
        // "Tanggal pesan".
        Text('Detail pesanan', style: AppTypography.h1(colors.onSurface)),
        const SizedBox(height: 2),
        Text(
          order.orderNumber.toUpperCase(),
          style: AppTypography.bodySmSemibold(context.mutedForeground),
        ),
        const SizedBox(height: 16),

        _Section(
          title: 'Items',
          trailing: Text(
            '${order.items.length} item${order.items.length > 1 ? "s" : ""}',
            style: AppTypography.caption(context.mutedForeground),
          ),
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

        _Section(
          title: 'Pesanan',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Web keeps the order's identity, its date, who bought it and
              // where it's going in one card rather than scattering them —
              // they're all answers to "whose order is this?".
              _InfoRow(
                label: 'Order ID',
                value: order.orderNumber.toUpperCase(),
              ),
              _InfoRow(
                label: 'Tanggal pesan',
                value: formatSaleDate(order.createdAt),
              ),
              _InfoRow(
                label: 'Pembeli',
                value: detail.buyerUsername == null
                    ? 'Pembeli'
                    : '@${detail.buyerUsername}',
              ),
              if (detail.destination case final destination?
                  when !destination.isEmpty) ...[
                Divider(color: context.borderColor, height: 20),
                Text(
                  'ALAMAT PENGIRIMAN',
                  style: AppTypography.overline(context.mutedForeground),
                ),
                const SizedBox(height: 6),
                _DestinationBlock(destination: destination),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'Pembayaran',
          child: Column(
            children: [
              _MoneyRow(label: 'Subtotal', amount: detail.subtotal),
              _MoneyRow(label: 'Ongkir', amount: detail.shippingCost),
              if (detail.insuranceFee > 0)
                _MoneyRow(label: 'Asuransi', amount: detail.insuranceFee),
              Divider(color: context.borderColor, height: 20),
              _MoneyRow(
                label: 'Total dibayar',
                amount: detail.buyerPaid,
                emphasis: true,
              ),
              _MoneyRow(
                label: 'Komisi platform (3%)',
                amount: -detail.commissionAmount,
              ),
              Divider(color: context.borderColor, height: 20),
              _MoneyRow(
                label: 'Pendapatan',
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

/// Ports `order-items-section.tsx`'s row — a `[64px | 1fr | auto]` grid.
///
/// The thumbnail is a square crop, not [CardArt]'s 245:342 portrait: web uses
/// `size-16 object-cover` on every order surface, which is what made the two
/// screens read so differently.
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final OrderItemModel item;

  /// Ports `itemStatusPill`, in web's order of precedence.
  ({String label, InlinePillTone tone})? get _pill {
    if (item.dispute != null) {
      return (label: 'Dikomplain', tone: InlinePillTone.danger);
    }
    if (item.releasedAt != null) {
      return (label: 'Dana dirilis', tone: InlinePillTone.success);
    }
    if (item.settlementStatus == 'refunded' ||
        item.settlementStatus == 'cancelled') {
      return (label: 'Dibatalkan', tone: InlinePillTone.neutral);
    }
    return (label: 'Dalam escrow', tone: InlinePillTone.progress);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final pill = _pill;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OrderThumbnail(imageUrl: item.card.imageUrl, radius: AppRadius.sm),
        const SizedBox(width: 12),
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
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (item.card.expansionCode.isNotEmpty)
                    ExpansionChip(code: item.card.expansionCode),
                  Text(
                    '#${item.card.collectorNumber}',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                  ConditionBadge(condition: item.condition, dense: true),
                ],
              ),
              const SizedBox(height: 4),
              // Each line carries its own number: a package can hold several,
              // and this is the one a seller quotes about one card.
              Text(
                item.orderNumber.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.captionSemibold(colors.onSurface),
              ),
              if (pill != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: InlinePill(tone: pill.tone, label: pill.label),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '×${item.matchedQuantity}',
              style: AppTypography.caption(context.mutedForeground),
            ),
            Text(
              formatRupiah(item.matchPrice),
              style: AppTypography.caption(context.mutedForeground),
            ),
            const SizedBox(height: 2),
            Text(
              formatRupiah(item.subtotal),
              style: AppTypography.bodySmSemibold(colors.onSurface),
            ),
          ],
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
            // What the buyer actually paid for. Without it the seller has to
            // guess which courier to hand the parcel to — web leads the
            // dispatch step with this card for that reason.
            if (detail.buyerCourierLabel case final courier?) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.truck, size: 18, color: colors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Kurir pilihan pembeli',
                            style: AppTypography.caption(
                              context.mutedForeground,
                            ),
                          ),
                          Text(
                            courier,
                            style: AppTypography.bodySmSemibold(
                              colors.onSurface,
                            ),
                          ),
                          if (detail.etd case final etd?)
                            Text(
                              'Estimasi $etd',
                              style: AppTypography.caption(
                                context.mutedForeground,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
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
            // Web pairs the date with how long is actually left; a bare
            // date makes a deadline three hours away look like any other.
            [
              'Kirim sebelum ${formatDeadlineId(order.shipmentDeadline!)}',
              if (order.shipmentDeadline!.isAfter(DateTime.now()))
                'Sisa ${formatCountdownId(order.shipmentDeadline!.difference(DateTime.now()))}'
              else
                'Lewat batas',
            ].join(' · '),
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
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;

  /// The right-hand side of the header — web puts an item count there.
  final Widget? trailing;

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
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.bodySmSemibold(
                      context.appColors.onSurface,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
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
        color: context.appSemantic.condMp.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: context.appSemantic.condMp.withValues(alpha: 0.4),
        ),
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

/// A label on the left, its value on the right — the `<dt>`/`<dd>` pairs
/// web's Pesanan card is built from.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTypography.bodySmSemibold(context.appColors.onSurface),
            ),
          ),
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
    // `condMp` is the app's amber, which is the warning tone web paints a
    // waiting state in. `tertiary` was never set on either ColorScheme, so
    // it resolved to Material's default — a near-black in dark mode, which
    // is why "Menunggu dikirim" was unreadable.
    'awaiting_shipment' || null => context.appSemantic.condMp,
    _ => context.mutedForeground,
  };
}
