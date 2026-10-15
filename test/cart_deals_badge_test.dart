import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/cart_item.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/checkout_deal.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';

CartItem _item({int quantity = 3, int? offerPrice, int? remaining}) {
  return CartItem(
    cartItemId: 1,
    quantity: quantity,
    offerPrice: offerPrice,
    offerRemainingQty: remaining,
    listing: ListingModel(
      id: 7,
      sellerId: 'seller-1',
      slug: 'listing-7',
      side: ListingSide.ask,
      price: 50000,
      condition: CardCondition.nm,
      quantity: 5,
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
      storeName: 'Toko',
      isVerified: false,
      cityName: 'Jakarta',
      createdAt: DateTime(2026, 8, 1),
    ),
  );
}

void main() {
  group('accepted-offer pricing (web offerLineTotal)', () {
    test('no offer uses the list price', () {
      expect(_item().subtotal, 150000);
    });

    test('the offer price covers what the offer still allows', () {
      // Two of three units at the offer price, the third at list price.
      expect(_item(offerPrice: 40000, remaining: 2).subtotal, 130000);
    });

    test('an offer covering more than the line prices every unit', () {
      expect(_item(offerPrice: 40000, remaining: 9).subtotal, 120000);
    });
  });

  group('deal kind', () {
    Map<String, dynamic> row(String? kind) => {
      'external_id': 'INV-BID-1',
      'kind': ?kind,
      'cart_snapshot': [
        {
          'seller_id': 's1',
          'card_name': 'Poffin',
          'price': 30000,
          'quantity': 1,
        },
      ],
    };

    test('reads the row kind, defaulting to bid', () {
      expect(CheckoutDeal.fromCartRow(row('combined'))!.kind, 'combined');
      expect(CheckoutDeal.fromCartRow(row(null))!.kind, 'bid');
    });
  });
}
