import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pokepedia_mobile/app/app.dart';
import 'package:pokepedia_mobile/app/router/app_router.dart';
import 'package:pokepedia_mobile/shared/data/dummy_catalog.dart';

void main() {
  testWidgets('every route in the app renders without throwing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: PokepediaApp()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final pack = DummyCatalog.packs.first;
    final card = DummyCatalog.allCards.first;
    final store = DummyCatalog.stores.first;
    // Orders are per-account server data now, and this test runs signed out,
    // so the order routes are exercised with a slug that resolves to nothing:
    // what's under test here is that the route builds, not what it finds.
    const orderSlug = '00000000-0000-4000-8000-000000000000';

    final routes = <String>[
      '/expansions',
      '/expansions/${pack.slug}',
      '/expansions/${pack.slug}/${card.id}',
      '/advanced-search',
      '/portfolio/collection',
      '/market',
      '/market/${store.handle}',
      '/account',
      '/login',
      '/signup',
      '/forgot-password',
      '/reset-password',
      '/cart',
      '/cart/checkout',
      '/cart/checkout/success',
      '/orders',
      '/orders/$orderSlug',
      '/orders/$orderSlug/open-dispute',
      '/orders/$orderSlug/dispute',
      '/proposals',
      '/wallet',
      '/chat',
      '/chat/$orderSlug',
      '/notifications',
      '/settings',
      '/users',
      '/user/ashketchum',
      '/portfolio/deck/1',
      '/portfolio/list',
      '/portfolio/list/1',
      '/support',
      '/tutorial',
      '/terms/syarat-dan-ketentuan',
      '/terms/kebijakan-privasi',
      '/terms/kondisi-kartu',
    ];

    for (final route in routes) {
      appRouter.push(route);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Route "$route" threw during build',
      );
    }
  });

  testWidgets('bottom nav switches between all six tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: PokepediaApp()));
    // The previous test left the shared `appRouter` singleton deep in a
    // pushed stack — reset it to Home so the bottom nav is visible here.
    appRouter.go('/');
    await tester.pumpAndSettle();

    for (final label in [
      'Ekspansi',
      'Pencarian',
      'Koleksi',
      'Market',
      'Akun',
      'Beranda',
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Tab "$label" threw');
    }
  });
}
