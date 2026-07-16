import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/condition_badge.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/status_pill.dart';
import '../repository/models/order_model.dart';
import '../usecase/orders_notifier.dart';
import 'orders_page.dart' show orderStatusColor;

/// Ports `app/orders/[slug]/order-detail.tsx`.
class OrderDetailPage extends ConsumerWidget {
  const OrderDetailPage({super.key, required this.slug});

  final String slug;

  static const _steps = [
    'Menunggu Dikirim',
    'Dikirim',
    'Diterima',
    'Selesai',
  ];

  int _stepIndex(OrderStatus status) {
    switch (status) {
      case OrderStatus.awaitingShipment:
        return 0;
      case OrderStatus.shipped:
        return 1;
      case OrderStatus.received:
        return 2;
      case OrderStatus.completed:
        return 3;
      case OrderStatus.cancelled:
      case OrderStatus.issue:
        return -1;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderDetailProvider(slug));
    final disputeAsync = ref.watch(orderDisputeProvider(slug));
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(title: Text(async.valueOrNull?.orderNumber ?? slug)),
      body: SafeArea(
        top: false,
        child: async.when(
          data: (order) {
            if (order == null) {
              return const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Pesanan tidak ditemukan',
              );
            }
            final activeStep = _stepIndex(order.status);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatRelativeId(order.createdAt),
                      style: AppTypography.bodySm(context.mutedForeground),
                    ),
                    StatusPill(
                      label: order.status.label,
                      color: orderStatusColor(context, order.status),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (activeStep >= 0)
                  _Stepper(activeIndex: activeStep, steps: _steps)
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 18, color: colors.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            order.status == OrderStatus.cancelled
                                ? 'Pesanan ini telah dibatalkan.'
                                : 'Pesanan ini sedang dalam proses sengketa.',
                            style: AppTypography.bodySm(colors.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                Text('Penjual', style: AppTypography.captionSemibold(context.mutedForeground)),
                const SizedBox(height: 4),
                Text(order.storeName, style: AppTypography.bodySmSemibold(colors.onSurface)),
                if (order.trackingNumber != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.local_shipping_outlined, size: 14, color: context.mutedForeground),
                      const SizedBox(width: 4),
                      Text(
                        '${order.courier} · ${order.trackingNumber}',
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Text('Item Pesanan', style: AppTypography.captionSemibold(context.mutedForeground)),
                const SizedBox(height: 8),
                for (final item in order.items) _OrderItemTile(item: item),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: context.borderColor)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total', style: AppTypography.bodySemibold(colors.onSurface)),
                      Text(formatRupiah(order.total), style: AppTypography.bodySemibold(colors.onSurface)),
                    ],
                  ),
                ),
                if (order.status == OrderStatus.shipped || order.status == OrderStatus.received) ...[
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => context.push(Routes.orderOpenDispute(slug)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      foregroundColor: colors.error,
                      side: BorderSide(color: colors.error.withValues(alpha: 0.4)),
                    ),
                    child: const Text('Ajukan Sengketa'),
                  ),
                ],
                if (order.status == OrderStatus.issue)
                  disputeAsync.when(
                    data: (dispute) {
                      if (dispute == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: OutlinedButton(
                          onPressed: () => context.push(Routes.orderDispute(slug)),
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                          child: const Text('Lihat Detail Sengketa'),
                        ),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('Gagal memuat pesanan')),
        ),
      ),
    );
  }
}

class _OrderItemTile extends StatelessWidget {
  const _OrderItemTile({required this.item});

  final OrderItemModel item;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 48, child: CardArt(borderRadius: AppRadius.sm)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.card.name, style: AppTypography.bodySmSemibold(colors.onSurface)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    ConditionBadge(condition: item.condition),
                    const SizedBox(width: 6),
                    Text('×${item.matchedQuantity}', style: AppTypography.caption(context.mutedForeground)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(item.status.label, style: AppTypography.caption(context.mutedForeground)),
              ],
            ),
          ),
          Text(formatRupiah(item.subtotal), style: AppTypography.bodySmSemibold(colors.onSurface)),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.activeIndex, required this.steps});

  final int activeIndex;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i <= activeIndex ? colors.primary : colors.secondary,
                    ),
                    child: i <= activeIndex
                        ? const Icon(Icons.check, size: 12, color: Colors.white)
                        : null,
                  ),
                  if (i != steps.length - 1)
                    Container(
                      width: 2,
                      height: 28,
                      color: i < activeIndex ? colors.primary : context.borderColor,
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  steps[i],
                  style: i <= activeIndex
                      ? AppTypography.bodySmSemibold(colors.onSurface)
                      : AppTypography.bodySm(context.mutedForeground),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
