import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pokepedia_mobile/app/app.dart';
import 'package:pokepedia_mobile/app/router/app_router.dart';
import 'package:pokepedia_mobile/features/orders/repository/orders_repository.dart';
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
    final orders = await OrdersRepository().fetchOrders();
    final issueOrder = orders.firstWhere((o) => o.status.name == 'issue', orElse: () => orders.first);

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
      '/orders/${orders.first.slug}',
      '/orders/${orders.first.slug}/open-dispute',
      '/orders/${issueOrder.slug}/dispute',
      '/proposals',
      '/wallet',
      '/chat',
      '/chat/cardvault-id',
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
