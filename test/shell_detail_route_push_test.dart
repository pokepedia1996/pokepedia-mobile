import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Guards the navigator setup behind "Lihat toko" and every other link into a
/// detail page from a screen that sits above the shell.
///
/// `/market/:handle` and `/expansions/:packSlug/:cardId` live inside
/// `StatefulShellBranch`es, but the seller dashboard, orders, chat and
/// notifications all sit *above* the shell as top-level routes. Pushing a
/// branch route from up there made go_router hand the root navigator a page
/// whose key the branch had already reserved, and Navigator's
/// `!keyReservation.contains(key)` assertion took the screen down.
///
/// Mirrors `app_router.dart`'s shape rather than importing it: the real
/// router builds a `GoRouterRefreshStream` over `Supabase.instance` at
/// construction, which a widget test has no session for.
final rootKey = GlobalKey<NavigatorState>();

GoRouter buildRouter() => GoRouter(
  navigatorKey: rootKey,
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => Scaffold(body: shell),
      branches: [
        StatefulShellBranch(
          routes: [GoRoute(path: '/home', builder: (_, __) => const Text('home'))],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/market',
              builder: (_, __) => const Text('market'),
              routes: [
                GoRoute(
                  path: ':handle',
                  parentNavigatorKey: rootKey,
                  builder: (_, state) =>
                      Text('store ${state.pathParameters['handle']}'),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    GoRoute(path: '/seller', builder: (_, __) => const Text('seller')),
  ],
);

void main() {
  testWidgets('opens a store from a route above the shell', (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.push('/seller');
    await tester.pumpAndSettle();
    expect(find.text('seller'), findsOneWidget);

    // What "Lihat toko" does on the seller dashboard.
    router.push('/market/toko-abc');
    await tester.pumpAndSettle();
    expect(find.text('store toko-abc'), findsOneWidget);

    // And back to where it was opened from, not into the Market tab.
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('seller'), findsOneWidget);
  });

  testWidgets('still opens a store from inside the Market tab', (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.go('/market');
    await tester.pumpAndSettle();
    expect(find.text('market'), findsOneWidget);

    router.push('/market/toko-abc');
    await tester.pumpAndSettle();
    expect(find.text('store toko-abc'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('market'), findsOneWidget);
  });
}
