import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../notifications/usecase/notifications_notifier.dart';
import '../repository/chat_repository.dart';
import '../repository/models/chat_models.dart';

final chatRepositoryProvider = Provider(
  (ref) => ChatRepository(ref.read(supabaseClientProvider)),
);

/// The inbox. Keyed off the signed-in user so signing out empties it and
/// signing in refetches rather than showing the previous account's rooms.
///
/// Subscribes while it's alive: a message landing in any visible room, or
/// this user's read cursor moving, refreshes the list — the same two triggers
/// web's `useChatRooms` listens on, with its 400ms debounce so a burst of
/// inserts costs one refetch.
class ChatThreadsNotifier extends AsyncNotifier<List<ChatThread>> {
  static const _debounce = Duration(milliseconds: 400);

  RealtimeChannel? _channel;
  Timer? _timer;
  bool _loadingMore = false;
  bool _hasMore = false;

  bool get hasMore => _hasMore;
  bool get loadingMore => _loadingMore;

  @override
  Future<List<ChatThread>> build() async {
    final user = ref.watch(authProvider).valueOrNull;
    // Held rather than read again inside `onDispose`: when the whole
    // container goes down, the repository provider may already be gone by
    // the time this runs, and reading it there throws.
    final repo = ref.read(chatRepositoryProvider);

    ref.onDispose(() {
      _timer?.cancel();
      final channel = _channel;
      if (channel != null) repo.unsubscribe(channel);
    });

    if (user == null) {
      _hasMore = false;
      return const [];
    }

    // Subscribed *before* the first fetch, not after it. `fetchThreads`
    // throws on a transient PostgREST failure (the one its own retry didn't
    // catch), and this provider is keep-alive: with the subscription set up
    // afterwards, that first failure left no channel, nothing to refetch on,
    // and an error state that reads as an unread count of zero for the rest
    // of the session — a badge that never appears again until a restart.
    // Subscribing first means the next message repopulates it.
    _channel ??= repo.subscribeToInbox(_scheduleRefresh);
    final threads = await repo.fetchThreads();
    _hasMore = threads.length >= ChatRepository.roomsPerPage;
    return threads;
  }

  void _scheduleRefresh() {
    if (_timer?.isActive ?? false) return;
    _timer = Timer(_debounce, () async {
      final repo = ref.read(chatRepositoryProvider);
      try {
        final threads = await repo.fetchThreads();
        _hasMore = threads.length >= ChatRepository.roomsPerPage;
        state = AsyncData(threads);
      } catch (_) {
        // A dropped refresh leaves the list as it was; the next event or a
        // pull-to-refresh tries again.
      }
    });
  }

  /// Zeroes one room's badge in place, for when the user has just read it.
  ///
  /// A local edit rather than a refetch: invalidating this provider would
  /// dispose the notifier and take its realtime channel down with it, and
  /// the answer is already known. Web does the same through its
  /// `chat:room-read` event.
  void markRoomRead(int roomId) {
    final current = state.valueOrNull;
    if (current == null) return;
    if (!current.any((t) => t.roomId == roomId && t.unread > 0)) return;
    state = AsyncData([
      for (final thread in current)
        if (thread.roomId == roomId && thread.unread > 0)
          thread.withUnreadCleared()
        else
          thread,
    ]);
  }

  /// Appends the next page — the inbox's "scrolled to the bottom" step.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.isEmpty) return;
    if (_loadingMore || !_hasMore) return;

    final last = current.last;
    final sortAt = last.sortAt;
    if (sortAt == null) {
      _hasMore = false;
      return;
    }

    _loadingMore = true;
    try {
      final next = await ref
          .read(chatRepositoryProvider)
          .fetchThreads(
            after: ChatRoomCursor(sortAt: sortAt, roomId: last.roomId),
          );
      final known = {for (final t in current) t.roomId};
      final fresh = next.where((t) => !known.contains(t.roomId)).toList();
      _hasMore = next.length >= ChatRepository.roomsPerPage;
      state = AsyncData([...current, ...fresh]);
    } catch (_) {
      // Leave the list alone; the row that triggered this is still there.
    } finally {
      _loadingMore = false;
    }
  }
}

