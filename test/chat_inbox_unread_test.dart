import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/chat/presentation/chat_inbox_page.dart';
import 'package:pokepedia_mobile/features/chat/repository/models/chat_models.dart';
import 'package:pokepedia_mobile/features/chat/usecase/chat_notifier.dart';

/// An unread conversation has to stand out in the inbox at a glance — not
/// only by a semibold preview, which was too quiet to spot while scrolling.
const _me = AppUser(id: 'me', email: 'me@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

class _Threads extends ChatThreadsNotifier {
  @override
  Future<List<ChatThread>> build() async => [
    ChatThread(
      roomId: 1,
      slug: 'room-1',
      unread: 2,
      otherUsername: 'pudskyasta',
      lastMessage: 'gapapa si',
      lastMessageAt: DateTime.now().subtract(const Duration(minutes: 44)),
    ),
    ChatThread(
      roomId: 2,
      slug: 'room-2',
      unread: 0,
      otherUsername: 'budi',
      lastMessage: 'oke siap',
      lastMessageAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
  ];
}

/// The colour the row is painted in: the Material right around its InkWell.
Color? _rowColor(WidgetTester tester, String preview) {
  final ink = find.ancestor(
    of: find.text(preview),
    matching: find.byType(InkWell),
  );
  return tester
      .widget<Material>(
        find.ancestor(of: ink.first, matching: find.byType(Material)).first,
      )
      .color;
}

void main() {
  testWidgets('an unread row stands out from a read one', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          chatThreadsProvider.overrideWith(_Threads.new),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const ChatInboxPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Tinted, against the read row's plain background.
    expect(_rowColor(tester, 'gapapa si'), isNot(Colors.transparent));
    expect(_rowColor(tester, 'oke siap'), Colors.transparent);

    // The preview in full ink and weight; the read one muted.
    final unread = tester.widget<Text>(find.text('gapapa si')).style!;
    final read = tester.widget<Text>(find.text('oke siap')).style!;
    expect(unread.fontWeight, FontWeight.w600);
    expect(read.fontWeight, isNot(FontWeight.w600));

    // And how many are waiting.
    expect(find.text('2'), findsOneWidget);
  });

  test('leaving a conversation lets it go', () {
    // Kept alive, an open thread went on marking every new message read
    // after the page closed, so the inbox never showed it as unread.
    expect(
      chatThreadProvider,
      isA<
        AutoDisposeAsyncNotifierProviderFamily<
          ChatThreadNotifier,
          ChatThreadState,
          ChatThreadArg
        >
      >(),
    );
  });
}
