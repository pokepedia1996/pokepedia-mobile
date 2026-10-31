import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/features/chat/repository/chat_repository.dart';
import 'package:pokepedia_mobile/features/chat/repository/models/chat_models.dart';
import 'package:pokepedia_mobile/features/chat/usecase/chat_notifier.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The inbox updates itself when a message arrives — for the whole session,
/// not only until the signed-in user's profile finishes loading.
const _bare = AppUser(id: 'me', email: 'me@example.com');
const _withProfile = AppUser(
  id: 'me',
  email: 'me@example.com',
  username: 'mulyana',
  onboarded: true,
);

/// Answers with the bare session user, as the real one does at launch, and
/// fills the profile in when told — the second answer every launch gets.
class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _bare;

  void profileLoaded() => state = const AsyncData(_withProfile);
}

ChatThread _thread(int roomId, String text) => ChatThread(
  roomId: roomId,
  slug: 'room-$roomId',
  unread: 1,
  otherUsername: 'user$roomId',
  lastMessage: text,
  lastMessageAt: DateTime(2026, 10, 24),
);

/// A live channel per subscription. Unsubscribing really cuts it off, as
/// the server does: an event after that reaches nobody.
class _FakeChatRepository implements ChatRepository {
  _FakeChatRepository(this.threads);

  List<ChatThread> threads;
  final _live = <_FakeChannel, void Function()>{};

  int get liveChannels => _live.length;

  /// A message lands somewhere this user can see.
  void deliver() {
    for (final onChange in _live.values.toList()) {
      onChange();
    }
  }

  @override
  Future<List<ChatThread>> fetchThreads({
    int limit = ChatRepository.roomsPerPage,
    ChatRoomCursor? after,
  }) async => threads;

  @override
  RealtimeChannel subscribeToInbox(void Function() onChange) {
    final channel = _FakeChannel();
    _live[channel] = onChange;
    return channel;
  }

  @override
  Future<void> unsubscribe(RealtimeChannel channel) async {
    _live.remove(channel);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeChannel implements RealtimeChannel {
  @override
  dynamic noSuchMethod(Invocation invocation) => this;
}

Future<void> _settle(ProviderContainer container) async {
  for (var i = 0; i < 6; i++) {
    await container.pump();
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('a new message reaches the inbox after the profile loads', () async {
    final repo = _FakeChatRepository([_thread(1, 'halo')]);
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        chatRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    container.listen(chatThreadsProvider, (_, __) {}, fireImmediately: true);
    await _settle(container);
    expect(container.read(chatThreadsProvider).value, hasLength(1));

    // What every launch does a moment after the first answer.
    (container.read(authProvider.notifier) as _FakeAuth).profileLoaded();
    await _settle(container);
    expect(repo.liveChannels, 1, reason: 'still listening');

    // Someone writes.
    repo.threads = [_thread(2, 'gapapa si'), _thread(1, 'halo')];
    repo.deliver();
    // Past the inbox's debounce.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    await _settle(container);

    final threads = container.read(chatThreadsProvider).value!;
    expect(threads.first.preview, 'gapapa si');
  });
}
