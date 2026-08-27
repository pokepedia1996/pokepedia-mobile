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
      'id, type, category, title, body, is_read, action_url, created_at';

  Future<List<NotificationModel>> fetchNotifications({int limit = 50}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    final rows =
        await _client
                .from('notifications')
                .select(_columns)
                .eq('user_id', userId)
                .order('created_at', ascending: false)
                .limit(limit)
            as List;
    return rows
        .map((r) => NotificationModel.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> markRead(int id) =>
      _client.rpc('mark_notification_read', params: {'p_id': id});

  Future<void> markAllRead() => _client.rpc('mark_all_notifications_read');
}
