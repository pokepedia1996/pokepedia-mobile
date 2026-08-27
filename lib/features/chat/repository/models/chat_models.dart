import '../../../../core/utils/formatters.dart';

/// One conversation in the inbox — a row of `get_chat_room_summaries`.
class ChatThread {
  const ChatThread({
    required this.roomId,
    required this.slug,
    required this.unread,
    this.otherUserId,
    this.otherUsername,
    this.otherStoreName,
    this.otherAvatarUrl,
    this.lastMessage,
    this.lastMessageAt,
    this.lastMessageKind,
  });

  factory ChatThread.fromSummary(Map<String, dynamic> row) {
    return ChatThread(
      roomId: (row['room_id'] as num).toInt(),
      slug: row['room_slug'] as String,
      unread: (row['unread_count'] as num?)?.toInt() ?? 0,
      otherUserId: row['other_user_id'] as String?,
      otherUsername: row['other_username'] as String?,
      otherStoreName: row['other_store_name'] as String?,
      otherAvatarUrl:
          row['other_store_logo_url'] as String? ??
          row['other_avatar_url'] as String?,
      lastMessage: row['last_message_content'] as String?,
      lastMessageAt: DateTime.tryParse(
        row['last_message_created_at'] as String? ?? '',
      )?.toLocal(),
      lastMessageKind: row['last_message_kind'] as String?,
    );
  }

  final int roomId;
  final String slug;
  final int unread;
  final String? otherUserId;
  final String? otherUsername;
  final String? otherStoreName;
  final String? otherAvatarUrl;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? lastMessageKind;

  /// A seller is known by their shop; everyone else by their username. Group
  /// rooms have no single other party, hence the last fallback.
  String get displayName {
    final store = otherStoreName;
    if (store != null && store.isNotEmpty) return store;
    final username = otherUsername;
    if (username != null && username.isNotEmpty) return username;
    return 'Percakapan';
  }

  /// The preview line. Non-text messages carry no content of their own, so
  /// they're described instead of shown blank.
  String get preview => switch (lastMessageKind) {
    'image' => '📷 Foto',
    'listing_context' => 'Menanyakan sebuah listing',
    'order_event' => 'Pembaruan pesanan',
    'offer_event' => 'Pembaruan penawaran',
    _ => lastMessage ?? '',
  };

  String get lastAt =>
      lastMessageAt == null ? '' : formatChatStamp(lastMessageAt!);
}

/// A single message in a room.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.fromMe,
    required this.text,
    required this.createdAt,
    this.kind = 'text',
    this.mediaUrl,
    this.pending = false,
    this.failed = false,
  });

  factory ChatMessage.fromRow(Map<String, dynamic> row, {String? myId}) {
    final senderId = row['sender_id'] as String? ?? '';
    return ChatMessage(
      id: (row['id'] as num).toInt(),
      senderId: senderId,
      fromMe: myId != null && senderId == myId,
      text: row['content'] as String? ?? '',
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      kind: row['kind'] as String? ?? 'text',
      mediaUrl: row['media_url'] as String?,
    );
  }

  final int id;
  final String senderId;
  final bool fromMe;
  final String text;
  final DateTime createdAt;
  final String kind;
  final String? mediaUrl;

  /// Shown immediately on send, before the insert comes back.
  final bool pending;

  /// The insert was rejected — the bubble stays, marked, rather than the
  /// message silently disappearing.
  final bool failed;

  /// System-authored rows (`listing_context`, `order_event`, …) are rendered
  /// as centred notes rather than as somebody's speech.
  bool get isEvent => kind != 'text' && kind != 'image';

  String get sentAt => formatClockId(createdAt);

  ChatMessage copyWith({int? id, bool? pending, bool? failed}) => ChatMessage(
    id: id ?? this.id,
    senderId: senderId,
    fromMe: fromMe,
    text: text,
    createdAt: createdAt,
    kind: kind,
    mediaUrl: mediaUrl,
    pending: pending ?? this.pending,
    failed: failed ?? this.failed,
  );
}

/// The room behind an open thread, resolved from its slug.
class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.slug,
    required this.title,
    this.otherUserId,
    this.otherAvatarUrl,
  });

  final int id;
  final String slug;
  final String title;
  final String? otherUserId;
  final String? otherAvatarUrl;
}

/// Who to talk to when no room exists yet.
///
/// Rooms are created lazily, on the first message (`ensure_direct_room`), so
/// "Hubungi penjual" opens a thread that has a recipient but no room — this
/// carries the recipient until something is actually said.
class ChatTarget {
  const ChatTarget({
    required this.otherUserId,
    required this.title,
    this.listingId,
  });

  final String otherUserId;
  final String title;

  /// Attaches the listing card to the room when it is created.
  final int? listingId;
}
