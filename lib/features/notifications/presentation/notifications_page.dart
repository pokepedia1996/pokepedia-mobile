import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
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
      case NotificationType.other:
        return Icons.notifications_none;
    }
  }

  /// `action_url` is written for the website. Most of its paths exist in the
  /// app under the same name, but not all do — anything outside this list
  /// would land on the router's error page, so those rows just mark read.
  static const _navigablePrefixes = [
    '/orders',
    '/chat',
    '/market',
    '/expansions',
    '/portfolio',
    '/proposals',
    '/wallet',
    '/user',
  ];

  String? _appRouteFor(String? actionUrl) {
    if (actionUrl == null || !actionUrl.startsWith('/')) return null;
    for (final prefix in _navigablePrefixes) {
      if (actionUrl == prefix || actionUrl.startsWith('$prefix/')) {
        return actionUrl;
      }
    }
    return null;
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
              icon: Icons.notifications_none,
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
                    icon: Icons.notifications_none,
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
                          final route = _appRouteFor(item.actionUrl);
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
                icon: Icons.error_outline,
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
