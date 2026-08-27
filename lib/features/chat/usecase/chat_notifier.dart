import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../repository/chat_repository.dart';
import '../repository/models/chat_models.dart';

final chatRepositoryProvider = Provider(
  (ref) => ChatRepository(ref.read(supabaseClientProvider)),
);

/// The inbox. Keyed off the signed-in user so signing out empties it and
/// signing in refetches rather than showing the previous account's rooms.
final chatThreadsProvider = FutureProvider<List<ChatThread>>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const <ChatThread>[]);
  return ref.read(chatRepositoryProvider).fetchThreads();
});

/// Unread conversations, for the badge on the Akun row.
final chatUnreadCountProvider = Provider<int>((ref) {
  final threads = ref.watch(chatThreadsProvider).valueOrNull;
  if (threads == null) return 0;
  return threads.fold(0, (sum, t) => sum + t.unread);
});

/// Identifies an open thread: an existing room by [slug], or a conversation
/// that hasn't been started yet, in which case the recipient is carried here
/// until the first message creates the room.
typedef ChatThreadArg = ({
  String? slug,
  String? otherUserId,
  int? listingId,
  String title,
});

class ChatThreadState {
  const ChatThreadState({
    required this.title,
    this.room,
    this.messages = const [],
    this.missing = false,
    this.sending = false,
  });

  final String title;
  final ChatRoom? room;
  final List<ChatMessage> messages;

  /// The slug resolved to nothing we're allowed to see.
  final bool missing;
  final bool sending;

  ChatThreadState copyWith({
    String? title,
    ChatRoom? room,
    List<ChatMessage>? messages,
    bool? missing,
    bool? sending,
  }) => ChatThreadState(
    title: title ?? this.title,
    room: room ?? this.room,
    messages: messages ?? this.messages,
    missing: missing ?? this.missing,
    sending: sending ?? this.sending,
  );
}

class ChatThreadNotifier
    extends FamilyAsyncNotifier<ChatThreadState, ChatThreadArg> {
  RealtimeChannel? _channel;

  /// Optimistic bubbles get descending negative ids so they sort last and
  /// can never collide with a real row.
  int _nextPendingId = -1;

  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  @override
  Future<ChatThreadState> build(ChatThreadArg arg) async {
    ref.onDispose(() {
      final channel = _channel;
      if (channel != null) _repo.unsubscribe(channel);
    });

    final slug = arg.slug;
    if (slug == null) {
      // Nothing said yet — the room appears with the first message.
      return ChatThreadState(title: arg.title);
    }

    final room = await _repo.fetchRoom(slug);
    if (room == null) {
      return ChatThreadState(title: arg.title, missing: true);
    }

    final messages = await _repo.fetchMessages(room.id);
    _listen(room.id);
    _markRead(messages);
    return ChatThreadState(title: room.title, room: room, messages: messages);
  }

  void _listen(int roomId) {
    _channel ??= _repo.subscribeToRoom(roomId, _onIncoming);
  }

  void _onIncoming(ChatMessage message) {
    final current = state.valueOrNull;
    if (current == null) return;
    // The sender sees their own insert twice — once as the awaited row, once
    // over the socket.
    if (current.messages.any((m) => m.id == message.id)) return;

    final merged = [...current.messages, message]
      ..sort((a, b) => a.id.compareTo(b.id));
    state = AsyncData(current.copyWith(messages: merged));
    if (!message.fromMe) _markRead(merged);
  }

  void _markRead(List<ChatMessage> messages) {
    final room = state.valueOrNull?.room ?? _roomOf(messages);
    if (room == null) return;
    final lastReal = messages.where((m) => m.id > 0);
    if (lastReal.isEmpty) return;
    _repo.markRead(room.id, lastReal.last.id);
  }

  ChatRoom? _roomOf(List<ChatMessage> _) => state.valueOrNull?.room;

  /// Sends [text], creating the room first when this is the opening message.
  Future<void> send(String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final current = state.valueOrNull;
    if (current == null || current.sending) return;

    final me = ref.read(authProvider).valueOrNull;
    if (me == null) {
      throw const ChatException('Masuk dulu untuk mengirim pesan');
    }

    final optimistic = ChatMessage(
      id: _nextPendingId--,
      senderId: me.id,
      fromMe: true,
      text: body,
      createdAt: DateTime.now(),
      pending: true,
    );
    state = AsyncData(
      current.copyWith(
        messages: [...current.messages, optimistic],
        sending: true,
      ),
    );

    try {
      var room = current.room;
      if (room == null) {
        final otherUserId = arg.otherUserId;
        if (otherUserId == null) {
          throw const ChatException('Percakapan ini tidak punya penerima');
        }
        room = await _repo.ensureDirectRoom(
          otherUserId: otherUserId,
          listingId: arg.listingId,
          title: arg.title,
        );
        _listen(room.id);
      }

      final sent = await _repo.sendMessage(roomId: room.id, text: body);
      _replace(optimistic.id, sent, room: room);
      _repo.markRead(room.id, sent.id);
      // The inbox's preview and ordering just changed.
      ref.invalidate(chatThreadsProvider);
    } catch (e) {
      _replace(
        optimistic.id,
        optimistic.copyWith(failed: true, pending: false),
      );
      rethrow;
    } finally {
      final latest = state.valueOrNull;
      if (latest != null) state = AsyncData(latest.copyWith(sending: false));
    }
  }

  void _replace(int pendingId, ChatMessage message, {ChatRoom? room}) {
    final current = state.valueOrNull;
    if (current == null) return;
    // Realtime may have delivered the real row before the insert returned.
    final withoutDuplicate = current.messages.where(
      (m) => m.id != pendingId && (m.id != message.id || m.id < 0),
    );
    state = AsyncData(
      current.copyWith(
        room: room ?? current.room,
        messages: [...withoutDuplicate, message]
          ..sort((a, b) => a.id.compareTo(b.id)),
      ),
    );
  }
}

final chatThreadProvider =
    AsyncNotifierProvider.family<
      ChatThreadNotifier,
      ChatThreadState,
      ChatThreadArg
    >(ChatThreadNotifier.new);

/// Opens a conversation with a user, reusing their existing room when there
/// is one. Returns the argument the thread page should be built with.
class ChatOpener {
  const ChatOpener(this._repo);

  final ChatRepository _repo;

  Future<ChatThreadArg> withUser({
    required String otherUserId,
    required String title,
    int? listingId,
  }) async {
    final slug = listingId != null
        ? await _repo.findListingRoomSlug(listingId)
        : await _repo.findDirectRoomSlug(otherUserId);
    return (
      slug: slug,
      otherUserId: otherUserId,
      listingId: listingId,
      title: title,
    );
  }
}

final chatOpenerProvider = Provider(
  (ref) => ChatOpener(ref.read(chatRepositoryProvider)),
);
