import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../repository/models/notification_model.dart';
import '../usecase/notification_route.dart';
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
        return LucideIcons.truck;
      case NotificationType.disputeOpened:
      case NotificationType.disputeResolved:
      case NotificationType.disputeMessage:
        return LucideIcons.gavel;
      case NotificationType.bidProposalReceived:
      case NotificationType.bidProposalAccepted:
      case NotificationType.offerReceived:
      case NotificationType.offerAccepted:
      case NotificationType.offerCountered:
        return LucideIcons.tag;
      case NotificationType.ratingReceived:
        return LucideIcons.star;
      case NotificationType.chatMessage:
        return LucideIcons.messageCircle;
      case NotificationType.other:
        return LucideIcons.bell;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    final notifier = ref.read(notificationsProvider.notifier);
    final colors = context.appColors;

    final signedIn = ref.watch(authProvider).valueOrNull != null;
    final unread = ref.watch(unreadNotificationCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: notifier.markAllRead,
              child: const Text('Tandai semua'),
            ),
        ],
      ),
      body: !signedIn
          ? EmptyState(
              icon: LucideIcons.bell,
              title: 'Masuk untuk melihat notifikasi',
              action: ElevatedButton(
                onPressed: () => context.push(Routes.login),
                child: const Text('Masuk'),
              ),
            )
          : async.when(
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: LucideIcons.bell,
                    title: 'Belum ada notifikasi',
                  );
                }
                return RefreshIndicator(
                  onRefresh: notifier.refresh,
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (context, i) => Divider(
                      height: 1,
                      color: context.borderColor,
                      indent: 68,
                    ),
                    itemBuilder: (context, i) {
                      final item = items[i];
                      return InkWell(
                        onTap: () {
                          notifier.markRead(item.id);
                          final route = appRouteForActionUrl(item.actionUrl);
                          if (route != null) context.push(route);
                        },
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
                                          ? AppTypography.bodySm(
                                              colors.onSurface,
                                            )
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
                                      item.createdLabel,
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
                  ),
                );
              },
              loading: () => const PikachuLoader(),
              error: (_, __) => EmptyState(
                icon: LucideIcons.circleAlert,
                title: 'Gagal memuat notifikasi',
                action: OutlinedButton(
                  onPressed: notifier.refresh,
                  child: const Text('Coba lagi'),
                ),
              ),
            ),
    );
  }
}
