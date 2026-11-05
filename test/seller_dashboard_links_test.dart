import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/seller_order.dart';
import 'package:pokepedia_mobile/features/seller/presentation/seller_dashboard_page.dart';
import 'package:pokepedia_mobile/features/seller/presentation/widgets/seller_header.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/seller_dashboard.dart';
import 'package:pokepedia_mobile/features/seller/repository/seller_repository.dart';
import 'package:pokepedia_mobile/features/seller/usecase/seller_notifier.dart';

/// Each dashboard counter opens the list it counted. "Perlu dikirim" and
/// "Komplain terbuka" used to send `to_ship` and `disputes`, which the
/// orders list doesn't know, so it opened on whatever tab was last left.
const _me = AppUser(id: 'seller', email: 'seller@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

Future<List<Uri>> _tap(WidgetTester tester, String label) async {
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final opened = <Uri>[];
  final router = GoRouter(
    initialLocation: '/seller',
    routes: [
      GoRoute(path: '/seller', builder: (_, __) => const SellerDashboardPage()),
      GoRoute(
        path: '/seller/:rest',
        builder: (_, state) {
          opened.add(state.uri);
          return const SizedBox();
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        hasStoreProvider.overrideWith((ref) async => true),
        sellerIdentityProvider.overrideWith(
          (ref) async => const SellerIdentity(username: 'satoshi'),
        ),
        sellerDashboardProvider.overrideWith(
          (ref) async => const DashboardPayload(
            kpi: DashboardKpi(),
            performance: DashboardPerformance(window: 30),
            health: DashboardHealth(),
            summary: DashboardSummary(),
            walletBalance: 0,
          ),
        ),
        myReliabilityProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.tap(find.text(label));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return opened;
}

void main() {
  testWidgets('Perlu dikirim opens the Perlu dikirim tab', (tester) async {
    final opened = await _tap(tester, 'Perlu dikirim');
    expect(
      SellerOrderTab.fromFilterKey(opened.single.queryParameters['filter']),
      SellerOrderTab.urgent,
    );
  });

  testWidgets('Komplain terbuka opens the Komplain tab', (tester) async {
    final opened = await _tap(tester, 'Komplain terbuka');
    expect(
      SellerOrderTab.fromFilterKey(opened.single.queryParameters['filter']),
      SellerOrderTab.disputed,
    );
  });

  testWidgets('PESANAN opens Semua, not the tab last left', (tester) async {
    final opened = await _tap(tester, 'PESANAN');
    expect(
      SellerOrderTab.fromFilterKey(opened.single.queryParameters['filter']),
      SellerOrderTab.all,
    );
  });

  testWidgets('only Ada penawaran masuk asks for the offers filter', (
    tester,
  ) async {
    final offers = await _tap(tester, 'Ada penawaran masuk');
    expect(offers.single.queryParameters['offers'], '1');
  });
}
