import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../repository/models/notification_model.dart';
import '../usecase/notifications_notifier.dart';

/// Ports `app/notifications/notifications-client.tsx`.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  IconData _iconFor(NotificationType type) {
    switch (type) {
      case NotificationType.listingSold:
      case NotificationType.paymentReceived:
      case NotificationType.tradeCompleted:
      case NotificationType.orderCancelled:
      case NotificationType.shipmentPickedUp:
      case NotificationType.shipmentDelivered:
        return Icons.local_shipping_outlined;
      case NotificationType.disputeOpened:
      case NotificationType.disputeResolved:
      case NotificationType.disputeMessage:
        return Icons.gavel_outlined;
      case NotificationType.bidProposalReceived:
      case NotificationType.bidProposalAccepted:
      case NotificationType.offerReceived:
      case NotificationType.offerAccepted:
      case NotificationType.offerCountered:
        return Icons.local_offer_outlined;
      case NotificationType.ratingReceived:
        return Icons.star_outline;
      case NotificationType.chatMessage:
        return Icons.chat_bubble_outline;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    final notifier = ref.read(notificationsProvider.notifier);
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifikasi')),
      body: SafeArea(
        top: false,
        child: async.when(
          data: (items) {
            if (items.isEmpty) {
              return const EmptyState(
                icon: Icons.notifications_none,
                title: 'Belum ada notifikasi',
              );
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (context, i) =>
                  Divider(height: 1, color: context.borderColor, indent: 68),
              itemBuilder: (context, i) {
                final item = items[i];
                return InkWell(
                  onTap: () => notifier.markRead(item.id),
                  child: Container(
                    color: item.isRead
                        ? null
                        : colors.primary.withValues(alpha: 0.04),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: colors.secondary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _iconFor(item.type),
                            size: 17,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: item.isRead
                                    ? AppTypography.bodySm(colors.onSurface)
                                    : AppTypography.bodySmSemibold(
                                        colors.onSurface,
                                      ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.body,
                                style: AppTypography.caption(
                                  context.mutedForeground,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.createdAt,
                                style: AppTypography.caption(
                                  context.mutedForeground,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!item.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('Gagal memuat notifikasi')),
        ),
      ),
    );
  }
}
