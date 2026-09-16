import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pokepedia_mobile/app/app.dart';
import 'package:pokepedia_mobile/app/router/app_router.dart';
import 'package:pokepedia_mobile/shared/widgets/app_bottom_nav.dart';

/// Catalog routes are exercised with literal slugs rather than rows from a
/// catalog fixture: every page behind them loads from Supabase now, so no
/// slug this test can name resolves to anything, and what's under test is
/// that the route builds — not what it finds.
const _packSlug = 'sv3';
const _cardId = 1;
const _storeHandle = 'toko';

/// Likewise for the per-account server data behind the order routes, which
/// this test reaches signed out.
const _orderSlug = '00000000-0000-4000-8000-000000000000';

void main() {
  // `appRouter` listens to `Supabase.instance` and reads the session in its
  // redirect, so it cannot be built until a client exists. Pointed at a
  // local address that is never actually contacted: nothing here signs in,
  // and the pages assert on building, not on what loads.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-publishable-key',
    );
  });

  testWidgets('every route in the app renders without throwing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: PokepediaApp()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    const orderSlug = _orderSlug;

    final routes = <String>[
      '/expansions',
      '/expansions/$_packSlug',
      '/expansions/$_packSlug/$_cardId',
      '/advanced-search',
      '/portfolio/collection',
      '/market',
      '/market/$_storeHandle',
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
      // A shell branch root is switched to, never pushed. Pushing one onto
      // the root navigator builds it a second time while the shell's
      // IndexedStack still holds it, and the two copies reserve the same
      // GlobalKey — a crash the app never hits, because the bottom nav
      // reaches these through `goBranch`/`go`.
      if (AppBottomNav.tabPaths.contains(route)) {
        appRouter.go(route);
      } else {
        appRouter.push(route);
      }
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
      'Portofolio',
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
