import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/seller/repository/seller_repository.dart';

/// The Jual tab shows Buka Toko only to a brand-new seller, as web's
/// `isBrandNewSeller` does. A store name has no say: web lets a seller skip
/// it and shows their username instead.
void main() {
  bool brandNew({bool active = false, int listings = 0, int sold = 0}) =>
      isBrandNewSeller(
        sellerActive: active,
        listingTotal: listings,
        itemsSold: sold,
      );

  test('nothing set up yet is brand new', () {
    expect(brandNew(), isTrue);
  });

  test('an active seller has a store, name or no name', () {
    expect(brandNew(active: true), isFalse);
  });

  test('any listing or draft means a store', () {
    expect(brandNew(listings: 1), isFalse);
  });

  test('a past sale means a store, even with nothing listed now', () {
    expect(brandNew(sold: 3), isFalse);
  });
}
