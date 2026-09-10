import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/market/presentation/widgets/more_from_seller_section.dart';
import 'package:pokepedia_mobile/features/market/usecase/market_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';

/// The rail exists to fill one order rather than two, so what it must never
/// show is anything the buyer can't actually add: the card they're already
/// on, the seller's own bids, and closed or sold-out rows.
ListingModel _listing({
  required int cardId,
  ListingSide side = ListingSide.ask,
  ListingStatus status = ListingStatus.open,
  int quantity = 2,
  int qtyLocked = 0,
}) {
  return ListingModel(
    id: cardId * 100,
    sellerId: 'seller-1',
    slug: 'listing-$cardId',
    side: side,
    price: 25000,
    condition: CardCondition.nm,
    quantity: quantity,
    qtyLocked: qtyLocked,
    status: status,
    card: CardModel(
      id: cardId,
      category: CardCategory.pokemon,
      nameId: 'Kartu $cardId',
      expansionCode: 'SV2a',
      packSlug: 'sv2a',
      collectorNumber: '02$cardId/165',
      rarity: 'Rare',
    ),
    storeSlug: 'toko-ash',
    storeName: 'Toko Ash',
    isVerified: false,
    cityName: 'Jakarta',
    createdAt: DateTime(2026, 8, 1),
  );
}

Widget _host(List<ListingModel> listings, {int excludeCardId = 1}) {
  return ProviderScope(
    overrides: [
      storeListingsProvider('toko-ash').overrideWith((ref) async => listings),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ListView(
          children: [
            MoreFromSellerSection(
              storeHandle: 'toko-ash',
              excludeCardId: excludeCardId,
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the seller\'s other cards', (tester) async {
    await tester.pumpWidget(
      _host([_listing(cardId: 1), _listing(cardId: 2), _listing(cardId: 3)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lebih banyak dari penjual'), findsOneWidget);
    expect(find.text('Kartu 2'), findsOneWidget);
    expect(find.text('Kartu 3'), findsOneWidget);
  });

  testWidgets('never links back to the card being viewed', (tester) async {
    await tester.pumpWidget(
      _host([_listing(cardId: 1), _listing(cardId: 2)], excludeCardId: 1),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kartu 1'), findsNothing);
    expect(find.text('Kartu 2'), findsOneWidget);
  });

  testWidgets('excludes bids, closed listings and sold-out stock', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        _listing(cardId: 2, side: ListingSide.bid),
        _listing(cardId: 3, status: ListingStatus.cancelled),
        _listing(cardId: 4, quantity: 2, qtyLocked: 2),
        _listing(cardId: 5),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kartu 2'), findsNothing);
    expect(find.text('Kartu 3'), findsNothing);
    expect(find.text('Kartu 4'), findsNothing);
    expect(find.text('Kartu 5'), findsOneWidget);
  });

  testWidgets('a seller with nothing else shows no section at all', (
    tester,
  ) async {
    await tester.pumpWidget(_host([_listing(cardId: 1)], excludeCardId: 1));
    await tester.pumpAndSettle();

    expect(find.text('Lebih banyak dari penjual'), findsNothing);
  });

  testWidgets('renders inside a ListView without overflowing', (tester) async {
    await tester.pumpWidget(
      _host([for (var i = 2; i <= 14; i++) _listing(cardId: i)]),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
