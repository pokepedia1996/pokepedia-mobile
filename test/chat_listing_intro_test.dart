import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/features/chat/repository/chat_repository.dart';
import 'package:pokepedia_mobile/features/chat/repository/models/chat_models.dart';
import 'package:pokepedia_mobile/features/chat/usecase/chat_notifier.dart';
import 'package:pokepedia_mobile/features/notifications/repository/models/notification_model.dart';
import 'package:pokepedia_mobile/features/notifications/repository/notifications_repository.dart';
import 'package:pokepedia_mobile/features/notifications/usecase/notifications_notifier.dart';

/// Sending the first message in a chat opened from a listing has to put the
/// card in the thread — `ensure_direct_room` writes that `listing_context`
/// message, and it is the only thing that does.
const _me = AppUser(id: 'me', email: 'me@example.com');

const _context = ChatListingContext(
  listingOrderId: 9,
  cardId: 42,
  priceIdr: 300000,
  cardName: 'Pansage',
  packSlug: 'sv2a',
  condition: 'NM',
);

const _room = ChatRoom(
  id: 7,
  slug: 'room-a',
  title: 'Toko Ash',
  otherUserId: 'seller',
);

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

class _FakeNotifications implements NotificationsRepository {
  @override
  Future<List<NotificationModel>> fetchNotifications({int limit = 50}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeChat implements ChatRepository {
  _FakeChat({required this.roomExists});

  final bool roomExists;

  /// Listing ids `ensure_direct_room` was called with.
  final ensured = <int?>[];
  int _nextId = 100;

  /// What the room holds server-side. The context message lands here when
  /// the RPC is called with a listing.
  final List<ChatMessage> stored = [];

  ChatMessage _message(
    int id, {
    ChatListingContext? listing,
    String text = '',
  }) => ChatMessage(
    id: id,
    senderId: listing == null ? 'me' : 'seller',
    fromMe: listing == null,
    text: text,
    createdAt: DateTime(2026, 9, 12, 15, id),
    kind: listing == null ? 'text' : 'listing_context',
    listingContext: listing,
  );

  @override
  Future<ChatRoom?> fetchRoom(String slug) async => roomExists ? _room : null;

  @override
  Future<List<ChatMessage>> fetchMessages(
    int roomId, {
    int limit = 40,
    ChatMessageCursor? before,
    String table = 'chat_messages',
  }) async => [...stored];

  @override
  Future<({String? roomSlug, ChatListingContext? context})> fetchListingChat(
    int listingId,
  ) async => (roomSlug: roomExists ? 'room-a' : null, context: _context);

  @override
  Future<ChatRoom> ensureDirectRoom({
    required String otherUserId,
    int? listingId,
    required String title,
  }) async {
    ensured.add(listingId);
    if (listingId != null) {
      // Deduped per listing, as the RPC does.
      final already = stored.any(
        (m) => m.listingContext?.listingOrderId == listingId,
      );
      if (!already) stored.add(_message(_nextId++, listing: _context));
    }
    return _room;
  }

  @override
  Future<ChatMessage> sendMessage({
    required int roomId,
    required String text,
    ChatMediaUpload? media,
    String table = 'chat_messages',
  }) async {
    final sent = _message(_nextId++, text: text);
    stored.add(sent);
    return sent;
  }

  @override
  Future<void> markRead(int roomId, int lastMessageId) async {}

  @override
  RealtimeChannel subscribeToRoom(
    int roomId,
    void Function(ChatMessage message) onMessage, {
    String table = 'chat_messages',
  }) => _FakeChannel();

  @override
  Future<void> unsubscribe(RealtimeChannel channel) async {}

  @override
  Future<int?> fetchOthersReadCursor(int roomId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// The notifier only holds this and hands it back to `unsubscribe`.
class _FakeChannel implements RealtimeChannel {
  @override
  dynamic noSuchMethod(Invocation invocation) => this;
}

Future<ChatThreadState> _sendFirstMessage({
  required bool roomExists,
  required _FakeChat chat,
}) async {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      chatRepositoryProvider.overrideWithValue(chat),
      notificationsRepositoryProvider.overrideWithValue(_FakeNotifications()),
    ],
  );
  addTearDown(container.dispose);

  final arg = (
    slug: roomExists ? 'room-a' : null,
    otherUserId: roomExists ? null : 'seller',
    listingId: 9,
    title: 'Toko Ash',
  );

  // Auth first: the page watches it, so by the time a message can be sent
  // it has resolved. Read cold inside `send` it would still be loading.
  container.listen(authProvider, (_, __) {}, fireImmediately: true);
  for (var i = 0; i < 5; i++) {
    await container.pump();
    await Future<void>.delayed(Duration.zero);
  }

  container.listen(chatThreadProvider(arg), (_, __) {}, fireImmediately: true);
  for (var i = 0; i < 10; i++) {
    await container.pump();
    await Future<void>.delayed(Duration.zero);
  }

  await container.read(chatThreadProvider(arg).notifier).send('halo');
  for (var i = 0; i < 10; i++) {
    await container.pump();
    await Future<void>.delayed(Duration.zero);
  }
  return container.read(chatThreadProvider(arg)).value!;
}

Future<ChatThreadState> _open({
  required bool roomExists,
  required _FakeChat chat,
  int? listingId = 9,
}) async {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      chatRepositoryProvider.overrideWithValue(chat),
      notificationsRepositoryProvider.overrideWithValue(_FakeNotifications()),
    ],
  );
  addTearDown(container.dispose);

  final arg = (
    slug: roomExists ? 'room-a' : null,
    otherUserId: roomExists ? null : 'seller',
    listingId: listingId,
    title: 'Toko Ash',
  );
  container.listen(chatThreadProvider(arg), (_, __) {}, fireImmediately: true);
  for (var i = 0; i < 10; i++) {
    await container.pump();
    await Future<void>.delayed(Duration.zero);
  }
  return container.read(chatThreadProvider(arg)).value!;
}

void main() {
  test('an existing room opened from a listing pins that listing', () async {
    // Nothing has been said about this listing yet, so the pin comes from
    // the payload `chat_about_listing` hands back.
    final state = await _open(
      roomExists: true,
      chat: _FakeChat(roomExists: true),
    );

    expect(state.openedListingId, 9);
    expect(state.pinnedListing?.listingOrderId, 9);
  });

  test('reached any other way, nothing is pinned', () async {
    final chat = _FakeChat(roomExists: true);
    final state = await _open(roomExists: true, chat: chat, listingId: null);

    expect(state.pinnedListing, isNull);
  });

  test('a new conversation is introduced by the listing card', () async {
    final chat = _FakeChat(roomExists: false);
    final state = await _sendFirstMessage(roomExists: false, chat: chat);

    expect(chat.ensured, [9]);
    expect(
      state.messages.any((m) => m.listingContext?.listingOrderId == 9),
      isTrue,
      reason: 'the card the conversation is about is in the thread',
    );
  });

  test('an existing conversation gets the card the first time too', () async {
    // The room already exists, so nothing had attached this listing to it —
    // the card never appeared, however many times it was opened.
    final chat = _FakeChat(roomExists: true);
    final state = await _sendFirstMessage(roomExists: true, chat: chat);

    expect(chat.ensured, [9]);
    expect(
      state.messages.any((m) => m.listingContext?.listingOrderId == 9),
      isTrue,
    );
    // And the pinned banner stops being a preview, since the thread now
    // carries the card itself.
    expect(state.previewContext, isNull);
  });
}