final chatThreadsProvider =
    AsyncNotifierProvider<ChatThreadsNotifier, List<ChatThread>>(
      ChatThreadsNotifier.new,
    );

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
    this.hasMore = false,
    this.loadingMore = false,
    this.othersReadUpTo,
  });

  final String title;
  final ChatRoom? room;
  final List<ChatMessage> messages;

  /// The slug resolved to nothing we're allowed to see.
  final bool missing;
  final bool sending;

  /// A full page came back last time, so there may be more above.
  final bool hasMore;
  final bool loadingMore;

  /// The newest message id everyone else in the room has read — what turns
  /// your own ticks green. Null in a room with nobody else in it yet.
  final int? othersReadUpTo;

  /// Whether [id] has been read by every other participant.
  bool isReadByOthers(int id) =>
      id > 0 && othersReadUpTo != null && othersReadUpTo! >= id;

  ChatThreadState copyWith({
    String? title,
    ChatRoom? room,
    List<ChatMessage>? messages,
    bool? missing,
    bool? sending,
    bool? hasMore,
    bool? loadingMore,
    int? othersReadUpTo,
  }) => ChatThreadState(
    title: title ?? this.title,
    room: room ?? this.room,
    messages: messages ?? this.messages,
    missing: missing ?? this.missing,
    sending: sending ?? this.sending,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    othersReadUpTo: othersReadUpTo ?? this.othersReadUpTo,
  );
}

