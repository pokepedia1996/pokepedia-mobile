import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/expansions/repository/expansions_repository.dart';
import 'package:pokepedia_mobile/features/expansions/repository/models/store_identity.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';
import 'package:pokepedia_mobile/shared/widgets/seller_rating_badge.dart';

const _card = CardModel(
  id: 1,
  category: CardCategory.pokemon,
  nameId: 'Moltres',
  expansionCode: 'M-P',
  packSlug: 'm-p',
  collectorNumber: '028/M-P',
  rarity: 'Promo',
);

final _row = {
  'id': 5,
  'slug': 'ask-5',
  'price': 10000,
  'condition': 'NM',
  'quantity': 1,
  'qty_locked': 0,
  'user_id': 'u1',
  'created_at': '2026-10-01T00:00:00Z',
};

Future<void> _pump(WidgetTester tester, SellerRating? rating) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SellerRatingBadge(rating: rating)),
    ),
  );
}

void main() {
  test('a listing row carries the seller city and reputation', () {
    final listing = cardListingFromRow(
      _row,
      card: _card,
      store: StoreIdentity.fromRow(const {
        'user_id': 'u1',
        'store_name': 'Takumie',
        'city_name': 'Kota Bandung',
      }),
      reputation: const {
        'positive_pct': 98.5,
        'successful_trades': 37,
        'positive_count_total': 40,
        'neutral_count_12mo': 1,
        'negative_count_total': 1,
      },
    );

    expect(listing.cityName, 'Kota Bandung');
    expect(listing.sellerRating!.positivePct, 98.5);
    expect(listing.sellerRating!.totalSales, 37);
  });

  test('an older backend without city_name leaves the city blank', () {
    final listing = cardListingFromRow(
      _row,
      card: _card,
      store: StoreIdentity.fromRow(const {'user_id': 'u1'}),
    );
    expect(listing.cityName, '');
    expect(listing.sellerRating, isNull);
  });

  testWidgets('rating reads as web: percent and sales', (tester) async {
    await _pump(tester, const SellerRating(positivePct: 100, totalSales: 37));
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('37 penjualan'), findsOneWidget);
  });

  testWidgets('an unrated seller is "Penjual baru"', (tester) async {
    await _pump(tester, null);
    expect(find.text('Penjual baru'), findsOneWidget);
  });
}
