import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokepedia_mobile/app/router/navigation.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';

/// A miniature of the app's shape: Beranda inside the shell, Pesanan and the
/// checkout success screen as full-screen routes above it. The real router
/// can't be mounted in a test — it listens to `Supabase.instance` — so this
/// stands in for the routing behaviour under test, which is go_router's, not
/// the app's own route table.
GoRouter _router() => GoRouter(
  initialLocation: '/success',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, __, shell) => shell,
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.home,
              builder: (_, __) => const Text('Beranda'),
            ),
          ],
        ),
      ],
    ),
    GoRoute(path: Routes.orders, builder: (_, __) => const Text('Pesanan')),
    GoRoute(
      path: '/success',
      builder: (context, __) => TextButton(
        onPressed: () => context.goHomeThen(Routes.orders),
        child: const Text('Lihat Pesanan'),
      ),
    ),
  ],
);

/// Checkout ends by replacing the stack, so the screens that close it have to
/// put Beranda back underneath whatever they open. Without that, the first
/// back press out of Pesanan closes the app on a buyer who has just paid.
void main() {
  testWidgets('leaving checkout for Pesanan keeps Beranda underneath', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.tap(find.text('Lihat Pesanan'));
    await tester.pumpAndSettle();

    expect(find.text('Pesanan'), findsOneWidget);
    // The success screen is gone rather than buried under Pesanan: going back
    // to a finished checkout is its own kind of wrong.
    expect(find.text('Lihat Pesanan'), findsNothing);
    expect(router.canPop(), isTrue);

    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('Beranda'), findsOneWidget);
    expect(router.canPop(), isFalse);
  });
}
