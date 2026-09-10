import '../../../../core/utils/formatters.dart';

/// One conversation in the inbox — a row of `get_chat_room_summaries`.
class ChatThread {
  const ChatThread({
    required this.roomId,
    required this.slug,
    required this.unread,
    this.roomType = 'direct',
    this.participantCount = 2,
    this.otherUserId,
    this.otherUsername,
    this.otherStoreName,
    this.otherAvatarUrl,
    this.lastMessage,
    this.lastMessageAt,
    this.lastMessageKind,
    this.lastMessageMediaType,
    this.sortAt,
  });

  factory ChatThread.fromSummary(Map<String, dynamic> row) {
    return ChatThread(
      roomId: (row['room_id'] as num).toInt(),
      slug: row['room_slug'] as String,
      unread: (row['unread_count'] as num?)?.toInt() ?? 0,
      roomType: row['room_type'] as String? ?? 'direct',
      participantCount: (row['participant_count'] as num?)?.toInt() ?? 2,
      otherUserId: row['other_user_id'] as String?,
      otherUsername: row['other_username'] as String?,
      otherStoreName: row['other_store_name'] as String?,
      // The personal avatar first, then the shop's logo — the order
      // `resolveChatParty` resolves `photoUrl` in.
      otherAvatarUrl:
          row['other_avatar_url'] as String? ??
          row['other_store_logo_url'] as String?,
      lastMessage: row['last_message_content'] as String?,
      lastMessageAt: DateTime.tryParse(
        row['last_message_created_at'] as String? ?? '',
      )?.toLocal(),
      lastMessageKind: row['last_message_kind'] as String?,
      lastMessageMediaType: row['last_message_media_type'] as String?,
      sortAt:
          DateTime.tryParse(row['sort_at'] as String? ?? '')?.toLocal() ??
          DateTime.tryParse(
            row['last_message_created_at'] as String? ?? '',
          )?.toLocal(),
    );
  }

  final int roomId;
  final String slug;
  final int unread;

  /// `direct` or `dispute` — a dispute room is named for what it is rather
  /// than for a counterparty.
  final String roomType;
  final int participantCount;

  final String? otherUserId;
  final String? otherUsername;
  final String? otherStoreName;
  final String? otherAvatarUrl;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? lastMessageKind;
  final String? lastMessageMediaType;

  /// What the inbox orders on, and half of the paging cursor.
  final DateTime? sortAt;

  /// No single counterparty — a dispute or group room.
  bool get isGroup => otherUserId == null;

  /// Ports the `displayName` in `conversation-list.tsx`, by way of
  /// `resolveChatParty`: a seller is known by their shop, everyone else by
  /// their username, and a room with no one counterparty by what it is.
  String get displayName {
    if (isGroup) {
      return roomType == 'dispute' ? 'Dispute' : 'Group ($participantCount)';
    }
    final store = otherStoreName?.trim();
    if (store != null && store.isNotEmpty) return store;
    final username = otherUsername;
    if (username != null && username.isNotEmpty) return username;
    return 'Pengguna';
  }

  /// `@username` beside the shop name, shown only when the two differ —
  /// `resolveChatParty`'s `secondaryName`.
  String? get secondaryName {
    final store = otherStoreName?.trim();
    final username = otherUsername;
    if (store == null || store.isEmpty) return null;
    if (username == null || username.isEmpty) return null;
    return '@$username';
  }

  /// `PREVIEW_MAX` in `conversation-list.tsx`.
  static const previewMaxLength = 60;

  /// Ports `formatPreview`. Note that a photo is recognised by its media type
  /// and empty body rather than by `kind`, so an image sent with a caption
  /// previews as the caption.
  String get preview {
    if (lastMessageAt == null) return 'Belum ada pesan';
    if (lastMessageKind == 'order_event') return 'Pesanan baru';
    if (lastMessageKind == 'offer_event') return 'Penawaran';

    final body = lastMessage ?? '';
    // Web tests `startsWith('image/')`, but the value it writes is the bare
    // string 'image' — so its own photo rows fall through to "Pesan". Both
    // forms are accepted here rather than reproducing that.
    final mediaType = lastMessageMediaType;
    if (mediaType != null &&
        (mediaType == 'image' || mediaType.startsWith('image/')) &&
        body.isEmpty) {
      return 'Foto';
    }

    final trimmed = body.trim();
    if (trimmed.isEmpty) return 'Pesan';
    if (trimmed.length <= previewMaxLength) return trimmed;
    return '${trimmed.substring(0, previewMaxLength).trimRight()}…';
  }

