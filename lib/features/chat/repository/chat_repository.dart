import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/chat_models.dart';

/// Raised when a chat action can't be carried out, carrying a message that is
/// safe to show the user.
class ChatException implements Exception {
  const ChatException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Data access for chat, against `chat_rooms` / `chat_room_participants` /
/// `chat_messages`.
///
/// Reads and sends go straight to the tables — RLS already scopes them to
/// rooms the caller participates in (`chat_messages_select`,
/// `chat_messages_insert`) — while room creation goes through
/// `ensure_direct_room`, which owns the lazy get-or-create and its rate limit.
class ChatRepository {
  ChatRepository(this._client);

  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  static const _messageColumns =
      'id, room_id, sender_id, content, created_at, kind, media_url, media_type';

  /// The inbox. Rooms with no real message yet are filtered out server-side,
  /// so a "Hubungi" that was never followed through doesn't show up here.
  Future<List<ChatThread>> fetchThreads({int limit = 30}) async {
    if (_uid == null) return const [];
    final rows =
        await _client.rpc('get_chat_room_summaries', params: {'p_limit': limit})
            as List;
    return rows
        .map((r) => ChatThread.fromSummary(r as Map<String, dynamic>))
        .toList();
  }

  /// Resolves the room behind a thread slug, along with a title for the bar.
  Future<ChatRoom?> fetchRoom(String slug) async {
    final me = _uid;
    if (me == null) return null;

    final row = await _client
        .from('chat_rooms')
        .select('id, slug, buyer_id, seller_id')
        .eq('slug', slug)
        .maybeSingle();
    if (row == null) return null;

    final buyerId = row['buyer_id'] as String?;
    final sellerId = row['seller_id'] as String?;
    final otherId = buyerId == me ? sellerId : buyerId;

    return ChatRoom(
      id: (row['id'] as num).toInt(),
      slug: row['slug'] as String,
      title: otherId == null ? 'Percakapan' : await _displayName(otherId),
      otherUserId: otherId,
    );
  }

  /// Store name where the other party sells, username otherwise.
  ///
  /// Via `get_store_identities` rather than reading `seller_profiles`: that
  /// table is self-select only, so a direct read would come back empty for
  /// everyone but yourself.
  Future<String> _displayName(String userId) async {
    final identities =
        await _client.rpc(
              'get_store_identities',
              params: {
                'p_user_ids': [userId],
              },
            )
            as List;
    if (identities.isNotEmpty) {
      final storeName =
          (identities.first as Map<String, dynamic>)['store_name'] as String?;
      if (storeName != null && storeName.isNotEmpty) return storeName;
    }

    final profile = await _client
        .from('profiles')
        .select('username')
        .eq('id', userId)
        .maybeSingle();
    return (profile?['username'] as String?) ?? 'Pengguna';
  }

  /// Oldest-first, which is the order the thread renders in.
  Future<List<ChatMessage>> fetchMessages(int roomId, {int limit = 100}) async {
    final me = _uid;
    final rows =
        await _client
                .from('chat_messages')
                .select(_messageColumns)
                .eq('room_id', roomId)
                .isFilter('deleted_at', null)
                .order('id', ascending: false)
                .limit(limit)
            as List;
    return rows.reversed
        .map((r) => ChatMessage.fromRow(r as Map<String, dynamic>, myId: me))
        .toList();
  }

  Future<ChatMessage> sendMessage({
    required int roomId,
    required String text,
  }) async {
    final me = _uid;
    if (me == null) {
      throw const ChatException('Masuk dulu untuk mengirim pesan');
    }

    final row = await _client
        .from('chat_messages')
        .insert({
          'room_id': roomId,
          'sender_id': me,
          'content': text,
          'kind': 'text',
        })
        .select(_messageColumns)
        .single();
    return ChatMessage.fromRow(row, myId: me);
  }

  /// Get-or-creates the direct room with [otherUserId], optionally attaching
  /// the listing that started the conversation. Called on the first send.
  Future<ChatRoom> ensureDirectRoom({
    required String otherUserId,
    int? listingId,
    required String title,
  }) async {
    final result =
        await _client.rpc(
              'ensure_direct_room',
              params: {
                'p_other_user_id': otherUserId,
                if (listingId != null) 'p_listing_order_id': listingId,
              },
            )
            as Map<String, dynamic>;

    final error = result['error'] as String?;
    if (error != null) throw ChatException(_roomErrorMessage(error));

    return ChatRoom(
      id: (result['room_id'] as num).toInt(),
      slug: result['room_slug'] as String,
      title: title,
      otherUserId: otherUserId,
    );
  }

  /// The existing direct room with [otherUserId], or null when they've never
  /// spoken — the room is only created once something is actually sent.
  Future<String?> findDirectRoomSlug(String otherUserId) async {
    final result =
        await _client.rpc(
              'resolve_direct_chat_target',
              params: {'p_other_user_id': otherUserId},
            )
            as Map<String, dynamic>;
    if (result['error'] != null) return null;
    return result['room_slug'] as String?;
  }

  /// The room for a conversation about a listing, when one already exists.
  Future<String?> findListingRoomSlug(int listingId) async {
    final result =
        await _client.rpc(
              'chat_about_listing',
              params: {'p_listing_order_id': listingId},
            )
            as Map<String, dynamic>;
    if (result['error'] != null) return null;
    return result['room_slug'] as String?;
  }

  /// Moves this participant's read cursor to [lastMessageId].
  Future<void> markRead(int roomId, int lastMessageId) async {
    final me = _uid;
    if (me == null) return;
    await _client
        .from('chat_room_participants')
        .update({
          'last_read_message_id': lastMessageId,
          'last_read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('room_id', roomId)
        .eq('user_id', me);
  }

  /// Live inserts for one room. `chat_messages` is in the realtime
  /// publication, so this is a straight postgres_changes subscription.
  RealtimeChannel subscribeToRoom(
    int roomId,
    void Function(ChatMessage message) onMessage,
  ) {
    final me = _uid;
    return _client
        .channel('chat-room-$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) =>
              onMessage(ChatMessage.fromRow(payload.newRecord, myId: me)),
        )
        .subscribe();
  }

  Future<void> unsubscribe(RealtimeChannel channel) =>
      _client.removeChannel(channel);

  String _roomErrorMessage(String code) => switch (code) {
    'unauthorized' => 'Masuk dulu untuk mengirim pesan',
    'cannot_chat_self' => 'Tidak bisa mengirim pesan ke diri sendiri',
    'user_not_found' => 'Pengguna tidak ditemukan',
    'rate_limited' =>
      'Terlalu banyak percakapan baru. Coba lagi beberapa saat lagi.',
    _ => 'Gagal membuka percakapan',
  };
}
