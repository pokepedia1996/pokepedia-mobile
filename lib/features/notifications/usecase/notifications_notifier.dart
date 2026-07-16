import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repository/models/notification_model.dart';
import '../repository/notifications_repository.dart';

final notificationsRepositoryProvider = Provider(
  (ref) => NotificationsRepository(),
);

class NotificationsNotifier extends AsyncNotifier<List<NotificationModel>> {
  @override
  Future<List<NotificationModel>> build() {
    return ref.read(notificationsRepositoryProvider).fetchNotifications();
  }

  void markRead(int id) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([
      for (final n in current)
        if (n.id == id) n.copyWith(isRead: true) else n,
    ]);
  }
}

final notificationsProvider =
    AsyncNotifierProvider<NotificationsNotifier, List<NotificationModel>>(
      NotificationsNotifier.new,
    );
