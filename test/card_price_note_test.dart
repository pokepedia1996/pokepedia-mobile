import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/shared/models/card_market_price.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/widgets/card_grid_item.dart';

/// The week's move only ever comes from a *confirmed* price with a week of
/// history behind it — `card_market_price_cache` leaves `price_7d_ago` null
/// on its ask and bid rows, and web gates its own badge the same way. Every
/// other priced card says where its number came from instead. These pin both
/// halves down, because on a catalog where almost every price is an ask the
/// difference between "correctly silent" and "broken" is invisible by eye.
CardModel _card({
  int? price = 20000,
  int? price7dAgo,
  CardPriceSource? source,
}) => CardModel(
  id: 1,
  category: CardCategory.pokemon,
  nameId: 'Oricorio ex',
  expansionCode: 'SV2a',
  packSlug: 'sv2a',
  collectorNumber: '018/103',
  rarity: 'Rare',
  marketPrice: price,
  price7dAgo: price7dAgo,
  priceSource: source,
);

Future<void> _pump(WidgetTester tester, CardModel card) async {
  tester.view.physicalSize = const Size(1170, 3000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 260,
            child: CardGridItem(card: card, onTap: () {}),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a confirmed price with a week behind it shows its move', (
    tester,
  ) async {
    await _pump(
      tester,
      _card(
        price: 20000,
        price7dAgo: 10000,
        source: CardPriceSource.confirmed,
      ),
    );

    expect(
      find.textContaining('↑100.0%', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('7H', findRichText: true), findsOneWidget);
  });

  testWidgets('a fall reads as one', (tester) async {
    await _pump(
      tester,
      _card(price: 8000, price7dAgo: 10000, source: CardPriceSource.confirmed),
    );

    expect(find.textContaining('↓20.0%', findRichText: true), findsOneWidget);
  });

  testWidgets('an ask price says so instead of showing a trend', (
    tester,
  ) async {
    // What the catalog is mostly made of: a price taken from the cheapest
    // open listing, which is one seller's number rather than a market. The
    // 7d figure is deliberately present and deliberately ignored — the cache
    // never sets one on an ask row, and a trend drawn through one listing
    // would be a lie however the data arrived.
    await _pump(
      tester,
      _card(price: 20000, price7dAgo: 10000, source: CardPriceSource.ask),
    );

    expect(find.textContaining('%', findRichText: true), findsNothing);
    expect(find.text('Rp20.000'), findsOneWidget);
    expect(find.text('Termurah'), findsOneWidget);
  });

  testWidgets('a bid price says so too', (tester) async {
    await _pump(tester, _card(source: CardPriceSource.bid));

    expect(find.text('Tertinggi'), findsOneWidget);
  });

  testWidgets('a first-week confirmed price reads as new', (tester) async {
    // Priced from real sales, but the cache has nothing from a week ago to
    // compare against — the state every priced card in the catalog is in
    // until its sales are seven days old.
    await _pump(tester, _card(source: CardPriceSource.confirmed));

    expect(find.textContaining('%', findRichText: true), findsNothing);
    expect(find.text('Baru'), findsOneWidget);
  });

  testWidgets('an unpriced card says nothing at all', (tester) async {
    await _pump(tester, _card(price: null));

    expect(find.text('Rp-'), findsOneWidget);
    expect(find.text('Termurah'), findsNothing);
    expect(find.text('Baru'), findsNothing);
  });
}