  /// True where web puts an icon in front of the preview line.
  bool get previewIsPhoto => preview == 'Foto';
  bool get previewIsOrder =>
      lastMessageKind == 'order_event' || lastMessageKind == 'offer_event';

  String get lastAt =>
      lastMessageAt == null ? '' : formatChatInboxStamp(lastMessageAt!);

  /// The same row with its badge cleared, for a room the user just opened.
  ChatThread withUnreadCleared() => ChatThread(
    roomId: roomId,
    slug: slug,
    unread: 0,
    roomType: roomType,
    participantCount: participantCount,
    otherUserId: otherUserId,
    otherUsername: otherUsername,
    otherStoreName: otherStoreName,
    otherAvatarUrl: otherAvatarUrl,
    lastMessage: lastMessage,
    lastMessageAt: lastMessageAt,
    lastMessageKind: lastMessageKind,
    lastMessageMediaType: lastMessageMediaType,
    sortAt: sortAt,
  );
}

/// The listing a conversation was started about — the `listing_context`
/// payload, mirroring `ListingContextSchema`.
class ChatListingContext {
  const ChatListingContext({
    required this.listingOrderId,
    required this.cardId,
    required this.priceIdr,
    this.cardName,
    this.cardImage,
    this.packSlug,
    this.variantKey,
    this.condition,
  });

  static ChatListingContext? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final listingOrderId = (raw['listing_order_id'] as num?)?.toInt();
    final cardId = (raw['card_id'] as num?)?.toInt();
    if (listingOrderId == null || cardId == null) return null;
    return ChatListingContext(
      listingOrderId: listingOrderId,
      cardId: cardId,
      priceIdr: (raw['price_idr'] as num?)?.toInt() ?? 0,
      cardName: raw['card_name'] as String?,
      cardImage: raw['card_image'] as String?,
      packSlug: raw['pack_slug'] as String?,
      variantKey: raw['variant_key'] as String?,
      condition: raw['condition'] as String?,
    );
  }

  final int listingOrderId;
  final int cardId;
  final int priceIdr;
  final String? cardName;
  final String? cardImage;
  final String? packSlug;
  final String? variantKey;
  final String? condition;
}

/// A step in an order's life, posted into the room — the `order_event`
/// payload, mirroring `OrderEventSchema`.
class ChatOrderEvent {
  const ChatOrderEvent({
    required this.matchSlug,
    required this.event,
    required this.amountIdr,
    required this.quantity,
    this.cardName,
    this.cardImage,
  });

  static ChatOrderEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final matchSlug = raw['match_slug'] as String?;
    if (matchSlug == null || matchSlug.isEmpty) return null;
    return ChatOrderEvent(
      matchSlug: matchSlug,
      event: raw['event'] as String? ?? '',
      amountIdr: (raw['amount_idr'] as num?)?.toInt() ?? 0,
      quantity: (raw['quantity'] as num?)?.toInt() ?? 1,
      cardName: raw['card_name'] as String?,
      cardImage: raw['card_image'] as String?,
    );
  }

  final String matchSlug;
  final String event;
  final int amountIdr;
  final int quantity;
  final String? cardName;
  final String? cardImage;

  /// `EVENT_LABEL` from `order-event-card.tsx`.
  String get label => switch (event) {
    'order_placed' => 'Pesanan Dibuat',
    'paid' => 'Pembayaran Diterima',
    'shipped' => 'Dikirim',
    'delivered' => 'Diterima',
    'completed' => 'Selesai',
    'disputed' => 'Dilaporkan',
    'cancelled' => 'Dibatalkan',
    _ => event,
  };
}

/// An offer changing hands inside the room — the `offer_event` payload,
/// mirroring `OfferEventSchema`.
class ChatOfferEvent {
  const ChatOfferEvent({
    required this.offerSlug,
    required this.event,
    required this.price,
    required this.listingPrice,
    required this.quantity,
    required this.buyerId,
    required this.sellerId,
    this.cardName,
    this.cardImage,
    this.message,
  });

