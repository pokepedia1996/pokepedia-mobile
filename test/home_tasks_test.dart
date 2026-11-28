import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/home/presentation/widgets/home_tasks_section.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/proposals_summary.dart';
import 'package:pokepedia_mobile/features/proposals/usecase/proposals_notifier.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/seller_dashboard.dart';
import 'package:pokepedia_mobile/features/seller/repository/seller_repository.dart';
import 'package:pokepedia_mobile/features/seller/usecase/seller_notifier.dart';
import 'package:pokepedia_mobile/features/seller/usecase/offers_notifier.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/listing_offer.dart';

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
  int incomingOffers = 0,
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
        offerCountsProvider.overrideWith(
          (ref) => {
            if (incomingOffers > 0)
              'listing': OfferCount(
                total: incomingOffers,
                needsResponse: incomingOffers,
              ),
          },
        ),
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

void main() {
  testWidgets('nothing to do means nothing on screen', (tester) async {
    await _pump(tester);

    expect(find.byType(InkWell), findsNothing);
    expect(find.text('Penawaran masuk'), findsNothing);
    expect(find.text('WTB-mu dipenuhi'), findsNothing);
    expect(find.textContaining('Perlu dikirim'), findsNothing);
  });

  testWidgets('incoming offers appear only when a seller needs to respond', (
    tester,
  ) async {
    await _pump(tester, incomingOffers: 4);
    expect(find.text('Penawaran masuk'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
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
      incomingOffers: 4,
      kpi: const DashboardKpi(toShip: 2, disputesOpen: 1),
      proposals: const ProposalsSummary(receivedPending: 3),
    );

    expect(find.text('Perlu dikirim'), findsOneWidget);
    expect(find.text('Komplain terbuka'), findsOneWidget);
    expect(find.text('Penawaran masuk'), findsOneWidget);
    expect(find.text('WTB-mu dipenuhi'), findsOneWidget);
  });

  testWidgets('a buyer is never asked about a shop they do not have', (
    tester,
  ) async {
    // The dashboard payload would answer, but it is not even consulted.
    await _pump(
      tester,
      hasStore: false,
      incomingOffers: 4,
      kpi: const DashboardKpi(toShip: 9),
      proposals: const ProposalsSummary(receivedPending: 1),
    );

    expect(find.text('Perlu dikirim'), findsNothing);
    expect(find.text('WTB-mu dipenuhi'), findsOneWidget);
    expect(find.text('Penawaran masuk'), findsNothing);
  });
}
