import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/utils/chat_image.dart';
import 'models/chat_models.dart';

/// Where the next page of rooms resumes from — `get_chat_room_summaries`
/// pages on `(sort_at, room_id)`.
class ChatRoomCursor {
  const ChatRoomCursor({required this.sortAt, required this.roomId});

  final DateTime sortAt;
  final int roomId;
}

/// Where a page of older messages should resume from — `(created_at, id)`,
/// the pair the query orders on.
class ChatMessageCursor {
  const ChatMessageCursor({required this.createdAt, required this.id});

  final DateTime createdAt;
  final int id;
}

/// A photo already in the bucket, waiting to be named by a message row.
class ChatMediaUpload {
  const ChatMediaUpload({required this.path, required this.metadata});

  /// The object's path inside `chat-media` — what `media_url` stores.
  final String path;
  final Map<String, dynamic> metadata;
}

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

  /// Matches the select in web's `fetchChatMessages`. The event columns carry
  /// what a `listing_context` / `order_event` / `offer_event` row is actually
  /// about; without them those messages arrive as blank text.
  static const _messageColumns =
      'id, room_id, sender_id, content, created_at, kind, media_url, '
      'media_type, media_metadata, order_event, listing_context, offer_event';

  /// The same list minus `offer_event`, which `dispute_chat_messages` doesn't
  /// have — there are no offers inside a dispute. Web passes its one column
  /// list to both tables, which PostgREST rejects on this one.
  static const _disputeMessageColumns =
      'id, room_id, sender_id, content, created_at, kind, media_url, '
      'media_type, media_metadata, order_event, listing_context';

  /// The table behind a room, which is decided by its type.
  static const directTable = 'chat_messages';
  static const disputeTable = 'dispute_chat_messages';

  static String _columnsFor(String table) =>
      table == disputeTable ? _disputeMessageColumns : _messageColumns;

  /// `MESSAGES_PER_PAGE` in `features/chat/api/index.ts`.
  static const messagesPerPage = 50;

  /// `CHAT_ROOMS_PER_PAGE`.
  static const roomsPerPage = 25;

  /// `MAX_MESSAGE_LENGTH` — the same ceiling web rejects a send at.
  static const maxMessageLength = 2000;

  /// Chat images live in a private bucket, so a stored path is worthless to
  /// the client until it's exchanged for a signed URL.
  static const _mediaBucket = 'chat-media';
  static const _signedUrlTtl = 60 * 60;

  /// `UPLOAD_ATTEMPTS` / `UPLOAD_TIMEOUT_MS`.
  static const _uploadAttempts = 2;
  static const _uploadTimeout = Duration(seconds: 30);

  /// The inbox. Rooms with no real message yet are filtered out server-side,
  /// so a "Hubungi" that was never followed through doesn't show up here.
  Future<List<ChatThread>> fetchThreads({
    int limit = roomsPerPage,
    ChatRoomCursor? after,
  }) async {
    if (_uid == null) return const [];
    final params = <String, dynamic>{
      'p_limit': limit,
      if (after != null) ...{
        'p_cursor_sort_at': after.sortAt.toUtc().toIso8601String(),
        'p_cursor_room_id': after.roomId,
      },
    };

    List rows;
    try {
      rows =
          await _client.rpc('get_chat_room_summaries', params: params) as List;
    } catch (_) {
      // One retry after a beat, as web does — a transient Kong/PostgREST 502
      // during startup shouldn't read as an empty inbox.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      rows =
          await _client.rpc('get_chat_room_summaries', params: params) as List;
    }

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
        .select('id, slug, buyer_id, seller_id, room_type')
        .eq('slug', slug)
        .maybeSingle();
    if (row == null) return null;

    final buyerId = row['buyer_id'] as String?;
    final sellerId = row['seller_id'] as String?;
    final otherId = buyerId == me ? sellerId : buyerId;
    final roomType = row['room_type'] as String? ?? 'direct';

    final other = otherId == null ? null : await _identity(otherId);

    return ChatRoom(
      id: (row['id'] as num).toInt(),
      slug: row['slug'] as String,
      // A dispute is named for what it is: both sides are already in it, so
      // titling it after "the other person" would be arbitrary.
      title: roomType == 'dispute' ? 'Dispute' : other?.name ?? 'Percakapan',
      roomType: roomType,
      otherUserId: otherId,
      otherUsername: other?.username,
      otherAvatarUrl: other?.avatarUrl,
    );
  }

  /// How the other party shows in the bar: their shop where they sell, their
  /// username otherwise, with the matching picture.
  ///
  /// Via `get_store_identities` rather than reading `seller_profiles`: that
  /// table is self-select only, so a direct read would come back empty for
  /// everyone but yourself.
  Future<({String name, String? username, String? avatarUrl})> _identity(
    String userId,
  ) async {
    String? storeName;
    String? logoUrl;
    try {
      final identities =
          await _client.rpc(
                'get_store_identities',
                params: {
                  'p_user_ids': [userId],
                },
              )
              as List;
      if (identities.isNotEmpty) {
        final row = identities.first as Map<String, dynamic>;
        storeName = row['store_name'] as String?;
        logoUrl = row['store_logo_url'] as String?;
      }
    } on PostgrestException {
      // Someone with no storefront just shows as their username.
    }

    final profile = await _client
        .from('profiles')
        .select('username, avatar_url')
        .eq('id', userId)
        .maybeSingle();

    final username = profile?['username'] as String?;
    return (
      name: storeName != null && storeName.isNotEmpty
          ? storeName
          : username ?? 'Pengguna',
      // `resolveChatParty`'s `secondaryName`: the handle behind the shop
      // name, and nothing when the shop name *is* the handle.
      username: storeName != null && storeName.isNotEmpty ? username : null,
      // Avatar before logo, the order `resolveChatParty` resolves `photoUrl`.
      avatarUrl: profile?['avatar_url'] as String? ?? logoUrl,
    );
  }

  /// Oldest-first, which is the order the thread renders in.
  ///
  /// Ordered by `created_at` then `id`, the pair web pages on, so the newest
  /// [limit] rows here are the same rows it would have taken.
  Future<List<ChatMessage>> fetchMessages(
    int roomId, {
    int limit = messagesPerPage,
    ChatMessageCursor? before,
    String table = 'chat_messages',
  }) async {
    final me = _uid;
    var query = _client
        .from(table)
        .select(_columnsFor(table))
        .eq('room_id', roomId)
        .isFilter('deleted_at', null);

    if (before != null) {
      // Keyset rather than an offset: an insert while the user is reading
      // would shift every later page by one. The same `or` web pages with.
      final stamp = before.createdAt.toUtc().toIso8601String();
      query = query.or(
        'created_at.lt.$stamp,'
        'and(created_at.eq.$stamp,id.lt.${before.id})',
      );
    }

    final rows =
        await query
                .order('created_at', ascending: false)
                .order('id', ascending: false)
                .limit(limit)
            as List;
    final messages = rows.reversed
        .map((r) => ChatMessage.fromRow(r as Map<String, dynamic>, myId: me))
        .toList();
    return signMedia(messages);
  }

  /// Swaps every stored media path for a signed URL, in one round trip.
  ///
  /// The `chat-media` bucket is private, so an unsigned path renders as a
  /// broken image. A message whose URL can't be signed comes back with none
  /// rather than a link that will 404 — the same fallback web takes.
  Future<List<ChatMessage>> signMedia(List<ChatMessage> messages) async {
    final indexesByPath = <String, List<int>>{};
    for (var i = 0; i < messages.length; i++) {
      final path = extractMediaPath(messages[i].mediaUrl);
      if (path == null) continue;
      indexesByPath.putIfAbsent(path, () => []).add(i);
    }
    if (indexesByPath.isEmpty) return messages;

    final signed = <String, String>{};
    try {
      final results = await _client.storage
          .from(_mediaBucket)
          .createSignedUrlsResult(indexesByPath.keys.toList(), _signedUrlTtl);
      // The result form rather than `createSignedUrls`: that one drops paths
      // it couldn't sign, which would leave a deleted image indistinguishable
      // from one that simply wasn't in the batch.
      for (final result in results) {
        if (result case SignedUrlSuccess(:final path, :final signedUrl)) {
          signed[path] = signedUrl;
        }
      }
    } catch (_) {
      // Fall through: every media message loses its URL below.
    }

    final next = [...messages];
    for (final entry in indexesByPath.entries) {
      for (final i in entry.value) {
        next[i] = next[i].copyWith(mediaUrl: signed[entry.key]);
      }
    }
    return next;
  }

  /// One path's signed URL, for a message arriving over the socket rather
  /// than through a fetch that could batch it.
  Future<String?> signOne(String? stored) async {
    final path = extractMediaPath(stored);
    if (path == null) return null;
    try {
      return await _client.storage
          .from(_mediaBucket)
          .createSignedUrl(path, _signedUrlTtl);
    } catch (_) {
      return null;
    }
  }

  /// Ports `extractChatMediaPath`. Rows hold a bare path, but older ones hold
  /// a full URL — the `://` guard is what lets both resolve.
  static String? extractMediaPath(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    if (!stored.contains('://')) return stored;
    final match = RegExp(r'/chat-media/(.+?)(?:\?.*)?$').firstMatch(stored);
    return match?.group(1);
  }

  Future<ChatMessage> sendMessage({
    required int roomId,
    required String text,
    ChatMediaUpload? media,
    String table = directTable,
  }) async {
    final me = _uid;
    if (me == null) {
      throw const ChatException('Masuk dulu untuk mengirim pesan');
    }
    if (text.isEmpty && media == null) {
      throw const ChatException('Pesan kosong');
    }
    if (text.length > maxMessageLength) {
      throw const ChatException('Pesan terlalu panjang');
    }

    final row = await _client
        .from(table)
        .insert({
          'room_id': roomId,
          'sender_id': me,
          'content': text,
          // `kind` stays `text` on a photo, and `media_type` is the literal
          // 'image'. That's what web writes, and what its renderer keys on —
          // a row with `kind: 'image'` would draw as an empty bubble there.
          'kind': 'text',
          if (media != null) ...{
            'media_url': media.path,
            'media_type': 'image',
            'media_metadata': media.metadata,
          },
        })
        .select(_columnsFor(table))
        .single();
    return ChatMessage.fromRow(row, myId: me);
  }

  /// Compresses and uploads a picked photo, returning the storage path the
  /// message row should carry.
  ///
  /// The path is `{uid}/{roomId}/{name}` because `chat_media_insert_own_room`
  /// requires exactly that: the first segment must be the caller's id and the
  /// second a room they participate in. A room therefore has to exist before
  /// its first photo can be uploaded, which is why the caller creates one
  /// first on a conversation that hasn't started yet.
  Future<({ChatMediaUpload? media, String? error})> uploadMedia({
    required int roomId,
    required File file,
  }) async {
    final me = _uid;
    if (me == null) {
      return (media: null, error: 'Masuk dulu untuk mengirim pesan');
    }

    final Uint8List original;
    try {
      original = await file.readAsBytes();
    } catch (_) {
      return (media: null, error: 'Gagal membaca foto');
    }

    final mimeType = sniffImageMime(original);
    if (mimeType == null || !chatAllowedImageTypes.contains(mimeType)) {
      return (media: null, error: 'Format tidak didukung');
    }
    if (original.length > chatMaxImageBytes) {
      return (media: null, error: 'File terlalu besar (maks 10MB)');
    }

    // Off the UI isolate: decoding and re-encoding a 12MP photo drops frames.
    final compressed = await compute(
      compressChatImage,
      ChatImageInput(bytes: original, mimeType: mimeType),
    );
    if (compressed == null) {
      return (media: null, error: 'Gagal memproses foto, coba foto lain');
    }

    final path = '$me/$roomId/${_mediaFileName(compressed.mimeType)}';
    final failure = await _uploadWithRetry(
      path: path,
      bytes: compressed.bytes,
      contentType: compressed.mimeType,
    );
    if (failure != null) {
      return (media: null, error: 'Gagal mengunggah gambar');
    }

    return (
      media: ChatMediaUpload(path: path, metadata: compressed.metadata),
      error: null,
    );
  }

  /// Two attempts with a timeout each, as `uploadWithRetry` does — a chat
  /// photo on a phone's connection is exactly where one flaky attempt is
  /// worth retrying rather than surfacing.
  Future<Object?> _uploadWithRetry({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < _uploadAttempts; attempt++) {
      try {
        await _client.storage
            .from(_mediaBucket)
            .uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: contentType, upsert: true),
            )
            .timeout(_uploadTimeout);
        return null;
      } catch (error) {
        lastError = error;
      }
    }
    return lastError;
  }

  /// `crypto.randomUUID()` stands in for nothing here — the name only has to
  /// not collide inside one user's room folder.
  String _mediaFileName(String mimeType) {
    final random = Random.secure();
    final hex = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '$hex.${_extForMime(mimeType)}';
  }

  static String _extForMime(String mime) => switch (mime) {
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    _ => 'jpg',
  };

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

  /// How far every *other* participant has read, as the lowest cursor among
  /// them — web's `isReadByOthers`, which only calls a message read once
  /// everyone else has passed it.
  ///
  /// Null when the room has nobody else in it yet, which is different from
  /// "nobody has read anything": one draws no tick state at all, the other
  /// draws an unread one.
  Future<int?> fetchOthersReadCursor(int roomId) async {
    final me = _uid;
    if (me == null) return null;

    final rows =
        await _client
                .from('chat_room_participants')
                .select('user_id, last_read_message_id')
                .eq('room_id', roomId)
            as List;

    int? lowest;
    for (final row in rows.cast<Map<String, dynamic>>()) {
      if ((row['user_id'] as String?) == me) continue;
      final cursor = (row['last_read_message_id'] as num?)?.toInt() ?? 0;
      if (lowest == null || cursor < lowest) lowest = cursor;
    }
    return lowest;
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

  /// Anything that could change the inbox: a new message in any room the
  /// caller can see, and their own read cursor moving.
  ///
  /// The channel name carries a unique suffix for the same reason web's
  /// carries `useId()` — two subscriptions sharing a name crash with "cannot
  /// add postgres_changes after subscribe".
  RealtimeChannel subscribeToInbox(void Function() onChange) {
    final me = _uid;
    return _client
        .channel('inbox-$me-${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_room_participants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: me,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  /// Live inserts for one room. `chat_messages` is in the realtime
  /// publication, so this is a straight postgres_changes subscription.
  RealtimeChannel subscribeToRoom(
    int roomId,
    void Function(ChatMessage message) onMessage, {
    String table = directTable,
  }) {
    final me = _uid;
    return _client
        // Suffixed so two subscriptions never share a channel name — the
        // "cannot add postgres_changes after subscribe" crash web hit when
        // its hook mounted twice.
        .channel('chat-room-$roomId-${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: table,
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
