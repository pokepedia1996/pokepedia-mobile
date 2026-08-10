import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/status_pill.dart';
import '../repository/models/order_model.dart';
import '../usecase/orders_notifier.dart';

/// Ports `app/orders/orders-page.tsx`.
class OrdersPage extends ConsumerWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ordersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Pesanan')),
      body: SafeArea(
        top: false,
        child: async.when(
          data: (orders) {
            if (orders.isEmpty) {
              return const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Belum ada pesanan',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final order = orders[i];
                return _OrderTile(
                  order: order,
                  onTap: () => context.push(Routes.orderDetail(order.slug)),
                );
              },
            );
          },
          loading: () => const PikachuLoader(),
          error: (_, __) => const Center(child: Text('Gagal memuat pesanan')),
        ),
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

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.onTap});

  final OrderModel order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final headline = order.items.length == 1
        ? '${order.items.first.card.name} ×${order.items.first.matchedQuantity}'
        : '${order.items.length} kartu';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.orderNumber,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ),
                StatusPill(
                  label: order.status.label,
                  color: orderStatusColor(context, order.status),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              headline,
              style: AppTypography.bodySmSemibold(colors.onSurface),
            ),
            const SizedBox(height: 2),
            Text(
              order.storeName,
              style: AppTypography.caption(context.mutedForeground),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatRupiah(order.total),
                  style: AppTypography.bodySemibold(colors.onSurface),
                ),
                Text(
                  formatRelativeId(order.createdAt),
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