class ChatThreadNotifier
    extends FamilyAsyncNotifier<ChatThreadState, ChatThreadArg> {
  RealtimeChannel? _channel;

  /// Optimistic bubbles get descending negative ids so they sort last and
  /// can never collide with a real row.
  int _nextPendingId = -1;

  /// The newest message id already reported as read.
  int _readUpTo = 0;

  /// Which table this room's messages live in. A dispute keeps its own.
  String _messageTable = ChatRepository.directTable;

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

    _messageTable = room.isDispute
        ? ChatRepository.disputeTable
        : ChatRepository.directTable;

    // Reading the thread reads what the notifications were about. Fired here
    // rather than inside `_markRead` so it still runs when the read cursor
    // is already up to date — rows can outlive the cursor when the thread
    // was read on another device.
    if (!room.isDispute) {
      unawaited(
        ref.read(notificationsProvider.notifier).markChatRoomRead(room.slug),
      );
    }

    final messages = await _repo.fetchMessages(room.id, table: _messageTable);
    final othersReadUpTo = await _repo.fetchOthersReadCursor(room.id);
    _listen(room.id);
    // The room is passed in rather than read back off `state`, which isn't
    // assigned until this future completes — reading it here found nothing
    // and quietly skipped the read cursor, so opening a conversation left
    // its unread badge sitting on the inbox.
    _markRead(room, messages);
    return ChatThreadState(
      title: room.title,
      room: room,
      messages: messages,
      // A short first page means the room's whole history is already here.
      hasMore: messages.length >= ChatRepository.messagesPerPage,
      othersReadUpTo: othersReadUpTo,
    );
  }

  /// Pulls the page above what's loaded — the thread's "scrolled to the top"
  /// step, keyed off the oldest real message on screen.
  Future<void> loadOlder() async {
    final current = state.valueOrNull;
    final room = current?.room;
    if (current == null || room == null) return;
    if (current.loadingMore || !current.hasMore) return;

    final oldest = current.messages.where((m) => m.id > 0).firstOrNull;
    if (oldest == null) return;

    state = AsyncData(current.copyWith(loadingMore: true));
    final older = await _repo.fetchMessages(
      room.id,
      before: ChatMessageCursor(createdAt: oldest.createdAt, id: oldest.id),
      table: _messageTable,
    );

    final latest = state.valueOrNull;
    if (latest == null) return;
    // Ids already on screen are skipped rather than trusted to be disjoint:
    // a realtime insert can land mid-fetch.
    final known = {for (final m in latest.messages) m.id};
    final fresh = older.where((m) => !known.contains(m.id));
    state = AsyncData(
      latest.copyWith(
        messages: [...fresh, ...latest.messages]
          ..sort((a, b) => a.id.compareTo(b.id)),
        hasMore: older.length >= ChatRepository.messagesPerPage,
        loadingMore: false,
      ),
    );
  }

  void _listen(int roomId) {
    _channel ??= _repo.subscribeToRoom(
      roomId,
      _onIncoming,
      table: _messageTable,
    );
  }

  Future<void> _onIncoming(ChatMessage message) async {
    final current = state.valueOrNull;
    if (current == null) return;
    // The sender sees their own insert twice — once as the awaited row, once
    // over the socket.
    if (current.messages.any((m) => m.id == message.id)) return;

    // A socket delivery carries the raw storage path, which is useless
    // against a private bucket. Fetches sign in a batch; this one is on its
    // own, so it gets signed here.
    var resolved = message;
    if (message.isImage && message.mediaUrl != null) {
      resolved = message.copyWith(
        mediaUrl: await _repo.signOne(message.mediaUrl),
      );
    }

    final latest = state.valueOrNull;
    if (latest == null) return;
    if (latest.messages.any((m) => m.id == resolved.id)) return;

    final merged = [...latest.messages, resolved]
      ..sort((a, b) => a.id.compareTo(b.id));
    state = AsyncData(latest.copyWith(messages: merged));
    final room = latest.room;
    if (room == null) return;
    if (!resolved.fromMe) _markRead(room, merged);
    // Someone else being active is the moment their read cursor is most
    // likely to have moved, and the socket carries messages rather than
    // cursors — so the ticks are refreshed off the traffic instead of a
    // second subscription.
    unawaited(_refreshReadCursor(room));
  }

  /// Re-reads how far the others have got, for the ticks on your own
  /// bubbles. Failures are ignored: a stale tick is not worth an error.
  Future<void> _refreshReadCursor(ChatRoom room) async {
    try {
      final cursor = await _repo.fetchOthersReadCursor(room.id);
      final latest = state.valueOrNull;
      if (cursor == null || latest == null) return;
      if (latest.othersReadUpTo == cursor) return;
      state = AsyncData(latest.copyWith(othersReadUpTo: cursor));
    } catch (_) {}
  }

  /// Moves the read cursor to the newest real message, and tells the inbox
  /// so the badge that brought the user here clears.
  ///
  /// [_readUpTo] keeps a lively conversation from writing the cursor and
  /// refetching the inbox for a message already counted as read.
  Future<void> _markRead(ChatRoom room, List<ChatMessage> messages) async {
    var newest = 0;
    for (final message in messages) {
      if (message.id > newest) newest = message.id;
    }
    if (newest <= _readUpTo) return;
    _readUpTo = newest;

    try {
      await _repo.markRead(room.id, newest);
    } catch (_) {
      // A cursor that didn't move is a stale badge, not a broken thread.
      _readUpTo = 0;
      return;
    }
    ref.read(chatThreadsProvider.notifier).markRoomRead(room.id);
  }

  /// Sends [text] and/or [image], creating the room first when this is the
  /// opening message.
  ///
  /// A photo needs the room to exist before it can go anywhere:
  /// `chat_media_insert_own_room` only accepts an object at
  /// `{uid}/{roomId}/…` for a room the caller is in, so the upload can't come
  /// first the way it can on a room that already exists.
  Future<void> send(String text, {File? image}) async {
    final body = text.trim();
    if (body.isEmpty && image == null) return;
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
      // The picked file stands in for the photo until the upload lands, so
      // the bubble is there the moment the user taps send.
      mediaType: image == null ? null : 'image',
      localImagePath: image?.path,
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

      ChatMediaUpload? media;
      if (image != null) {
        final upload = await _repo.uploadMedia(roomId: room.id, file: image);
        if (upload.error != null) throw ChatException(upload.error!);
        media = upload.media;
      }

      final sent = await _repo.sendMessage(
        roomId: room.id,
        text: body,
        media: media,
        table: _messageTable,
      );
      // The row comes back holding the storage path; the bubble needs a
      // signed URL, and keeps drawing the local file until it has one.
      final resolved = media == null
          ? sent
          : sent.copyWith(
              mediaUrl: await _repo.signOne(sent.mediaUrl),
              localImagePath: image?.path,
            );
      _replace(optimistic.id, resolved, room: room);
      _repo.markRead(room.id, sent.id);
      // The inbox's preview and ordering just changed — its own subscription
      // sees this insert and refreshes, so there's nothing to invalidate.
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

  /// Sends a rejected message again.
  ///
  /// The failed bubble is dropped first and the text re-sent, so the retry
  /// takes its place at the end of the thread rather than staying frozen
  /// wherever the original stalled.
  Future<void> retry(ChatMessage message) async {
    if (!message.failed) return;
    final current = state.valueOrNull;
    if (current == null || current.sending) return;

    state = AsyncData(
      current.copyWith(
        messages: current.messages
            .where((m) => m.id != message.id)
            .toList(growable: false),
      ),
    );
    // A failed photo still has its local file, so the retry re-uploads the
    // same picture rather than asking the user to find it again.
    final path = message.localImagePath;
    await send(message.text, image: path == null ? null : File(path));
  }

  /// Drops a failed bubble for good — the way out when the message was never
  /// going to send and the user just wants it gone.
  void discard(ChatMessage message) {
    if (!message.failed) return;
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        messages: current.messages
            .where((m) => m.id != message.id)
            .toList(growable: false),
      ),
    );
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
