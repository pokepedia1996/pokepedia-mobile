import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/notification_model.dart';

/// Data access for `public.notifications`.
///
/// Reads go straight to the table (`notifications_select_own` scopes them to
/// the caller); the two writes go through the RPCs, since there is no UPDATE
/// policy on the table.
class NotificationsRepository {
  NotificationsRepository(this._client);

  final SupabaseClient _client;

  static const _columns =
      'id, slug, type, category, title, body, is_read, action_url, created_at';

  /// The inbox, plus the unread chat rows.
  ///
  /// Chat is not shown in the inbox (the chat tab has its own badge), so it
  /// is kept out of [limit]: one row is written per message, and an active
  /// conversation would otherwise crowd everything else out of the page.
  /// The unread chat rows still come along because opening a thread marks
  /// them read (`markChatRoomRead`), and that needs them in the list.
  Future<List<NotificationModel>> fetchNotifications({int limit = 50}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    final chat = NotificationType.chatMessage.raw;
    final results = await Future.wait([
      _client
          .from('notifications')
          .select(_columns)
          .eq('user_id', userId)
          .neq('type', chat)
          .order('created_at', ascending: false)
          .limit(limit),
      _client
          .from('notifications')
          .select(_columns)
          .eq('user_id', userId)
          .eq('type', chat)
          .eq('is_read', false)
          .order('created_at', ascending: false)
          .limit(200),
    ]);
    return [
      for (final rows in results)
        for (final r in rows as List)
          NotificationModel.fromRow(r as Map<String, dynamic>),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Takes the row's uuid slug, not its `id`: that is the argument the
  /// deployed `mark_notification_read` declares, and PostgREST resolves an
  /// overload by argument name — calling it with `p_id` matched nothing and
  /// came back PGRST202, which read to the app as a failed write, so every
  /// tapped notification's dot came straight back.
  Future<void> markRead(String slug) =>
      _client.rpc('mark_notification_read', params: {'p_slug': slug});

  Future<void> markAllRead() => _client.rpc('mark_all_notifications_read');
}
