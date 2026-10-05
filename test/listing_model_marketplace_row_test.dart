import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';

const _catalogImage = 'https://cdn.pokepedia.id/cards/sv1-001.webp';
const _sellerPhoto =
    'https://tlauakxyrxpwnwgdywum.supabase.co/storage/v1/object/public/listing-photos/u/a.webp';

Map<String, dynamic> _marketplaceRow({Object? photoUrls}) => {
  'id': 1,
  'user_id': 'seller-1',
  'slug': 'slug-1',
  'side': 'ask',
  'price': 10000,
  'condition': 'NM',
  'quantity': 1,
  'qty_locked': 0,
  'created_at': '2026-10-05T00:00:00Z',
  'card_id': 42,
  'card_name': 'Pikachu',
  'card_number': '001',
  'card_image': _catalogImage,
  'expansion_code': 'SV1',
  'photo_urls': photoUrls,
};

void main() {
  test('feed row keeps the seller photos and shows the first on the tile', () {
    final listing = ListingModel.fromMarketplaceRow(
      _marketplaceRow(photoUrls: [_sellerPhoto, '$_sellerPhoto?2']),
    );

    expect(listing.photoUrls, [_sellerPhoto, '$_sellerPhoto?2']);
    expect(listing.tileImageUrl, _sellerPhoto);
  });

  test('feed row without photos falls back to the catalog artwork', () {
    for (final photoUrls in [null, <String>[]]) {
      final listing = ListingModel.fromMarketplaceRow(
        _marketplaceRow(photoUrls: photoUrls),
      );

      expect(listing.photoUrls, isEmpty);
      expect(listing.tileImageUrl, _catalogImage);
    }
  });
}
