import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/cart/repository/cart_repository.dart';
import 'package:pokepedia_mobile/features/chat/repository/models/chat_models.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/order_model.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/pending_checkout.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/listing_offer.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';

const _photo =
    'https://tlauakxyrxpwnwgdywum.supabase.co/storage/v1/object/public/listing-photos/u/a.webp';

/// A `listings` row of kind `custom`: no card, no condition, a title and
/// photos instead.
Map<String, dynamic> _customListingRow() => {
  'id': 7,
  'user_id': 'seller-1',
  'slug': 'custom-slug',
  'side': 'ask',
  'price': 2900000,
  'condition': null,
  'card_id': null,
  'variant_key': null,
  'quantity': 3,
  'qty_locked': 1,
  'status': 'open',
  'created_at': '2026-11-23T00:00:00Z',
  'kind': 'custom',
  'title': 'Paket Charizard & Pikachu',
  'photo_urls': [_photo, '$_photo?2'],
};

const _pikachu = CardModel(
  id: 42,
  category: CardCategory.pokemon,
  nameId: 'Pikachu',
  expansionCode: 'SV1',
  packSlug: 'sv1',
  collectorNumber: '001',
  rarity: 'Rare',
);

void main() {
  group('CardModel.custom', () {
    test('is named by the title and drawn with the first photo', () {
      final card = CardModel.customFromRow({
        'title': 'Binder 9-pocket',
        'photo_urls': [42, _photo, '$_photo?2'],
      });

      expect(card.isCustom, isTrue);
      expect(card.name, 'Binder 9-pocket');
      expect(card.imageUrl, _photo);
      expect(card.id, 0);
      expect(card.collectorNumber, isEmpty);
      expect(card.expansionCode, isEmpty);
    });

    test(
      'a row whose listing the viewer can no longer read still has a name',
      () {
        expect(CardModel.customFromRow(const {}).name, 'Listing custom');
      },
    );

    test('has no grade; a catalog card does', () {
      expect(
        CardModel.customFromRow(_customListingRow()).hasCondition,
        isFalse,
      );
      expect(_pikachu.hasCondition, isTrue);
    });
  });

  group('market feed row', () {
    test('a custom row without a card_id parses instead of throwing', () {
      final listing = ListingModel.fromMarketplaceRow({
        ..._customListingRow(),
        'username': 'toko',
      });

      expect(listing.isCustom, isTrue);
      expect(listing.card.name, 'Paket Charizard & Pikachu');
      expect(listing.tileImageUrl, _photo);
      expect(listing.price, 2900000);
      expect(listing.available, 2);
    });

    test('a card row is still a catalog card', () {
      final listing = ListingModel.fromMarketplaceRow({
        'id': 1,
        'user_id': 'seller-1',
        'slug': 's',
        'side': 'ask',
        'price': 10000,
        'condition': 'NM',
        'quantity': 1,
        'qty_locked': 0,
        'created_at': '2026-10-05T00:00:00Z',
        'card_id': 42,
        'card_name': 'Pikachu',
        'kind': 'card',
      });

      expect(listing.isCustom, isFalse);
      expect(listing.card.id, 42);
    });
  });

  group('cart', () {
    test('keeps a custom line, with its seller from get_store_identities', () {
      final listing = CartRepository.listingFromCartRow(
        _customListingRow(),
        cardById: const {},
        profile: {'username': 'seller_user', 'avatar_url': null},
        store: {
          'store_slug': 'toko-user1',
          'store_name': 'Toko User1',
          'store_logo_url': null,
        },
      );

      expect(listing, isNotNull);
      expect(listing!.isCustom, isTrue);
      expect(listing.card.name, 'Paket Charizard & Pikachu');
      expect(listing.card.imageUrl, _photo);
      expect(listing.storeName, 'Toko User1');
      expect(listing.price, 2900000);
    });

    test('a card line whose card is gone is still dropped', () {
      final listing = CartRepository.listingFromCartRow(
        {..._customListingRow(), 'kind': 'card', 'card_id': 42},
        cardById: const {},
        profile: null,
        store: null,
      );

      expect(listing, isNull);
    });

    test('a card line is built from its card', () {
      final listing = CartRepository.listingFromCartRow(
        {..._customListingRow(), 'kind': 'card', 'card_id': 42},
        cardById: {42: _pikachu},
        profile: null,
        store: null,
      );

      expect(listing?.card.name, 'Pikachu');
      expect(listing?.isCustom, isFalse);
    });
  });

  group('order item', () {
    Map<String, dynamic> orderItem({
      Map<String, dynamic>? cards,
      String? title,
    }) => {
      'id': 5,
      'slug': 'item-slug',
      'order_number': 'ORD-1',
      'card_id': cards == null ? null : 42,
      'matched_quantity': 1,
      'match_price': 2900000,
      'status': 'pending',
      'created_at': '2026-11-23T00:00:00Z',
      'title': title,
      'photo_urls': title == null ? null : [_photo],
      'cards': cards,
      'settlements': {'condition': null, 'escrow_amount': 2900000},
    };

    test('a custom item shows its title and photo, not a missing card', () {
      final item = OrderItemModel.fromRow(orderItem(title: 'Paket Charizard'));

      expect(item.card.isCustom, isTrue);
      expect(item.card.name, 'Paket Charizard');
      expect(item.card.imageUrl, _photo);
    });

    test('an item whose card was deleted keeps the old placeholder', () {
      final item = OrderItemModel.fromRow(orderItem());

      expect(item.card.isCustom, isFalse);
      expect(item.card.name, 'Kartu tidak ditemukan');
    });

    test('a card item reads its card', () {
      final item = OrderItemModel.fromRow(
        orderItem(
          cards: {
            'id': 42,
            'name_id': 'Pikachu',
            'expansion_code': 'SV1',
            'collector_number': '001',
          },
        ),
      );

      expect(item.card.name, 'Pikachu');
      expect(item.card.isCustom, isFalse);
    });
  });

  group('seller offer', () {
    Map<String, dynamic> offerRow({
      Object? cardId,
      Map<String, dynamic>? cards,
      Map<String, dynamic>? listing,
    }) => {
      'slug': 'offer-1',
      'status': 'pending',
      'quantity': 1,
      'listing_price': 2900000,
      'current_price': 2500000,
      'last_actor': 'buyer',
      'expires_at': '2026-12-01T00:00:00Z',
      'created_at': '2026-11-23T00:00:00Z',
      'card_id': cardId,
      'cards': cards,
      'listings': listing,
    };

    test('an offer on a custom listing parses instead of throwing', () {
      final offer = ListingOffer.fromRow(
        offerRow(
          listing: {
            'slug': 'custom-slug',
            'kind': 'custom',
            'title': 'Paket Charizard',
            'photo_urls': [_photo],
          },
        ),
      );

      expect(offer.isCustom, isTrue);
      expect(offer.cardId, isNull);
      expect(offer.cardName, 'Paket Charizard');
      expect(offer.cardImageUrl, _photo);
      expect(offer.listingSlug, 'custom-slug');
    });

    test('keeps a name when the listing is no longer readable', () {
      final offer = ListingOffer.fromRow(offerRow());

      expect(offer.isCustom, isTrue);
      expect(offer.cardName, 'Listing custom');
    });

    test('an offer on a card is unchanged', () {
      final offer = ListingOffer.fromRow(
        offerRow(
          cardId: 42,
          cards: {'id': 42, 'name_id': 'Pikachu', 'expansion_code': 'SV1'},
          listing: {'slug': 'card-slug'},
        ),
      );

      expect(offer.isCustom, isFalse);
      expect(offer.cardId, 42);
      expect(offer.cardName, 'Pikachu');
    });
  });

  group('chat listing context', () {
    test('survives a null card_id, which is what a custom listing sends', () {
      final context = ChatListingContext.fromJson({
        'listing_order_id': 7,
        'card_id': null,
        'card_name': 'Paket Charizard',
        'card_image': _photo,
        'price_idr': 2900000,
      });

      expect(context, isNotNull);
      expect(context!.cardId, isNull);
      expect(context.cardName, 'Paket Charizard');
      expect(context.priceIdr, 2900000);
    });

    test('still needs the listing it is about', () {
      expect(
        ChatListingContext.fromJson({'card_id': 42, 'card_name': 'Pikachu'}),
        isNull,
      );
    });
  });

  group('pending checkout line', () {
    PendingCheckoutItem item({String expansion = '', String number = ''}) =>
        PendingCheckoutItem(
          cardId: 0,
          cardName: 'Paket Charizard',
          expansionCode: expansion,
          collectorNumber: number,
          price: 2900000,
          quantity: 2,
        );

    test('leaves out the set and number a custom listing does not have', () {
      expect(item().summaryLine, '×2');
    });

    test('keeps them for a card', () {
      expect(
        item(expansion: 'sv1', number: '001').summaryLine,
        'SV1 · #001 · ×2',
      );
    });
  });
}
