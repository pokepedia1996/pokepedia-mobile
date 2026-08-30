import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/market/repository/market_repository.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';

ListingModel _listing({required String sellerId, int id = 1}) => ListingModel(
  id: id,
  sellerId: sellerId,
  slug: 'listing-$id',
  side: ListingSide.ask,
  price: 100000,
  condition: CardCondition.nm,
  quantity: 1,
  qtyLocked: 0,
  card: CardModel(
    id: 7,
    category: CardCategory.pokemon,
    nameId: 'Charizard ex',
    expansionCode: 'SV2a',
    packSlug: 'sv2a',
    collectorNumber: '201/165',
    rarity: 'SAR',
  ),
  storeSlug: 'toko',
  storeName: 'Toko',
  isVerified: false,
  cityName: 'Jakarta',
  createdAt: DateTime(2026, 8, 1),
  status: ListingStatus.open,
);

void main() {
  group('excludeOwnListings', () {
    test('drops the viewer\'s own rows', () {
      final result = excludeOwnListings([
        _listing(sellerId: 'me', id: 1),
        _listing(sellerId: 'someone', id: 2),
        _listing(sellerId: 'me', id: 3),
      ], 'me');

      expect(result.map((l) => l.id), [2]);
    });

    test('keeps everything when signed out', () {
      // An anonymous browser owns nothing, so nothing is theirs to hide.
      final all = [
        _listing(sellerId: 'a', id: 1),
        _listing(sellerId: 'b', id: 2),
      ];
      expect(excludeOwnListings(all, null), hasLength(2));
      expect(excludeOwnListings(all, ''), hasLength(2));
    });

    test('a feed made entirely of your own listings comes back empty', () {
      // Not an error state — the empty view is the honest answer, and the
      // page already handles it.
      expect(
        excludeOwnListings([
          _listing(sellerId: 'me', id: 1),
          _listing(sellerId: 'me', id: 2),
        ], 'me'),
        isEmpty,
      );
    });

    test('matches on the exact id, not a prefix', () {
      // Ids are uuids; a substring match would hide a stranger's listing.
      final result = excludeOwnListings([
        _listing(sellerId: 'me-too', id: 1),
      ], 'me');
      expect(result, hasLength(1));
    });
  });
}