  static ChatOfferEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final offerSlug = raw['offer_slug'] as String?;
    if (offerSlug == null || offerSlug.isEmpty) return null;
    return ChatOfferEvent(
      offerSlug: offerSlug,
      event: raw['event'] as String? ?? '',
      price: (raw['price'] as num?)?.toInt() ?? 0,
      listingPrice: (raw['listing_price'] as num?)?.toInt() ?? 0,
      quantity: (raw['quantity'] as num?)?.toInt() ?? 1,
      buyerId: raw['buyer_id'] as String? ?? '',
      sellerId: raw['seller_id'] as String? ?? '',
      cardName: raw['card_name'] as String?,
      cardImage: raw['card_image'] as String?,
      message: raw['message'] as String?,
    );
  }

  final String offerSlug;
  final String event;
  final int price;
  final int listingPrice;
  final int quantity;
  final String buyerId;
  final String sellerId;
  final String? cardName;
  final String? cardImage;
  final String? message;

  /// `EVENT_LABEL` from `offer-event-card.tsx`.
  String get label => switch (event) {
    'offer' => 'Penawaran Dikirim',
    'counter' => 'Penawaran Balik',
    'accept' => 'Penawaran Diterima',
    'reject' => 'Penawaran Ditolak',
    _ => event,
  };

  /// The listing price is struck through only when the offer is under it.
  bool get showStrike => listingPrice > price;
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
    this.mediaType,
    this.localImagePath,
    this.listingContext,
    this.orderEvent,
    this.offerEvent,
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
      mediaType: row['media_type'] as String?,
      listingContext: ChatListingContext.fromJson(row['listing_context']),
      orderEvent: ChatOrderEvent.fromJson(row['order_event']),
      offerEvent: ChatOfferEvent.fromJson(row['offer_event']),
    );
  }

  final int id;
  final String senderId;
  final bool fromMe;
  final String text;
  final DateTime createdAt;
  final String kind;

  /// What the row stores: a path inside the private `chat-media` bucket, or
  /// a signed URL once the repository has exchanged it for one.
  final String? mediaUrl;

  /// The literal `'image'` on a photo — what web writes and renders on. Older
  /// rows may hold a real mime type instead.
  final String? mediaType;

  /// A picked file still on its way up. The bubble draws this instead of
  /// [mediaUrl] so a photo appears the moment it's sent, as web does with a
  /// blob URL.
  final String? localImagePath;

  final ChatListingContext? listingContext;
  final ChatOrderEvent? orderEvent;
  final ChatOfferEvent? offerEvent;

  /// Shown immediately on send, before the insert comes back.
  final bool pending;

  /// The insert was rejected — the bubble stays, marked, rather than the
  /// message silently disappearing.
  final bool failed;

  /// System-authored rows (`listing_context`, `order_event`, …) are drawn as
  /// their own cards rather than as somebody's speech.
  bool get isEvent => kind != 'text' && kind != 'image';

  /// A photo.
  ///
  /// Keyed on `media_type`, not `kind`: web sends a photo with `kind` left at
  /// its `text` default and `media_type` set to `'image'`, and renders on
  /// that. Reading `kind` here drew every photo web sent as an empty bubble.
  /// The `image/` prefix covers rows that stored a real mime type.
  bool get isImage {
    final type = mediaType;
    if (type == null) return false;
    return type == 'image' || type.startsWith('image/');
  }

  /// A photo whose file is gone — web's "Gambar tidak tersedia lagi".
  bool get imageMissing =>
      isImage && localImagePath == null && (mediaUrl?.isEmpty ?? true);

  String get sentAt => formatClockId(createdAt);

  /// The stamp the event cards show — `toLocaleString("id-ID", …)` on the
  /// web, which is the day, short month and clock.
  String get eventStamp =>
      '${formatShortDateId(createdAt)} ${formatClockId(createdAt)}';

  ChatMessage copyWith({
    int? id,
    String? mediaUrl,
    String? localImagePath,
    bool? pending,
    bool? failed,
  }) => ChatMessage(
    id: id ?? this.id,
    senderId: senderId,
    fromMe: fromMe,
    text: text,
    createdAt: createdAt,
    kind: kind,
    mediaUrl: mediaUrl ?? this.mediaUrl,
    mediaType: mediaType,
    localImagePath: localImagePath ?? this.localImagePath,
    listingContext: listingContext,
    orderEvent: orderEvent,
    offerEvent: offerEvent,
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
    this.roomType = 'direct',
    this.otherUserId,
    this.otherUsername,
    this.otherStoreSlug,
    this.otherAvatarUrl,
  });

  final int id;
  final String slug;
  final String title;

  /// `direct` or `dispute` — which decides the table the messages live in.
  final String roomType;

  final String? otherUserId;

  /// Their handle, shown after the shop name the way web's `secondaryName`
  /// is. Null when [title] is already the handle.
  final String? otherUsername;

  /// What their storefront is addressed by — the shop slug, or the handle
  /// where they have no shop of their own. Null for a dispute room and for
  /// an account with neither.
  final String? otherStoreSlug;

  final String? otherAvatarUrl;

  bool get isDispute => roomType == 'dispute';
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
