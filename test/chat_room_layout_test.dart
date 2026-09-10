import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/chat/presentation/chat_thread_page.dart';
import 'package:pokepedia_mobile/features/chat/repository/models/chat_models.dart';
import 'package:pokepedia_mobile/features/chat/usecase/chat_notifier.dart';

/// The room after it was rebuilt to match the website: a run opens with the
/// sender's avatar and name, every bubble carries its clock, and your own
/// carry read ticks. The layout is nested three deep (row → constrained
/// bubble → text/stamp row), which is exactly the shape that overflows if a
/// long message isn't allowed to shrink.
const _me = AppUser(id: 'me', email: 'me@example.com');

ChatMessage _msg({
  required int id,
  required bool mine,
  String text = 'Halo',
  int minute = 0,
}) => ChatMessage(
  id: id,
  senderId: mine ? 'me' : 'them',
  fromMe: mine,
  text: text,
  createdAt: DateTime(2026, 9, 7, 15, minute),
);

const _room = ChatRoom(
  id: 1,
  slug: 'room-a',
  title: 'Toko User1',
  otherUserId: 'them',
  otherUsername: 'user1',
  otherStoreSlug: 'toko-user1',
);

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

class _FakeThread extends ChatThreadNotifier {
  _FakeThread(this.value);

  final ChatThreadState value;

  @override
  Future<ChatThreadState> build(ChatThreadArg arg) async => value;
}

/// Where a tap on the header landed, if anywhere.
String? _openedRoute;

Future<void> _pump(WidgetTester tester, ChatThreadState state) async {
  _openedRoute = null;
  tester.view.physicalSize = const Size(1170, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        chatThreadProvider.overrideWith(() => _FakeThread(state)),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: GoRouter(
          initialLocation: '/chat/room-a',
          routes: [
            GoRoute(
              path: '/chat/:slug',
              builder: (_, __) => const ChatThreadPage(slug: 'room-a'),
            ),
            GoRoute(
              path: '/market/:handle',
              builder: (_, routeState) {
                _openedRoute = routeState.uri.path;
                return const Text('storefront');
              },
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a conversation lays out without overflowing', (tester) async {
    await _pump(
      tester,
      ChatThreadState(
        title: _room.title,
        room: _room,
        messages: [
          _msg(id: 1, mine: false, text: 'Halo bang', minute: 40),
          _msg(id: 2, mine: true, text: 'halo bro', minute: 51),
          _msg(id: 3, mine: true, text: 'testtt', minute: 53),
          _msg(
            id: 4,
            mine: false,
            // The case the old fixed-width bubble could not take: one word
            // longer than the screen.
            text: 'Haiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii',
            minute: 55,
          ),
        ],
        othersReadUpTo: 2,
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('a run opens with the sender and every bubble is stamped', (
    tester,
  ) async {
    await _pump(
      tester,
      ChatThreadState(
        title: _room.title,
        room: _room,
        messages: [
          _msg(id: 1, mine: false, text: 'Hai juga', minute: 43),
          _msg(id: 2, mine: true, text: 'halo bro', minute: 51),
          _msg(id: 3, mine: true, text: 'testtt', minute: 53),
        ],
        othersReadUpTo: 2,
      ),
    );

    // The other party is named once, on the message that opens their run —
    // and again in the app bar, which is the header's own copy.
    expect(find.text('Toko User1'), findsNWidgets(2));
    expect(find.text('@user1'), findsOneWidget);

    // Web stamps each bubble rather than only the last of a run.
    expect(find.text('15.51'), findsOneWidget);
    expect(find.text('15.53'), findsOneWidget);
    expect(find.text('15.43'), findsOneWidget);
  });

  testWidgets('tapping who you are talking to opens their shop', (
    tester,
  ) async {
    await _pump(
      tester,
      const ChatThreadState(title: 'Toko User1', room: _room, messages: []),
    );

    await tester.tap(find.text('Toko User1'));
    await tester.pumpAndSettle();

    expect(_openedRoute, '/market/toko-user1');
  });

  testWidgets('a counterparty with no shop is not a link', (tester) async {
    const shopless = ChatRoom(
      id: 2,
      slug: 'room-b',
      title: 'user2',
      otherUserId: 'them',
    );
    await _pump(
      tester,
      const ChatThreadState(title: 'user2', room: shopless, messages: []),
    );

    await tester.tap(find.text('user2'));
    await tester.pumpAndSettle();

    expect(_openedRoute, isNull);
  });

  testWidgets('only your own messages carry ticks', (tester) async {
    await _pump(
      tester,
      ChatThreadState(
        title: _room.title,
        room: _room,
        messages: [
          _msg(id: 1, mine: false, minute: 40),
          _msg(id: 2, mine: true, minute: 41),
          _msg(id: 3, mine: true, minute: 42),
        ],
        // Only the first of the two has been read.
        othersReadUpTo: 2,
      ),
    );

    expect(find.byIcon(LucideIcons.checkCheck), findsNWidgets(2));
  });
}
