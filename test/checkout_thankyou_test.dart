import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokepedia_mobile/app/router/navigation.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/cart/presentation/checkout_thankyou_page.dart';

/// A saldo checkout has nothing to poll, so it ends on a thank-you screen
/// rather than dropping the buyer into Pesanan with no sign anything
/// happened. The real router listens to `Supabase.instance` and can't be
/// mounted here, so this mirrors the shape under test: Beranda in the shell,
/// the success screen pushed above it exactly as `goHomeThen` does.
GoRouter _router() => GoRouter(
  initialLocation: Routes.checkout,
  routes: [
    GoRoute(path: Routes.home, builder: (_, __) => const Text('Beranda')),
    GoRoute(path: Routes.orders, builder: (_, __) => const Text('Pesanan')),
    GoRoute(
      path: Routes.checkout,
      builder: (context, __) => TextButton(
        onPressed: () => context.goHomeThen(
          Routes.checkoutSuccessFor(cards: 3, total: 150000),
        ),
        child: const Text('Bayar'),
      ),
    ),
    GoRoute(
      path: Routes.checkoutSuccess,
      builder: (_, state) => CheckoutThankYouPage(
        cardCount: int.tryParse(state.uri.queryParameters['cards'] ?? '') ?? 0,
        totalAmount: int.tryParse(state.uri.queryParameters['total'] ?? '') ?? 0,
      ),
    ),
  ],
);

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: _router(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a saldo checkout lands on the thank-you screen', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Bayar'));
    await tester.pumpAndSettle();

    expect(find.text('Pembayaran Berhasil!'), findsOneWidget);
    // The figures travel in the URL, so they survive the go(home) + push.
    expect(find.text('3 kartu berhasil dibeli.'), findsOneWidget);
    expect(find.text('Dibayar dari saldo: Rp150.000'), findsOneWidget);
    // Pesanan is offered, not forced.
    expect(find.text('Pesanan'), findsNothing);
  });

  testWidgets('Beranda sits underneath, not the spent checkout', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Bayar'));
    await tester.pumpAndSettle();

    // Backing out of a finished order must not return to the checkout it was
    // paid from — that cart is gone and the page would rebuild empty.
    final router = GoRouter.of(tester.element(find.byType(Scaffold)));
    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('Beranda'), findsOneWidget);
    expect(find.text('Bayar'), findsNothing);
  });

  testWidgets('Lihat Pesanan opens the order list', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Bayar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lihat Pesanan'));
    await tester.pumpAndSettle();

    expect(find.text('Pesanan'), findsOneWidget);
  });
}
