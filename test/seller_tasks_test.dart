import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/seller/presentation/seller_dashboard_page.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/seller_dashboard.dart';
import 'package:pokepedia_mobile/features/seller/repository/seller_repository.dart';
import 'package:pokepedia_mobile/features/seller/presentation/widgets/seller_header.dart';
import 'package:pokepedia_mobile/features/seller/usecase/seller_notifier.dart';

/// The dashboard's "Tugas" list.
///
/// This replaced "Penting hari ini", which drew only the counters that had
/// something on them and a "nothing to do" line when none did. The three
/// rows are always there now: a seller checking whether anything needs
/// shipping wants that answered in the same place whether the answer is
/// three or none, and a list that changes shape has to be re-read before it
/// can be scanned.
const _me = AppUser(id: 'seller', email: 'seller@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

DashboardPayload _payload(DashboardKpi kpi) => DashboardPayload(
  kpi: kpi,
  performance: const DashboardPerformance(window: 30),
  health: const DashboardHealth(),
  summary: const DashboardSummary(last30: 25000000, delta30: 317),
  walletBalance: 177179,
);

Future<void> _pump(WidgetTester tester, DashboardKpi kpi) async {
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        hasStoreProvider.overrideWith((ref) async => true),
        sellerIdentityProvider.overrideWith(
          (ref) async => const SellerIdentity(username: 'satoshi'),
        ),
        sellerDashboardProvider.overrideWith((ref) async => _payload(kpi)),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const SellerDashboardPage(),
      ),
    ),
  );
  // hasStore, then the dashboard payload, then the counts the tiles read:
  // each is its own future, so one pump is not enough.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('all three tasks are listed, quiet day or not', (tester) async {
    await _pump(tester, const DashboardKpi());

    expect(find.text('Tugas · 3'), findsOneWidget);
    expect(find.text('Perlu dikirim'), findsOneWidget);
    expect(find.text('Ada penawaran masuk'), findsOneWidget);
    expect(find.text('Komplain terbuka'), findsOneWidget);
  });

  testWidgets('a busy day counts each one', (tester) async {
    await _pump(tester, const DashboardKpi(toShip: 3, disputesOpen: 2));

    expect(find.text('3'), findsWidgets);
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('the seller is greeted by name', (tester) async {
    await _pump(tester, const DashboardKpi());
    expect(find.text('Halo, satoshi'), findsOneWidget);
  });

  testWidgets('the headline is the 30-day revenue and its move', (
    tester,
  ) async {
    await _pump(tester, const DashboardKpi());

    expect(find.text('OMZET 30 HARI'), findsOneWidget);
    expect(find.text('Rp25.000.000'), findsOneWidget);
    // Signed, so a fall reads as one without having to compare two numbers.
    expect(find.text('+317%'), findsOneWidget);
  });

  testWidgets('the page starts at its own header, with no app bar over it', (
    tester,
  ) async {
    await _pump(tester, const DashboardKpi());

    // The dashboard is a tab, not a pushed page. It carried a
    // `TransparentAppBar`, whose back arrow sat on top of the wordmark while
    // its overlay padding pushed the whole page down — which is why the
    // redesign looked unchanged even though the content underneath had been
    // rebuilt.
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byType(SellerHeader), findsOneWidget);

    // And it is the topmost thing on the page.
    final header = tester.getTopLeft(find.byType(SellerHeader)).dy;
    final greeting = tester.getTopLeft(find.text('Halo, satoshi')).dy;
    expect(header, lessThan(greeting));
  });

  testWidgets('the analytics no longer trail the page', (tester) async {
    await _pump(tester, const DashboardKpi());

    // The design ends at the button; the charts moved to their own page,
    // which is also why the 30-day figure appears once again.
    expect(find.text('Rp25.000.000'), findsOneWidget);
    expect(find.text('Tambahkan Listing'), findsOneWidget);
  });

  testWidgets('the wallet balance sits under Pembayaran', (tester) async {
    await _pump(tester, const DashboardKpi());

    expect(find.text('Pembayaran'), findsOneWidget);
    expect(find.text('Saldo dompet'), findsOneWidget);
    expect(find.text('Rp177.179'), findsOneWidget);

    // The label sits above the amount, not beside it.
    expect(
      tester.getTopLeft(find.text('Saldo dompet')).dy,
      lessThan(tester.getTopLeft(find.text('Rp177.179')).dy),
    );
    // A chevron, not an arrow: the row steps into a page rather than
    // pointing off somewhere.
    expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowRight), findsNothing);
  });
}
