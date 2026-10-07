import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/expansions/repository/expansions_repository.dart';
import 'package:pokepedia_mobile/features/expansions/repository/models/store_identity.dart';
import 'package:pokepedia_mobile/features/expansions/repository/models/trading_models.dart';
import 'package:pokepedia_mobile/features/market/repository/models/store_feedback.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';

/// The trading surfaces read other users' rows through RPCs because RLS
/// hides them from direct reads (`seller_profiles` is self-select only,
/// `listings` needs a session). These pin the row shapes each RPC returns
/// to what the app builds from them.
void main() {
  group('get_bid_proposal_level', () {
    test('reads every count the RPC returns', () {
      final level = BidProposalLevel.fromRow({
        'buyer_count': 3,
        'available_qty': 7,
        'eligible_count': 1,
        'eligible_qty': 2,
        'already_proposed_count': 2,
      });

      expect(level.buyerCount, 3);
      expect(level.availableQty, 7);
      expect(level.eligibleCount, 1);
      expect(level.eligibleQty, 2);
      expect(level.alreadyProposedCount, 2);
      expect(level.isEmpty, isFalse);
      expect(level.allProposed, isFalse);
    });

    test('a level the seller proposed to in full has nobody left', () {
      final level = BidProposalLevel.fromRow({
        'buyer_count': 2,
        'available_qty': 4,
        'eligible_count': 0,
        'eligible_qty': 0,
        'already_proposed_count': 2,
      });

      expect(level.allProposed, isTrue);
    });

    test('a null or malformed payload reads as an empty level', () {
      expect(BidProposalLevel.fromRow(null).isEmpty, isTrue);
      expect(BidProposalLevel.fromRow(const []).isEmpty, isTrue);
      expect(BidProposalLevel.fromRow({'buyer_count': null}).isEmpty, isTrue);
    });
  });

  group('get_store_identities', () {
    test('keys rows by user id and skips rows without one', () {
      final stores = StoreIdentity.parseRows([
        {
          'user_id': 'u1',
          'store_name': 'Toko Satu',
          'store_slug': 'toko-satu',
          'store_logo_url': null,
        },
        {'store_name': 'No owner'},
      ]);

      expect(stores.keys, ['u1']);
      expect(stores['u1']!.storeName, 'Toko Satu');
      expect(stores['u1']!.storeSlug, 'toko-satu');
      expect(stores['u1']!.storeLogoUrl, isNull);
    });

    test('a non-list result reads as no storefronts', () {
      expect(StoreIdentity.parseRows(null), isEmpty);
      expect(StoreIdentity.parseRows({'error': 'x'}), isEmpty);
    });
  });

  group('matching asks', () {
    final row = {
      'slug': 'ask-1',
      'card_id': 42,
      'price': 150000,
      'condition': 'LP',
      'quantity': 3,
      'qty_locked': 1,
      'user_id': 'u1',
    };

    test('names the seller by their storefront when they have one', () {
      final ask = MatchingAsk.fromRow(
        row,
        store: const StoreIdentity(
          userId: 'u1',
          storeName: 'Toko Satu',
          storeSlug: 'toko-satu',
        ),
        username: 'satu',
      );

      expect(ask.slug, 'ask-1');
      expect(ask.cardId, 42);
      expect(ask.price, 150000);
      expect(ask.condition, CardCondition.lp);
      expect(ask.available, 2);
      expect(ask.storeName, 'Toko Satu');
      expect(ask.storeSlug, 'toko-satu');
    });

    test('falls back to the username without a storefront', () {
      final ask = MatchingAsk.fromRow(row, username: 'satu');

      expect(ask.storeName, 'satu');
      expect(ask.storeSlug, 'satu');
    });
  });

  group('get_card_listings', () {
    final card = CardModel.fromRow({
      'id': 42,
      'name_id': 'Pikachu',
      'expansion_code': 'SV1',
      'collector_number': '025',
    });
    final row = {
      'id': 9,
      'slug': '6f1c1f5e-2b9a-4f4e-9d1c-3b1a2c3d4e5f',
      'price': 120000,
      'condition': 'NM',
      'created_at': '2026-10-01T03:00:00+00:00',
      'user_id': 'u1',
      'photo_urls': ['https://cdn.example.com/a.jpg'],
      'quantity': 4,
      'qty_locked': 1,
      'available': 3,
      'total_count': 12,
      'min_price': 100000,
      'accepts_offers': true,
      'variant_key': null,
      'has_next': true,
    };

    test('builds an open ask with the seller resolved from the side reads', () {
      final listing = cardListingFromRow(
        row,
        card: card,
        store: const StoreIdentity(
          userId: 'u1',
          storeName: 'Toko Satu',
          storeSlug: 'toko-satu',
        ),
        profile: {'username': 'satu', 'avatar_url': null},
        reputation: {'positive_count_total': 10, 'negative_count_total': 3},
      );

      expect(listing.id, 9);
      expect(listing.side, ListingSide.ask);
      expect(listing.status, ListingStatus.open);
      expect(listing.sellerId, 'u1');
      expect(listing.price, 120000);
      expect(listing.condition, CardCondition.nm);
      expect(listing.available, 3);
      expect(listing.acceptsOffers, isTrue);
      expect(listing.photoUrls, hasLength(1));
      expect(listing.storeName, 'Toko Satu');
      expect(listing.storeSlug, 'toko-satu');
      expect(listing.sellerUsername, 'satu');
      expect(listing.sellerFeedbackScore, 7);
      expect(listing.card.id, 42);
    });

    test('a seller with no storefront or profile still renders', () {
      final listing = cardListingFromRow(row, card: card);

      expect(listing.storeName, 'Penjual');
      expect(listing.storeSlug, isEmpty);
      expect(listing.sellerFeedbackScore, 0);
    });
  });

  group('get_feedback_list', () {
    test('reads the rows of the {total, rows} payload', () {
      final feedback = StoreFeedback.parseList({
        'total': 2,
        'rows': [
          {
            'id': 5,
            'feedback': 'negative',
            'comment': 'Telat kirim',
            'reply': 'Maaf',
            'created_at': '2026-09-30T10:00:00+00:00',
            'is_auto': false,
            'item_count': 2,
            'rater_username': 'pembeli1',
          },
          {
            'id': 6,
            'feedback': 'positive',
            'comment': null,
            'reply': null,
            'created_at': '2026-09-29T10:00:00+00:00',
            'is_auto': true,
            'rater_username': null,
          },
        ],
      });

      expect(feedback, hasLength(2));
      expect(feedback.first.id, 5);
      expect(feedback.first.kind, FeedbackKind.negative);
      expect(feedback.first.comment, 'Telat kirim');
      expect(feedback.first.reply, 'Maaf');
      expect(feedback.first.raterUsername, 'pembeli1');
      expect(feedback.first.isAuto, isFalse);
      expect(feedback.last.kind, FeedbackKind.positive);
      expect(feedback.last.isAuto, isTrue);
      expect(feedback.last.raterUsername, isNull);
    });

    test('an empty or malformed payload reads as no reviews', () {
      expect(StoreFeedback.parseList(null), isEmpty);
      expect(StoreFeedback.parseList({'total': 0, 'rows': []}), isEmpty);
      expect(StoreFeedback.parseList({'rows': null}), isEmpty);
      expect(
        StoreFeedback.parseList({
          'rows': [
            {'feedback': 'positive'},
          ],
        }),
        isEmpty,
      );
    });
  });
}
