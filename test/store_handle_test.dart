import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/seller/repository/seller_repository.dart';
import 'package:pokepedia_mobile/shared/models/store_model.dart';

Map<String, dynamic> _detailRow({String? slug, String? username}) => {
  'user_id': 'seller-1',
  'store_name': 'Toko Ash',
  'store_slug': slug,
  'username': username,
  'store_tagline': 'Kartu langka',
  'city_name': 'Kota Bandung',
  'is_verified': false,
  'top_rated': false,
  'items_sold_count': 3,
  'followers_count': 1,
};

void main() {
  group('StoreModel.fromDetailRow handle', () {
    test('prefers the store slug', () {
      final store = StoreModel.fromDetailRow(
        _detailRow(slug: 'toko-ash', username: 'ash'),
        activeListingCount: 0,
      );
      expect(store.handle, 'toko-ash');
    });

    test('falls back to the username when the store has no slug', () {
      // `get_seller_storefront_by_username` resolves stores that never got a
      // slug. Without the fallback the handle is empty, and every link back
      // to this store — "more from seller", the market row, the cart's shop
      // line — pushes a route with nothing in it.
      final store = StoreModel.fromDetailRow(
        _detailRow(username: 'ash'),
        activeListingCount: 0,
      );
      expect(store.handle, 'ash');
    });

    test('an anonymous row still yields an empty handle, not a crash', () {
      final store = StoreModel.fromDetailRow(
        _detailRow(),
        activeListingCount: 0,
      );
      expect(store.handle, isEmpty);
    });
  });

  group('a blank slug counts as absent', () {
    test('detail rows fall through a blank slug to the username', () {
      // The crash this guards: a blank `store_slug` is not null, so a plain
      // `??` hands back '', the caller pushes `/market/`, and the route's
      // `pathParameters['handle']!` throws.
      final store = StoreModel.fromDetailRow(
        _detailRow(slug: '', username: 'ash'),
        activeListingCount: 0,
      );
      expect(store.handle, 'ash');
    });

    test('whitespace is blank too', () {
      final store = StoreModel.fromDetailRow(
        _detailRow(slug: '   ', username: 'ash'),
        activeListingCount: 0,
      );
      expect(store.handle, 'ash');
    });

    test('directory rows do the same', () {
      final store = StoreModel.fromDirectoryRow({
        'store_slug': '',
        'handle': 'ash',
        'store_name': 'Toko Ash',
      });
      expect(store.handle, 'ash');
    });
  });

  group('SellerIdentity.storeHandle', () {
    test('prefers the slug', () {
      const identity = SellerIdentity(username: 'ash', storeSlug: 'toko-ash');
      expect(identity.storeHandle, 'toko-ash');
    });

    test('a blank slug falls through to the username', () {
      const identity = SellerIdentity(username: 'ash', storeSlug: '');
      expect(identity.storeHandle, 'ash');
    });

    test('no slug and no username means no link at all', () {
      // The dashboard hides its "Toko" button on null; returning '' here
      // would show a button that routes nowhere.
      const identity = SellerIdentity(username: '', storeSlug: null);
      expect(identity.storeHandle, isNull);
    });
  });
}
