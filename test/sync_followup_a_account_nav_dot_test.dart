import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/account/usecase/account_nav_indicator.dart';
import 'package:pokepedia_mobile/shared/widgets/app_bottom_nav.dart';

final _account = AppBottomNav.tabPaths.indexOf(Routes.account);

Future<void> _pump(WidgetTester tester, Set<int> dotted) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: AppBottomNav(
          currentIndex: 0,
          dotted: dotted,
          onTap: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Web's `accountIndicator` in `mobile-bottom-nav.tsx`: buyer to-dos,
/// unread notifications and unread chat all light the Akun dot.
void main() {
  group('showsAccountIndicator', () {
    bool shows({
      bool signedIn = true,
      int actions = 0,
      int notifications = 0,
      int chat = 0,
    }) => showsAccountIndicator(
      signedIn: signedIn,
      buyerActionTotal: actions,
      notificationUnread: notifications,
      chatUnread: chat,
    );

    test('nothing pending, no dot', () => expect(shows(), isFalse));

    test('any one source is enough', () {
      expect(shows(actions: 1), isTrue);
      expect(shows(notifications: 2), isTrue);
      expect(shows(chat: 3), isTrue);
    });

    test('signed out never shows it, whatever counts linger', () {
      expect(
        shows(signedIn: false, actions: 4, notifications: 1, chat: 1),
        isFalse,
      );
    });
  });

  testWidgets('the dot draws only on the flagged tab', (tester) async {
    await _pump(tester, {_account});

    final dot = find.byKey(const ValueKey('bottom-nav-dot'));
    expect(dot, findsOneWidget);
    // It sits over Akun's icon, not some other tab's.
    final akun = tester.getRect(find.text('Akun'));
    final dotRect = tester.getRect(dot);
    expect(dotRect.center.dx, greaterThan(akun.left));
    expect(dotRect.center.dx, lessThan(akun.right + 12));
  });

  testWidgets('no flags, no dot', (tester) async {
    await _pump(tester, const {});
    expect(find.byKey(const ValueKey('bottom-nav-dot')), findsNothing);
  });
}
