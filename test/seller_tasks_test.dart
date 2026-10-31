import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/shared/widgets/app_bottom_nav.dart';
import 'package:pokepedia_mobile/features/seller/presentation/seller_dashboard_page.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/my_reliability.dart';
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
  summary: const DashboardSummary(last90: 25000000, delta90: 317),
  walletBalance: 177179,
);

/// A seller 20 orders short, clean otherwise — the design's sample.
const _newSeller = MyReliability(
  window90d: ReliabilityWindow(medianShipHours: 51.2),
  window30d: ReliabilityWindow(),
  topRated: false,
  negativeRating30d: false,
);

Future<void> _pump(
  WidgetTester tester,
  DashboardKpi kpi, {
  MyReliability? reliability = _newSeller,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width * 3, 1400 * 3);
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
        myReliabilityProvider.overrideWith((ref) async => reliability),
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

    // The heading counts open work, as web's does: a quiet day is "· 0".
    expect(find.text('Tugas · 0'), findsOneWidget);
    expect(find.text('Perlu dikirim'), findsOneWidget);
    expect(find.text('Ada penawaran masuk'), findsOneWidget);
    expect(find.text('Komplain terbuka'), findsOneWidget);
  });

  testWidgets('a busy day counts each one', (tester) async {
    await _pump(tester, const DashboardKpi(toShip: 3, disputesOpen: 2));

    expect(find.text('Tugas · 5'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('the seller is greeted by name', (tester) async {
    await _pump(tester, const DashboardKpi());
    expect(find.text('Halo, satoshi'), findsOneWidget);
  });

  testWidgets('the headline is the 90-day revenue and its move', (
    tester,
  ) async {
    await _pump(tester, const DashboardKpi());

    expect(find.text('OMZET 90 HARI'), findsOneWidget);
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
    expect(find.text('Jual'), findsOneWidget);
    expect(find.byType(SellerNotificationBell), findsOneWidget);

    // And it is the topmost thing on the page.
    final header = tester.getTopLeft(find.text('Jual')).dy;
    final greeting = tester.getTopLeft(find.text('Halo, satoshi')).dy;
    expect(header, lessThan(greeting));
  });

  testWidgets('the analytics no longer trail the page', (tester) async {
    await _pump(tester, const DashboardKpi());

    // The design ends at the button; the charts moved to their own page,
    // which is also why the 90-day figure appears once again.
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

  testWidgets('Lihat Toko and Atur Toko sit beside the greeting', (
    tester,
  ) async {
    await _pump(tester, const DashboardKpi());
    expect(find.text('Lihat Toko'), findsOneWidget);
    expect(find.text('Atur Toko'), findsOneWidget);
  });

  testWidgets('reliability and the road to Top Seller, as on web', (
    tester,
  ) async {
    await _pump(tester, const DashboardKpi());

    expect(find.text('Keandalan toko · 90 hari'), findsOneWidget);
    expect(find.text('Median kirim'), findsOneWidget);
    expect(find.text('52 jam'), findsOneWidget);
    expect(find.text('Menuju Top Seller · 30 hari'), findsOneWidget);
    expect(
      find.text('Minimal 20 pesanan selesai · Kurang 20 pesanan lagi'),
      findsOneWidget,
    );
    expect(
      find.text('Tanpa komplain kalah & rating negatif · Bersih'),
      findsOneWidget,
    );
  });

  testWidgets('a Top Seller has nothing left to work towards', (tester) async {
    await _pump(
      tester,
      const DashboardKpi(),
      reliability: const MyReliability(
        window90d: ReliabilityWindow(),
        window30d: ReliabilityWindow(),
        topRated: true,
        negativeRating30d: false,
      ),
    );
    expect(find.text('Keandalan toko · 90 hari'), findsOneWidget);
    expect(find.text('Menuju Top Seller · 30 hari'), findsNothing);
  });

  testWidgets('no reliability, no section', (tester) async {
    await _pump(tester, const DashboardKpi(), reliability: null);
    expect(find.text('Keandalan toko · 90 hari'), findsNothing);
  });

  testWidgets('Tambahkan Listing stays put above the nav as the page scrolls', (
    tester,
  ) async {
    await _pump(tester, const DashboardKpi());
    final button = find.text('Tambahkan Listing');
    final before = tester.getBottomLeft(button).dy;
    final screen =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

    final context = tester.element(button);
    expect(before, lessThan(screen - AppBottomNav.reservedSpace(context)));

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    expect(tester.getBottomLeft(button).dy, before);
  });

  testWidgets('fits a small phone without overflowing', (tester) async {
    await _pump(tester, const DashboardKpi(toShip: 120), width: 360);
    expect(tester.takeException(), isNull);
    expect(find.text('INAKTIF'), findsOneWidget);
  });
}
