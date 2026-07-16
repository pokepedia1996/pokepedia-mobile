import 'models/notification_model.dart';

/// Data access for the Notifications feature. Stands in for
/// `public.notifications` in
/// `supabase/migrations/00000000000000_baseline.sql` while this pass only
/// ports the UI with dummy data.
class NotificationsRepository {
  Future<List<NotificationModel>> fetchNotifications() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return const [
      NotificationModel(
        id: 1,
        type: NotificationType.shipmentDelivered,
        category: NotificationCategory.statusUpdate,
        title: 'Pesanan dikirim',
        body: 'Pesanan PKP-20260700 telah dikirim oleh Card Vault ID.',
        createdAt: '10 menit lalu',
        isRead: false,
      ),
      NotificationModel(
        id: 2,
        type: NotificationType.offerReceived,
        category: NotificationCategory.actionRequired,
        title: 'Penawaran baru',
        body: 'user_102 mengajukan penawaran untuk Charizard ex.',
        createdAt: '1 jam lalu',
        isRead: false,
      ),
      NotificationModel(
        id: 3,
        type: NotificationType.chatMessage,
        category: NotificationCategory.social,
        title: 'Pesan baru',
        body: 'Poke Corner: Boleh nego dikit gak kak?',
        createdAt: 'Kemarin',
        isRead: true,
      ),
      NotificationModel(
        id: 4,
        type: NotificationType.disputeOpened,
        category: NotificationCategory.actionRequired,
        title: 'Sengketa dibuka',
        body: 'Sengketa untuk pesanan PKP-20260703 menunggu responsmu.',
        createdAt: '2 hari lalu',
        isRead: true,
      ),
      NotificationModel(
        id: 5,
        type: NotificationType.ratingReceived,
        category: NotificationCategory.social,
        title: 'Penilaian baru',
        body: 'Card Vault ID memberimu penilaian positif.',
        createdAt: '3 hari lalu',
        isRead: true,
      ),
    ];
  }
}
