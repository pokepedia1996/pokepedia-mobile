import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/market/presentation/widgets/store_poster.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';
import 'package:pokepedia_mobile/shared/models/store_model.dart';

/// The poster is captured to PNG and posted outside the app, so what it
/// claims has to be right — especially the overflow count, which is the one
/// number a reader can't check for themselves.
ListingModel _listing(int id, {ListingSide side = ListingSide.ask}) {
  return ListingModel(
    id: id,
    sellerId: 'seller-1',
    slug: 'listing-$id',
    side: side,
    price: 10000 * id,
    condition: CardCondition.nm,
    quantity: 1,
    card: const CardModel(
      id: 1,
      category: CardCategory.pokemon,
      nameId: 'Pikachu',
      expansionCode: 'SV2a',
      packSlug: 'sv2a',
      collectorNumber: '025/165',
      rarity: 'Rare',
    ),
    storeSlug: 'toko',
    storeName: 'Toko Ash',
    isVerified: false,
    cityName: 'Jakarta',
    createdAt: DateTime(2026, 8, 1),
  );
}

StoreModel _storeSold(int itemsSoldCount) => StoreModel(
  handle: 'toko-ash',
  storeName: 'Toko Ash',
  tagline: '',
  activeListingCount: 40,
  cityName: 'Jakarta',
  isVerified: true,
  topRated: true,
  itemsSoldCount: itemsSoldCount,
  followersCount: 12,
);

const _store = StoreModel(
  handle: 'toko-ash',
  storeName: 'Toko Ash',
  tagline: '',
  activeListingCount: 40,
  cityName: 'Jakarta',
  isVerified: true,
  topRated: true,
  itemsSoldCount: 79,
  followersCount: 12,
);

Widget _host({
  required List<ListingModel> listings,
  int? total,
  PosterSide side = PosterSide.wts,
  StoreModel store = _store,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: FittedBox(
        child: StorePoster(
          store: store,
          listings: listings,
          side: side,
          totalCount: total,
          positivePct: 100,
          feedbackScore: 17,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('carries the store identity and the side badge', (tester) async {
    await tester.pumpWidget(_host(listings: [_listing(1), _listing(2)]));

    expect(find.text('Toko Ash'), findsOneWidget);
    expect(find.text('WTS'), findsOneWidget);
    expect(find.text('Jakarta'), findsOneWidget);
    expect(find.text('79 terjual'), findsOneWidget);
    expect(find.text('100% positif'), findsOneWidget);
    expect(find.text('pokepedia.id/market/toko-ash'), findsOneWidget);
  });

  testWidgets('WTB swaps the badge', (tester) async {
    await tester.pumpWidget(
      _host(
        listings: [_listing(1, side: ListingSide.bid)],
        side: PosterSide.wtb,
      ),
    );
    expect(find.text('WTB'), findsOneWidget);
    expect(find.text('WTS'), findsNothing);
  });

  testWidgets('the overflow tile counts what did not fit', (tester) async {
    // 112 listings, 12 tiles: 11 cards plus a "+101 lainnya".
    final listings = [
      for (var i = 1; i <= StorePoster.capacity; i++) _listing(i),
    ];
    await tester.pumpWidget(_host(listings: listings, total: 112));

    expect(find.text('+101'), findsOneWidget);
    expect(find.text('lainnya'), findsOneWidget);
  });

  testWidgets('the first poster counts the listings it leaves out', (
    tester,
  ) async {
    // What the sheet builds for page one: eleven cards and a tile saying
    // how much more the store is holding. 30 - 11 = 19.
    final listings = [
      for (var i = 1; i < StorePoster.capacity; i++) _listing(i),
    ];
    await tester.pumpWidget(_host(listings: listings, total: 30));

    expect(listings, hasLength(StorePoster.capacity - 1));
    expect(find.text('+19'), findsOneWidget);
    expect(find.text('lainnya'), findsOneWidget);
  });

  testWidgets('no overflow tile when everything fits', (tester) async {
    await tester.pumpWidget(
      _host(listings: [_listing(1), _listing(2)], total: 2),
    );
    expect(find.text('lainnya'), findsNothing);
  });

  testWidgets('a quiet store keeps its sales count to itself', (tester) async {
    // Under five sales the number reads as "nobody buys here" — worse for
    // the seller than saying nothing, which is what the poster does.
    await tester.pumpWidget(
      _host(listings: [_listing(1)], store: _storeSold(4)),
    );
    expect(find.textContaining('terjual'), findsNothing);
  });

  testWidgets('the threshold itself still shows', (tester) async {
    await tester.pumpWidget(
      _host(listings: [_listing(1)], store: _storeSold(5)),
    );
    expect(find.text('5 terjual'), findsOneWidget);
  });

  testWidgets('tiles label the condition by its short code', (tester) async {
    // The tile is ~245px wide and the price now sits on the art; the full
    // label would wrap into it.
    await tester.pumpWidget(_host(listings: [_listing(1)]));

    expect(find.text('NM'), findsOneWidget);
    expect(find.text(CardCondition.nm.label), findsNothing);
  });

  testWidgets('the price is painted over the card art', (tester) async {
    // Revision 1: stacked on the image rather than stealing a row beneath
    // it, so twelve tiles still fit at a readable size.
    await tester.pumpWidget(_host(listings: [_listing(3)]));

    final price = find.text('Rp30.000');
    expect(price, findsOneWidget);
    expect(
      find.ancestor(of: price, matching: find.byType(Stack)),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('renders at a fixed size regardless of the screen', (
    tester,
  ) async {
    // A poster that reflowed with the handset would produce a different
    // image per device for the same design.
    await tester.pumpWidget(_host(listings: [_listing(1)]));
    final size = tester.getSize(find.byType(StorePoster));
    expect(size.width, StorePoster.width);
    expect(size.height, StorePoster.height);
  });
}
