import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/expansions_notifier.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';
import 'package:pokepedia_mobile/shared/widgets/listing_card.dart';

/// Where a marketplace tile goes when it's tapped.
///
/// A WTB tile used to fall through to the catalog card page, which says
/// nothing about the bid that was tapped. It has its own page now, and the
/// two sides must not cross: an ask opens the seller's product page, a bid
/// opens the bid.
ListingModel _listing({
  required ListingSide side,
  String slug = 'bid-slug-1',
  String storeSlug = 'toko-abc',
}) => ListingModel(
  id: 1,
  sellerId: 'someone',
  slug: slug,
  side: side,
  price: 385000,
  condition: CardCondition.nm,
  quantity: 3,
  card: const CardModel(
    id: 42,
    category: CardCategory.pokemon,
    nameId: 'Pikachu',
    expansionCode: 'SV2a',
    packSlug: 'sv2a',
    collectorNumber: '038/165',
    rarity: 'Rare',
  ),
  storeSlug: storeSlug,
  storeName: 'Toko Ash',
  isVerified: true,
  cityName: 'Kota Jakarta Selatan',
  createdAt: DateTime(2026, 8, 1),
);

Future<void> _tap(WidgetTester tester, ListingModel listing) async {
  tester.view.physicalSize = const Size(1170, 3000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(
        path: '/start',
        builder: (_, __) => Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 260, child: ListingCard(listing: listing)),
          ),
        ),
      ),
      GoRoute(
        path: '/bid/:slug',
        builder: (_, state) => Text('bid ${state.pathParameters['slug']}'),
      ),
      GoRoute(
        path: '/market/:handle/card/:cardId',
        builder: (_, state) => Text('ask ${state.pathParameters['handle']}'),
      ),
      GoRoute(
        path: '/expansions/:packSlug/:cardId',
        builder: (_, state) => Text('card ${state.pathParameters['cardId']}'),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        wishlistedIdsProvider.overrideWith((ref) async => <int>{}),
        seriesGroupsProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byType(ListingCard));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a bid opens its own page', (tester) async {
    await _tap(tester, _listing(side: ListingSide.bid));

    expect(find.text('bid bid-slug-1'), findsOneWidget);
  });

  testWidgets('a bid with no slug falls back to the card page', (tester) async {
    // Nothing to look the bid up by, so the catalog page — where every bid
    // used to land — is still the destination rather than a dead route.
    await _tap(tester, _listing(side: ListingSide.bid, slug: ''));

    expect(find.text('card 42'), findsOneWidget);
  });

  testWidgets('an ask still opens the seller product page', (tester) async {
    await _tap(tester, _listing(side: ListingSide.ask));

    expect(find.text('ask toko-abc'), findsOneWidget);
  });

  test('the bid route is addressed by listing slug', () {
    expect(Routes.bidListing('abc-123'), '/bid/abc-123');
  });
}
