import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/seller/presentation/seller_dashboard_page.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/seller_dashboard.dart';
import 'package:pokepedia_mobile/features/seller/repository/seller_repository.dart';
import 'package:pokepedia_mobile/features/seller/usecase/seller_notifier.dart';

/// "Penting hari ini" is the first thing on the dashboard, so a counter at
/// zero costs a line that says nothing and buries the one that doesn't.
const _me = AppUser(id: 'seller', email: 'seller@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

DashboardPayload _payload(DashboardKpi kpi) => DashboardPayload(
  kpi: kpi,
  performance: const DashboardPerformance(window: 30),
  health: const DashboardHealth(),
  summary: const DashboardSummary(),
  walletBalance: 0,
);

Future<void> _pump(WidgetTester tester, DashboardKpi kpi) async {
  tester.view.physicalSize = const Size(1170, 3600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        hasStoreProvider.overrideWith((ref) async => true),
        sellerIdentityProvider.overrideWith(
          (ref) async => const SellerIdentity(),
        ),
        sellerDashboardProvider.overrideWith((ref) async => _payload(kpi)),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const SellerDashboardPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('only the counters with something on them are drawn', (
    tester,
  ) async {
    await _pump(tester, const DashboardKpi(toShip: 2, disputesOpen: 1));

    expect(find.text('Perlu dikirim'), findsOneWidget);
    expect(find.text('Komplain terbuka'), findsOneWidget);
    // Nothing in transit, so nothing about it.
    expect(find.text('Sedang dikirim'), findsNothing);
  });

  testWidgets('a quiet day says so rather than showing an empty box', (
    tester,
  ) async {
    await _pump(tester, const DashboardKpi());

    expect(
      find.text('Tidak ada yang perlu ditangani hari ini'),
      findsOneWidget,
    );
    expect(find.text('Perlu dikirim'), findsNothing);
    expect(find.text('Komplain terbuka'), findsNothing);
  });

  testWidgets('a busy day keeps all three', (tester) async {
    await _pump(
      tester,
      const DashboardKpi(toShip: 3, inTransit: 5, disputesOpen: 2),
    );

    expect(find.text('Perlu dikirim'), findsOneWidget);
    expect(find.text('Sedang dikirim'), findsOneWidget);
    expect(find.text('Komplain terbuka'), findsOneWidget);
    expect(find.text('Tidak ada yang perlu ditangani hari ini'), findsNothing);
  });
}
