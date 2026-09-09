import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router/routes.dart';
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

  /// Marks a row read, locally first — the dot should clear on tap, not a
  /// round trip later.
  ///
  /// For a conversation this marks the tapped row's siblings too. See
  /// [_conversationSiblings]: `notify_chat_message` writes one row per
  /// message, so tapping one of five identical "Pesan baru" rows used to
  /// leave four behind and read as a tap that did nothing.
  Future<void> markRead(int id) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final target = current.where((n) => n.id == id).firstOrNull;
    if (target == null || target.isRead) return;

    await _markIdsRead({id, ..._conversationSiblings(current, target)});
  }

  /// Clears the notifications for a conversation that has just been opened.
  ///
  /// Called when a chat thread loads, whichever way the reader got there —
  /// through a notification, the inbox, or a link from a listing. The rows
  /// are written one per message, so the ones about a thread you have just
  /// read are stale by definition; before this, only tapping the
  /// notification cleared them and reading from the inbox left the bell lit
  /// for messages already read.
  ///
  /// Waits for the list when it hasn't been fetched yet: on a fresh start
  /// nothing has read `notificationsProvider`, and the rows that need
  /// clearing are exactly the ones the user hasn't looked at.
  Future<void> markChatRoomRead(String roomSlug) async {
    if (roomSlug.isEmpty) return;
    final url = Routes.chatThread(roomSlug);

    var current = state.valueOrNull;
    if (current == null) {
      try {
        // Bounded: this future is re-created whenever the provider rebuilds
        // (a sign-in resolving mid-flight, say), and a chat opening is not
        // worth a promise that might never settle. Timing out lands on the
        // old behaviour — the rows stay until they're tapped.
        current = await future.timeout(const Duration(seconds: 8));
      } catch (_) {
        // No inbox, nothing to reconcile — the badge is already wrong in a
        // way this can't fix.
        return;
      }
    }

    await _markIdsRead({
      for (final n in current)
        if (!n.isRead &&
            n.type == NotificationType.chatMessage &&
            n.actionUrl == url)
          n.id,
    });
  }

  /// Flips a set of rows read, locally first, and puts them back if the
  /// write doesn't stick.
  Future<void> _markIdsRead(Set<int> ids) async {
    if (ids.isEmpty) return;
    final current = state.valueOrNull;
    if (current == null) return;

    // The server takes the row's slug; everything local is keyed by id.
    final slugs = [
      for (final n in current)
        if (ids.contains(n.id) && n.slug.isNotEmpty) n.slug,
    ];
    if (slugs.isEmpty) return;

    state = AsyncData([
      for (final n in current)
        if (ids.contains(n.id)) n.copyWith(isRead: true) else n,
    ]);
    try {
      final repository = ref.read(notificationsRepositoryProvider);
      await Future.wait([for (final slug in slugs) repository.markRead(slug)]);
    } catch (_) {
      // Put the dots back rather than claiming a read that didn't stick.
      final latest = state.valueOrNull;
      if (latest == null) return;
      state = AsyncData([
        for (final n in latest)
          if (ids.contains(n.id)) n.copyWith(isRead: false) else n,
      ]);
    }
  }

  /// The other unread rows the same tap has just dealt with.
  ///
  /// Only for the types the server writes one row per *message* of — a chat
  /// message and a dispute message. Opening the thread reads the whole
  /// conversation, so every unread row pointing at it is stale the moment
  /// one of them is opened.
  ///
  /// Deliberately not done for the rest: two rows can point at one order
  /// ("Pembayaran diterima", then "Paket dikirim") and reading one of those
  /// says nothing about the other.
  Iterable<int> _conversationSiblings(
    List<NotificationModel> all,
    NotificationModel target,
  ) {
    const conversational = {
      NotificationType.chatMessage,
      NotificationType.disputeMessage,
    };
    if (!conversational.contains(target.type)) return const [];
    final url = target.actionUrl;
    if (url == null || url.isEmpty) return const [];

    return all
        .where((n) => !n.isRead && n.type == target.type && n.actionUrl == url)
        .map((n) => n.id);
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
