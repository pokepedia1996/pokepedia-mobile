import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokepedia_mobile/core/errors/user_message.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/chat/presentation/chat_thread_page.dart';
import 'package:pokepedia_mobile/features/chat/repository/chat_repository.dart';
import 'package:pokepedia_mobile/features/chat/repository/models/chat_models.dart';
import 'package:pokepedia_mobile/features/chat/usecase/chat_notifier.dart';
import 'package:pokepedia_mobile/features/moderation/presentation/blocked_users_page.dart';
import 'package:pokepedia_mobile/features/moderation/presentation/user_safety_menu.dart';
import 'package:pokepedia_mobile/features/moderation/repository/moderation_repository.dart';
import 'package:pokepedia_mobile/features/moderation/usecase/moderation_notifier.dart';

const _me = AppUser(id: 'me', email: 'me@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

/// Records what the screens asked for, standing in for the RPCs and route.
class _FakeModeration implements ModerationRepository {
  _FakeModeration({List<BlockedUser>? blocked, this.roomBlocked = false})
    : blocked = blocked ?? [];

  List<BlockedUser> blocked;
  bool roomBlocked;
  Map<String, Object?>? reported;
  final unblocked = <String>[];

  @override
  Future<void> reportUser({
    required String userId,
    required String reason,
    required UserReportContext context,
    String? details,
    String? roomSlug,
  }) async {
    reported = {
      'userId': userId,
      'reason': reason,
      'context': context.value,
      'details': details,
      'roomSlug': roomSlug,
    };
  }

  @override
  Future<void> blockUser(String userId) async {}

  @override
  Future<void> unblockUser(String userId) async {
    unblocked.add(userId);
    blocked = blocked.where((u) => u.userId != userId).toList();
    roomBlocked = false;
  }

  @override
  Future<List<BlockedUser>> fetchBlockedUsers() async => blocked;

  @override
  Future<Set<String>> fetchBlockedPairIds() async =>
      blocked.map((u) => u.userId).toSet();

  @override
  Future<BlockStatus> blockStatus(String handle) async =>
      const BlockStatus(blockedByMe: false);

  @override
  Future<bool> isRoomBlocked(int roomId) async => roomBlocked;
}

BlockedUser _blockedUser(String id, String username) =>
    BlockedUser(userId: id, username: username, blockedAt: DateTime(2026));

Widget _app(
  Widget home,
  _FakeModeration repo, {
  List<Override> extra = const [],
}) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      moderationRepositoryProvider.overrideWithValue(repo),
      ...extra,
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            // The app watches the session from its root; without that here
            // the auth notifier never builds and the menu reads signed out.
            builder: (_, __) => Consumer(
              builder: (_, ref, __) {
                ref.watch(authProvider);
                return home;
              },
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  group('error copy', () {
    test('RPC tokens read as web rpc-errors.ts', () {
      expect(
        moderationErrorMessage('forbidden:self_block', 'x'),
        'Tidak bisa memblokir diri sendiri.',
      );
      expect(
        moderationErrorMessage('forbidden:self_report', 'x'),
        'Tidak bisa melaporkan diri sendiri.',
      );
      expect(moderationErrorMessage('boom', 'Gagal'), 'Gagal');
    });

    test('a chat refusal shows its own sentence, not the generic one', () {
      // ChatException used to fall through to "Terjadi kesalahan".
      expect(
        userFacingError(
          const ChatException(
            'Kamu tidak dapat berinteraksi dengan pengguna ini.',
          ),
        ),
        'Kamu tidak dapat berinteraksi dengan pengguna ini.',
      );
      expect(userFacingError('blocked'), blockedInteractionMessage);
    });
  });

  testWidgets('reporting sends the reason, details and chat room', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = _FakeModeration();
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: UserSafetyButton(
            userId: 'them',
            username: 'user1',
            reportContext: UserReportContext.chat,
            roomSlug: 'room-a',
          ),
        ),
        repo,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Opsi pengguna'));
    await tester.pumpAndSettle();
    expect(find.text('Blokir pengguna'), findsOneWidget);
    await tester.tap(find.text('Laporkan pengguna'));
    await tester.pumpAndSettle();

    expect(find.text('@user1'), findsOneWidget);
    await tester.tap(find.text('Penipuan'));
    await tester.enterText(
      find.byType(TextField),
      '  minta transfer di luar  ',
    );
    await tester.tap(find.text('Kirim Laporan'));
    await tester.pumpAndSettle();

    expect(repo.reported, {
      'userId': 'them',
      'reason': 'scam',
      'context': 'chat',
      'details': '  minta transfer di luar  ',
      'roomSlug': 'room-a',
    });
    expect(find.text('Laporan terkirim, terima kasih'), findsOneWidget);
  });

  testWidgets('a blocked user offers Buka blokir instead', (tester) async {
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: UserSafetyButton(
            userId: 'them',
            username: 'user1',
            reportContext: UserReportContext.store,
            isBlocked: true,
          ),
        ),
        _FakeModeration(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Opsi pengguna'));
    await tester.pumpAndSettle();

    expect(find.text('Buka blokir'), findsOneWidget);
    expect(find.text('Blokir pengguna'), findsNothing);
  });

  testWidgets('Pengguna diblokir lists blocks and unblocks', (tester) async {
    final repo = _FakeModeration(blocked: [_blockedUser('them', 'user1')]);
    await tester.pumpWidget(_app(const BlockedUsersPage(), repo));
    await tester.pumpAndSettle();

    expect(find.text('@user1'), findsOneWidget);
    await tester.tap(find.text('Buka blokir'));
    await tester.pumpAndSettle();

    expect(repo.unblocked, ['them']);
    expect(find.text('Kamu belum memblokir siapa pun.'), findsOneWidget);
  });

  group('chat', () {
    const room = ChatRoom(
      id: 1,
      slug: 'room-a',
      title: 'Toko User1',
      otherUserId: 'them',
      otherUsername: 'user1',
      otherStoreSlug: 'toko-user1',
    );

    Future<void> pumpChat(WidgetTester tester, _FakeModeration repo) async {
      await tester.pumpWidget(
        _app(
          const ChatThreadPage(slug: 'room-a'),
          repo,
          extra: [
            chatThreadProvider.overrideWith(
              () => _FakeThread(
                const ChatThreadState(title: 'Toko User1', room: room),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a blocked room swaps the composer for the bar', (
      tester,
    ) async {
      final repo = _FakeModeration(
        blocked: [_blockedUser('them', 'user1')],
        roomBlocked: true,
      );
      await pumpChat(tester, repo);

      expect(find.text('Kamu memblokir pengguna ini'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Buka blokir'));
      await tester.pumpAndSettle();
      expect(repo.unblocked, ['them']);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('blocked by the other side reads as no reply possible', (
      tester,
    ) async {
      await pumpChat(tester, _FakeModeration(roomBlocked: true));
      expect(
        find.text('Kamu tidak dapat membalas percakapan ini'),
        findsOneWidget,
      );
    });

    testWidgets('an open room keeps the composer and the menu', (tester) async {
      await pumpChat(tester, _FakeModeration());
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('Opsi pengguna'), findsOneWidget);
    });
  });
}

class _FakeThread extends ChatThreadNotifier {
  _FakeThread(this.value);

  final ChatThreadState value;

  @override
  Future<ChatThreadState> build(ChatThreadArg arg) async => value;
}
