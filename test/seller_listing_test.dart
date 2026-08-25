import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/seller_listing.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';

Map<String, dynamic> _row({
  int quantity = 3,
  int qtyLocked = 0,
  String status = 'open',
  String? archivedAt,
  bool acceptsOffers = false,
}) {
  return {
    'id': 1,
    'slug': '9c0f3a10-2b44-4e91-8a77-1d5e6f2b3c40',
    'price': 125000,
    'condition': 'LP',
    'quantity': quantity,
    'qty_locked': qtyLocked,
    'status': status,
    'accepts_offers': acceptsOffers,
    'auto_relist': true,
    'view_count': 42,
    'created_at': '2026-08-01T10:00:00+00:00',
    'archived_at': archivedAt,
    'expires_at': '2026-09-01T10:00:00+00:00',
    'cards': {
      'id': 7,
      'name_id': 'Charizard ex',
      'expansion_code': 'SV2a',
      'collector_number': '201/165',
      'rarity': 'SAR',
      'category': 'Pokemon',
      'language': 'id',
      'variant': 'normal',
      'details': <String, dynamic>{},
    },
  };
}

void main() {
  group('SellerListing.fromRow', () {
    test('maps a listing row with its joined card', () {
      final listing = SellerListing.fromRow(_row());

      expect(listing.slug, '9c0f3a10-2b44-4e91-8a77-1d5e6f2b3c40');
      expect(listing.card.name, 'Charizard ex');
      expect(listing.price, 125000);
      expect(listing.condition, CardCondition.lp);
      expect(listing.viewCount, 42);
      expect(listing.autoRelist, isTrue);
      expect(listing.isArchived, isFalse);
    });

    test('available subtracts the quantity buyers have locked', () {
      // Locked stock is mid-checkout — still owned, not sellable.
      final listing = SellerListing.fromRow(_row(quantity: 3, qtyLocked: 2));
      expect(listing.available, 1);
      expect(listing.isOutOfStock, isFalse);
    });

    test('fully locked stock reads as out of stock', () {
      final listing = SellerListing.fromRow(_row(quantity: 2, qtyLocked: 2));
      expect(listing.available, 0);
      expect(listing.isOutOfStock, isTrue);
    });

    test('archived is a timestamp, not a status', () {
      // The row keeps `status: open` after archiving, which is why the
      // active bucket has to exclude archived rows explicitly.
      final listing = SellerListing.fromRow(
        _row(status: 'open', archivedAt: '2026-08-20T09:00:00+00:00'),
      );
      expect(listing.status, 'open');
      expect(listing.isArchived, isTrue);
    });
  });

  group('SellerListingBucket', () {
    test('every bucket but archive filters on a status', () {
      expect(SellerListingBucket.active.status, 'open');
      expect(SellerListingBucket.sold.status, 'matched');
      expect(SellerListingBucket.expired.status, 'expired');
      expect(SellerListingBucket.archived.status, isNull);
      expect(SellerListingBucket.archived.isArchived, isTrue);
    });
  });
}
