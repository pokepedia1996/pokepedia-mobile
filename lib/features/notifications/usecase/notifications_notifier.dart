import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../repository/models/notification_model.dart';
import '../repository/notifications_repository.dart';

final notificationsRepositoryProvider = Provider(
  (ref) => NotificationsRepository(ref.read(supabaseClientProvider)),
);

class NotificationsNotifier extends AsyncNotifier<List<NotificationModel>> {
  @override
  Future<List<NotificationModel>> build() {
    // Rebuilds on sign-in/out so one account never sees another's inbox.
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return Future.value(const <NotificationModel>[]);
    return ref.read(notificationsRepositoryProvider).fetchNotifications();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(notificationsRepositoryProvider).fetchNotifications(),
    );
  }

  /// Marks one row read, locally first — the dot should clear on tap, not a
  /// round trip later.
  Future<void> markRead(int id) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final target = current.firstWhere(
      (n) => n.id == id,
      orElse: () => current.first,
    );
    if (target.id != id || target.isRead) return;

    state = AsyncData([
      for (final n in current)
        if (n.id == id) n.copyWith(isRead: true) else n,
    ]);
    try {
      await ref.read(notificationsRepositoryProvider).markRead(id);
    } catch (_) {
      // Put the dot back rather than claiming a read that didn't stick.
      final latest = state.valueOrNull;
      if (latest == null) return;
      state = AsyncData([
        for (final n in latest)
          if (n.id == id) n.copyWith(isRead: false) else n,
      ]);
    }
  }

  Future<void> markAllRead() async {
    final current = state.valueOrNull;
    if (current == null || current.every((n) => n.isRead)) return;

    state = AsyncData([for (final n in current) n.copyWith(isRead: true)]);
    try {
      await ref.read(notificationsRepositoryProvider).markAllRead();
    } catch (_) {
      await refresh();
    }
  }
}

final notificationsProvider =
    AsyncNotifierProvider<NotificationsNotifier, List<NotificationModel>>(
      NotificationsNotifier.new,
    );

/// Unread count, for badges elsewhere in the app.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final items = ref.watch(notificationsProvider).valueOrNull;
  if (items == null) return 0;
  return items.where((n) => !n.isRead).length;
});
