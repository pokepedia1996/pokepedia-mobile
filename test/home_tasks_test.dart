import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/ads/repository/ads_repository.dart';
import 'package:pokepedia_mobile/features/ads/usecase/ads_notifier.dart';
import 'package:pokepedia_mobile/features/home/presentation/widgets/home_ad_slot.dart';
import 'package:pokepedia_mobile/features/home/presentation/widgets/home_tasks_section.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/proposals_summary.dart';
import 'package:pokepedia_mobile/features/proposals/usecase/proposals_notifier.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/seller_dashboard.dart';
import 'package:pokepedia_mobile/features/seller/repository/seller_repository.dart';
import 'package:pokepedia_mobile/features/seller/usecase/seller_notifier.dart';

/// Beranda's task strip: eBay's "you have items to ship", and nothing at all
/// on a day with nothing to do.
const _me = AppUser(id: 'me', email: 'me@example.com');

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

Future<void> _pump(
  WidgetTester tester, {
  bool hasStore = true,
  DashboardKpi kpi = const DashboardKpi(),
  ProposalsSummary proposals = const ProposalsSummary(),
}) async {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        hasStoreProvider.overrideWith((ref) async => hasStore),
        sellerIdentityProvider.overrideWith(
          (ref) async => const SellerIdentity(),
        ),
        sellerDashboardProvider.overrideWith((ref) async => _payload(kpi)),
        proposalsSummaryProvider.overrideWith((ref) async => proposals),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: HomeTasksSection()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpSlot(WidgetTester tester, List<AdModel> ads) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adsProvider(AdPlacement.home).overrideWith((ref) async => ads),
      ],
      child: const MaterialApp(home: Scaffold(body: HomeAdSlot())),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('nothing to do means nothing on screen', (tester) async {
    await _pump(tester);

    expect(find.byType(InkWell), findsNothing);
    expect(find.textContaining('Perlu dikirim'), findsNothing);
  });

  testWidgets('a job shows with its count', (tester) async {
    await _pump(tester, kpi: const DashboardKpi(toShip: 9));

    expect(find.text('9'), findsOneWidget);
    expect(find.text('Perlu dikirim'), findsOneWidget);
    // Only the one that has something on it.
    expect(find.text('Komplain terbuka'), findsNothing);
  });

  testWidgets('jobs stack, seller and buyer side alike', (tester) async {
    await _pump(
      tester,
      kpi: const DashboardKpi(toShip: 2, disputesOpen: 1),
      proposals: const ProposalsSummary(receivedPending: 3),
    );

    expect(find.text('Perlu dikirim'), findsOneWidget);
    expect(find.text('Komplain terbuka'), findsOneWidget);
    expect(find.text('Proposal masuk'), findsOneWidget);
  });

  testWidgets('a buyer is never asked about a shop they do not have', (
    tester,
  ) async {
    // The dashboard payload would answer, but it is not even consulted.
    await _pump(
      tester,
      hasStore: false,
      kpi: const DashboardKpi(toShip: 9),
      proposals: const ProposalsSummary(receivedPending: 1),
    );

    expect(find.text('Perlu dikirim'), findsNothing);
    expect(find.text('Proposal masuk'), findsOneWidget);
  });

  testWidgets('nothing booked means no box at all', (tester) async {
    await _pumpSlot(tester, const []);

    // Not a placeholder, not a reserved gap — web's "Space Available" house
    // ad belongs on a page a media buyer reads, not in a phone's scroll.
    expect(find.byType(AspectRatio), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a booked slot draws it at 2:1', (tester) async {
    await _pumpSlot(tester, [
      const AdModel(
        id: 1,
        companyName: 'Gattchaa',
        imageUrl: 'https://cdn2.pokepedia.id/media/gattchaa_2.webp',
        href: 'https://example.com',
        slotPosition: 1,
      ),
    ]);

    final box = tester.getSize(find.byType(AspectRatio));
    // 800x400 at whatever width the phone gives it.
    expect(box.width / box.height, closeTo(2, 0.01));
  });

  testWidgets('the first slot position wins', (tester) async {
    await _pumpSlot(tester, [
      const AdModel(
        id: 1,
        companyName: 'First',
        imageUrl: 'https://cdn2.pokepedia.id/a.webp',
        href: '',
        slotPosition: 1,
      ),
      const AdModel(
        id: 2,
        companyName: 'Second',
        imageUrl: 'https://cdn2.pokepedia.id/b.webp',
        href: '',
        slotPosition: 2,
      ),
    ]);

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.semanticLabel, 'First');
  });
}
