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
import 'package:pokepedia_mobile/shared/widgets/condition_badge.dart';
import 'package:pokepedia_mobile/shared/widgets/listing_card.dart';
import 'package:pokepedia_mobile/shared/widgets/wishlist_heart.dart';

ListingModel _customListing() => ListingModel(
  id: 7,
  sellerId: 's',
  slug: 'custom-slug',
  side: ListingSide.ask,
  price: 2900000,
  condition: CardCondition.nm,
  quantity: 3,
  card: const CardModel.custom(title: 'Paket Charizard & Pikachu'),
  storeSlug: 'toko-user1',
  storeName: 'Toko User1',
  isVerified: false,
  cityName: 'Jakarta',
  createdAt: DateTime(2026, 11, 23),
);

ListingModel _cardListing() => ListingModel(
  id: 1,
  sellerId: 's',
  slug: 'l',
  side: ListingSide.ask,
  price: 385000,
  condition: CardCondition.nm,
  quantity: 3,
  card: const CardModel(
    id: 1,
    category: CardCategory.pokemon,
    nameId: 'Professor Elm Training Method',
    expansionCode: 'SV2a',
    packSlug: 'sv2a',
    collectorNumber: '038/165',
    rarity: 'Rare',
  ),
  storeSlug: 'toko',
  storeName: 'Toko Ash',
  isVerified: false,
  cityName: 'Jakarta',
  createdAt: DateTime(2026, 8, 1),
);

Future<GoRouter> _pump(WidgetTester tester, ListingModel listing) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              height: 360,
              child: ListingCard(listing: listing, showSeller: true),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/market/:handle/listing/:slug',
        builder: (_, state) => Scaffold(
          body: Text(
            'custom page ${state.pathParameters['handle']} '
            '${state.pathParameters['slug']}',
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        wishlistedIdsProvider.overrideWith((ref) async => <int>{}),
        seriesGroupsProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pump();
  return router;
}

void main() {
  testWidgets('a custom tile is the seller\'s title with a CUSTOM marker', (
    tester,
  ) async {
    await _pump(tester, _customListing());

    expect(find.text('Paket Charizard & Pikachu'), findsOneWidget);
    expect(find.text('CUSTOM'), findsOneWidget);
    expect(find.byType(ConditionBadge), findsNothing);
    expect(find.byType(WishlistHeart), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a card tile keeps its grade and its heart', (tester) async {
    await _pump(tester, _cardListing());

    expect(find.text('CUSTOM'), findsNothing);
    expect(find.byType(ConditionBadge), findsOneWidget);
    expect(find.byType(WishlistHeart), findsOneWidget);
  });

  testWidgets('tapping a custom tile opens the custom listing page', (
    tester,
  ) async {
    await _pump(tester, _customListing());

    await tester.tap(find.text('Paket Charizard & Pikachu'));
    await tester.pumpAndSettle();

    expect(find.text('custom page toko-user1 custom-slug'), findsOneWidget);
  });

  test('the route a custom tile opens', () {
    expect(
      Routes.customListing('toko-user1', 'abc'),
      '/market/toko-user1/listing/abc',
    );
  });
}
