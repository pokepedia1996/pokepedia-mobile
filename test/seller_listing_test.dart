import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/seller_listing.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';

Map<String, dynamic> _row({
  int quantity = 3,
  int qtyLocked = 0,
  String status = 'open',
  String? archivedAt,
  bool acceptsOffers = false,
  String? expiresAt = '2099-09-01T10:00:00+00:00',
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
    'expires_at': expiresAt,
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
    // The predicates are the SQL twin of web's `listing-buckets.ts`, so the
    // two clients agree on what "aktif" means.
    test('an open, unexpired listing is active', () {
      final listing = SellerListing.fromRow(_row(status: 'open'));
      expect(listing.bucket, SellerListingBucket.active);
    });

    test('an open listing past its expiry is inactive, not active', () {
      final listing = SellerListing.fromRow(
        _row(status: 'open', expiresAt: '2020-01-01T00:00:00+00:00'),
      );
      expect(listing.isExpired, isTrue);
      expect(listing.bucket, SellerListingBucket.inactive);
    });

    test('sold and expired statuses are inactive', () {
      for (final status in ['matched', 'expired']) {
        expect(
          SellerListing.fromRow(_row(status: status)).bucket,
          SellerListingBucket.inactive,
          reason: status,
        );
      }
    });

    test('archived wins over whatever status the row kept', () {
      final listing = SellerListing.fromRow(
        _row(status: 'open', archivedAt: '2026-08-20T09:00:00+00:00'),
      );
      expect(listing.bucket, SellerListingBucket.archived);
    });
  });

  group('SellerListingBucket', () {
    test('only the three listing buckets read the listings table', () {
      expect(
        SellerListingBucket.values.where((b) => b.isListingBucket),
        [
          SellerListingBucket.active,
          SellerListingBucket.inactive,
          SellerListingBucket.archived,
        ],
      );
      // Draft reads `listing_drafts`, Preferensi reads no list at all —
      // filtering them through the listings query would show the wrong rows.
      expect(SellerListingBucket.draft.isListingBucket, isFalse);
      expect(SellerListingBucket.preferences.isListingBucket, isFalse);
    });

    test('every tab carries the line web prints under the heading', () {
      for (final bucket in SellerListingBucket.values) {
        expect(bucket.description, isNotEmpty, reason: bucket.name);
      }
    });
  });

  group('SellerDraft.fromRow', () {
    Map<String, dynamic> draftRow({
      Object? price = 90000,
      List<String> photos = const [],
    }) => {
      'id': 12,
      'price': price,
      'condition': 'NM',
      'quantity': 2,
      'photo_urls': photos,
      'updated_at': '2026-08-20T09:00:00+00:00',
      'cards': _row()['cards'],
    };

    test('maps a draft row with its joined card', () {
      final draft = SellerDraft.fromRow(draftRow(photos: const ['a', 'b']));
      expect(draft.id, 12);
      expect(draft.card.name, 'Charizard ex');
      expect(draft.condition, CardCondition.nm);
      expect(draft.quantity, 2);
      expect(draft.photoCount, 2);
      expect(draft.price, 90000);
    });

    test('price is nullable — a draft can exist before one is decided', () {
      final draft = SellerDraft.fromRow(draftRow(price: null));
      expect(draft.price, isNull);
    });

    test('a missing photo_urls array counts as no photos', () {
      final row = draftRow()..remove('photo_urls');
      expect(SellerDraft.fromRow(row).photoCount, 0);
    });
  });
}
