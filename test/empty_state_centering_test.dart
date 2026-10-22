import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/chat/presentation/chat_inbox_page.dart';
import 'package:pokepedia_mobile/features/chat/repository/models/chat_models.dart';
import 'package:pokepedia_mobile/features/chat/usecase/chat_notifier.dart';
import 'package:pokepedia_mobile/features/notifications/presentation/notifications_page.dart';
import 'package:pokepedia_mobile/features/notifications/repository/models/notification_model.dart';
import 'package:pokepedia_mobile/features/notifications/usecase/notifications_notifier.dart';
import 'package:pokepedia_mobile/shared/widgets/empty_state.dart';

/// Every empty screen puts its note in the middle — across and down — of
/// the room it has, so no page reads differently from the next.
const _me = AppUser(id: 'me', email: 'me@example.com');

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this.user);

  final AppUser? user;

  @override
  Future<AppUser?> build() async => user;
}

class _NoNotifications extends NotificationsNotifier {
  @override
  Future<List<NotificationModel>> build() async => const [];
}

class _NoThreads extends ChatThreadsNotifier {
  @override
  Future<List<ChatThread>> build() async => const [];
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _openPage(
  WidgetTester tester,
  Widget page, {
  AppUser? user = _me,
}) async {
  _phone(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FakeAuth(user)),
        notificationsProvider.overrideWith(_NoNotifications.new),
        chatThreadsProvider.overrideWith(_NoThreads.new),
      ],
      child: MaterialApp(theme: AppTheme.light, home: page),
    ),
  );
  await tester.pumpAndSettle();
}

/// The note's centre is the centre of [space].
void _expectCentredIn(WidgetTester tester, Rect space) {
  final note = tester.getCenter(find.byType(EmptyState));
  expect(note.dx, moreOrLessEquals(space.center.dx, epsilon: 1));
  expect(note.dy, moreOrLessEquals(space.center.dy, epsilon: 1));
}

/// The room under the app bar.
Rect _body(WidgetTester tester) {
  final page = tester.getRect(find.byType(Scaffold));
  final appBar = tester.getRect(find.byType(AppBar));
  return Rect.fromLTRB(page.left, appBar.bottom, page.right, page.bottom);
}

const _note = EmptyState(icon: LucideIcons.inbox, title: 'Kosong');

void main() {
  group('pages', () {
    testWidgets('chat, with no conversations', (tester) async {
      await _openPage(tester, const ChatInboxPage());
      expect(find.byType(EmptyState), findsOneWidget);
      _expectCentredIn(tester, _body(tester));
    });

    testWidgets('chat, signed out', (tester) async {
      await _openPage(tester, const ChatInboxPage(), user: null);
      expect(find.text('Masuk'), findsOneWidget);
      _expectCentredIn(tester, _body(tester));
    });

    testWidgets('notifications, with none', (tester) async {
      await _openPage(tester, const NotificationsPage());
      expect(find.text('Belum ada notifikasi'), findsOneWidget);
      _expectCentredIn(tester, _body(tester));
    });

    testWidgets('notifications, signed out', (tester) async {
      await _openPage(tester, const NotificationsPage(), user: null);
      expect(find.text('Masuk untuk melihat notifikasi'), findsOneWidget);
      _expectCentredIn(tester, _body(tester));
    });
  });

  testWidgets('EmptyState fills a bounded room, centred', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            SizedBox(height: 200),
            Expanded(child: _note),
          ],
        ),
      ),
    );
    final room = tester.getRect(find.byType(Expanded));
    _expectCentredIn(tester, room);
  });

  testWidgets('in a list it keeps to its own height', (tester) async {
    // No room to centre in, so it stays where the list puts it — the
    // sections that sit under other content are unchanged.
    _phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(children: const [SizedBox(height: 100), _note]),
      ),
    );
    expect(tester.getTopLeft(find.byType(EmptyState)).dy, 100);
  });

  group('ScrollableEmptyState', () {
    Future<List<int>> host(WidgetTester tester) async {
      _phone(tester);
      final refreshes = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RefreshIndicator(
              onRefresh: () async => refreshes.add(1),
              child: const ScrollableEmptyState(
                header: [SizedBox(key: Key('header'), height: 150)],
                child: _note,
              ),
            ),
          ),
        ),
      );
      return refreshes;
    }

    testWidgets('centres it in the room under the header', (tester) async {
      await host(tester);
      final header = tester.getRect(find.byKey(const Key('header')));
      final page = tester.getRect(find.byType(Scaffold));
      _expectCentredIn(
        tester,
        Rect.fromLTRB(page.left, header.bottom, page.right, page.bottom),
      );
    });

    testWidgets('and still pulls to refresh', (tester) async {
      final refreshes = await host(tester);
      await tester.fling(find.byType(EmptyState), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(refreshes, hasLength(1));
    });
  });
}
