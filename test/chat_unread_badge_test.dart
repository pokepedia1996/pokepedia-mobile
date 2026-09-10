import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/features/chat/repository/chat_repository.dart';
import 'package:pokepedia_mobile/features/chat/repository/models/chat_models.dart';
import 'package:pokepedia_mobile/features/chat/usecase/chat_notifier.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The count behind the "Pesan" badge on Akun's quick actions.
///
/// It reads zero in three different situations that look identical on
/// screen — nothing unread, the inbox still loading, and the inbox failing —
/// so the arithmetic is worth pinning down separately from the fetch.
const _user = AppUser(id: 'me', email: 'me@example.com');

ChatThread _thread({required int roomId, required int unread}) => ChatThread(
  roomId: roomId,
  slug: 'room-$roomId',
  unread: unread,
  lastMessage: 'Halo',
  lastMessageAt: DateTime(2026, 9, 7),
);

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _user;
}

class _FakeChatRepository implements ChatRepository {
  _FakeChatRepository(this.threads, {this.failFetch = false});

  List<ChatThread> threads;
  bool failFetch;
  int subscriptions = 0;
  void Function()? onChange;

  @override
  Future<List<ChatThread>> fetchThreads({
    int limit = ChatRepository.roomsPerPage,
    ChatRoomCursor? after,
  }) async {
    if (failFetch) throw Exception('502');
    return threads;
  }

  @override
  RealtimeChannel subscribeToInbox(void Function() onChange) {
    subscriptions++;
    this.onChange = onChange;
    // The notifier only ever holds this and hands it back to `unsubscribe`.
    return _FakeChannel();
  }

  @override
  Future<void> unsubscribe(RealtimeChannel channel) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeChannel implements RealtimeChannel {
  @override
  dynamic noSuchMethod(Invocation invocation) => this;
}

Future<({ProviderContainer container, _FakeChatRepository repository})> _open(
  _FakeChatRepository repository,
) async {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      chatRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  container.listen(chatUnreadCountProvider, (_, __) {}, fireImmediately: true);
  for (var i = 0; i < 8; i++) {
    await container.pump();
    await Future<void>.delayed(Duration.zero);
  }
  return (container: container, repository: repository);
}

void main() {
  test('the badge counts every unread message across rooms', () async {
    final open = await _open(
      _FakeChatRepository([
        _thread(roomId: 1, unread: 3),
        _thread(roomId: 2, unread: 1),
        _thread(roomId: 3, unread: 0),
      ]),
    );

    expect(open.container.read(chatUnreadCountProvider), 4);
  });

  test('reading a room clears its share without a refetch', () async {
    final open = await _open(
      _FakeChatRepository([
        _thread(roomId: 1, unread: 3),
        _thread(roomId: 2, unread: 1),
      ]),
    );

    open.container.read(chatThreadsProvider.notifier).markRoomRead(1);

    expect(open.container.read(chatUnreadCountProvider), 1);
  });

  test('a failed first fetch still leaves the inbox subscribed', () async {
    // This is what made the badge stay empty for a whole session: the
    // subscription used to be set up after the fetch, so a transient failure
    // left the keep-alive provider in an error state with nothing that could
    // ever refresh it.
    final repository = _FakeChatRepository([], failFetch: true);
    final open = await _open(repository);

    expect(open.container.read(chatUnreadCountProvider), 0);
    expect(repository.subscriptions, 1);

    // A message arrives; the inbox is reachable again.
    repository
      ..failFetch = false
      ..threads = [_thread(roomId: 1, unread: 2)];
    repository.onChange!();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await open.container.pump();

    expect(open.container.read(chatUnreadCountProvider), 2);
  });
}
