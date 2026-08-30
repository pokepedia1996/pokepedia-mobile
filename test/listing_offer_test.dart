import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/listing_offer.dart';

Map<String, dynamic> _row({
  String slug = 'offer-1',
  String status = 'pending',
  String lastActor = 'buyer',
  String listingSlug = 'listing-1',
  int? orderItemId,
  String? orderItemStatus,
  DateTime? expiresAt,
  int sellerCounterCount = 0,
  int currentPrice = 80000,
  int listingPrice = 100000,
  List<Map<String, dynamic>>? history,
}) => {
  'slug': slug,
  'status': status,
  'quantity': 2,
  'listing_price': listingPrice,
  'current_price': currentPrice,
  'last_actor': lastActor,
  'buyer_counter_count': 1,
  'seller_counter_count': sellerCounterCount,
  'condition': 'NM',
  'variant_key': null,
  'message': 'Boleh kurang?',
  'history': history,
  'rejection_note': null,
  'expires_at': (expiresAt ?? DateTime.now().add(const Duration(days: 1)))
      .toIso8601String(),
  'responded_at': null,
  'created_at': DateTime(2026, 8, 1).toIso8601String(),
  'seen_at': null,
  'buyer_id': 'buyer-1',
  'card_id': 7,
  'order_item_id': orderItemId,
  'listings': {'slug': listingSlug},
  'cards': {
    'id': 7,
    'name_id': 'Charizard ex',
    'image_url': 'https://example.test/c.png',
    'expansion_code': 'SV2a',
    'collector_number': '201/165',
    'variant': 'normal',
  },
  'order_items': orderItemStatus == null ? null : {'status': orderItemStatus},
};

void main() {
  group('bucket', () {
    test('a buyer\'s open offer is the seller\'s to answer', () {
      final offer = ListingOffer.fromRow(_row(lastActor: 'buyer'));
      expect(offer.bucket, OfferBucket.received);
      expect(offer.needsSellerResponse, isTrue);
      expect(offer.waitingOnBuyer, isFalse);
    });

    test('after the seller counters it is the buyer\'s move', () {
      // Same status, different last actor — the distinction the whole
      // "Perlu dibalas" badge rests on.
      final offer = ListingOffer.fromRow(_row(lastActor: 'seller'));
      expect(offer.bucket, OfferBucket.sent);
      expect(offer.needsSellerResponse, isFalse);
      expect(offer.waitingOnBuyer, isTrue);
    });

    test('accepted but unpaid is waiting on money, not on anyone', () {
      final offer = ListingOffer.fromRow(_row(status: 'accepted'));
      expect(offer.paymentState, OfferPaymentState.awaiting);
      expect(offer.bucket, OfferBucket.awaitingPayment);
    });

    test('accepted with an order item behind it is paid', () {
      final offer = ListingOffer.fromRow(
        _row(status: 'accepted', orderItemId: 12, orderItemStatus: 'paid'),
      );
      expect(offer.paymentState, OfferPaymentState.paid);
      expect(offer.bucket, OfferBucket.completed);
    });

    test('a cancelled order item reads as cancelled, not paid', () {
      final offer = ListingOffer.fromRow(
        _row(status: 'accepted', orderItemId: 12, orderItemStatus: 'cancelled'),
      );
      expect(offer.paymentState, OfferPaymentState.cancelled);
    });

    test('accepted but past its deadline expired instead of waiting', () {
      final offer = ListingOffer.fromRow(
        _row(
          status: 'accepted',
          expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      );
      expect(offer.paymentState, OfferPaymentState.expired);
      expect(offer.bucket, OfferBucket.completed);
    });

    test('rejected and withdrawn both settle into Selesai', () {
      for (final status in ['rejected', 'withdrawn', 'expired']) {
        expect(
          ListingOffer.fromRow(_row(status: status)).bucket,
          OfferBucket.completed,
          reason: status,
        );
      }
    });
  });

  group('status label', () {
    test('an accepted offer is described by where the money got to', () {
      // "Diterima" stops being the useful fact the moment it is true.
      final offer = ListingOffer.fromRow(_row(status: 'accepted'));
      expect(offer.statusLabel, 'Menunggu Bayar');
    });

    test('anything else falls back to the offer status', () {
      expect(ListingOffer.fromRow(_row()).statusLabel, 'Menunggu');
      expect(
        ListingOffer.fromRow(_row(status: 'rejected')).statusLabel,
        'Ditolak',
      );
    });
  });

  group('counter limit', () {
    test('the seller can counter until they have used five', () {
      expect(
        ListingOffer.fromRow(_row(sellerCounterCount: 4)).canCounter,
        isTrue,
      );
      expect(
        ListingOffer.fromRow(_row(sellerCounterCount: 5)).canCounter,
        isFalse,
      );
    });

    test('the buyer\'s counters do not spend the seller\'s allowance', () {
      // Web tracks the two sides separately; sharing one budget would cut
      // the seller off after a chatty buyer.
      final offer = ListingOffer.fromRow(_row(sellerCounterCount: 0));
      expect(offer.buyerCounterCount, 1);
      expect(offer.canCounter, isTrue);
    });
  });

  group('buildOfferCounts', () {
    test('counts only what the seller could still act on', () {
      final counts = buildOfferCounts([
        ListingOffer.fromRow(_row(slug: 'a')),
        ListingOffer.fromRow(_row(slug: 'b', status: 'accepted')),
        // Settled — a badge here would read as outstanding work.
        ListingOffer.fromRow(_row(slug: 'c', status: 'rejected')),
        ListingOffer.fromRow(_row(slug: 'd', status: 'withdrawn')),
      ]);

      expect(counts['listing-1']!.total, 2);
    });

    test('needsResponse tracks only the seller\'s turn', () {
      final counts = buildOfferCounts([
        ListingOffer.fromRow(_row(slug: 'a', lastActor: 'buyer')),
        ListingOffer.fromRow(_row(slug: 'b', lastActor: 'seller')),
      ]);

      expect(counts['listing-1']!.total, 2);
      expect(counts['listing-1']!.needsResponse, 1);
    });

    test('splits by listing', () {
      final counts = buildOfferCounts([
        ListingOffer.fromRow(_row(slug: 'a', listingSlug: 'one')),
        ListingOffer.fromRow(_row(slug: 'b', listingSlug: 'two')),
        ListingOffer.fromRow(_row(slug: 'c', listingSlug: 'two')),
      ]);

      expect(counts['one']!.total, 1);
      expect(counts['two']!.total, 2);
    });

    test(
      'an offer with no listing slug is dropped rather than keyed empty',
      () {
        // A blank key would collect unrelated offers into one phantom badge.
        final counts = buildOfferCounts([
          ListingOffer.fromRow(_row(listingSlug: '')),
        ]);
        expect(counts, isEmpty);
      },
    );
  });

  group('pickDefaultOffer', () {
    test('the offer needing an answer wins over a newer one', () {
      final needsResponse = ListingOffer.fromRow(
        _row(slug: 'old', lastActor: 'buyer'),
      );
      final waiting = ListingOffer.fromRow(
        _row(slug: 'new', lastActor: 'seller'),
      );

      expect(pickDefaultOffer([waiting, needsResponse])!.slug, 'old');
    });

    test('nothing to pick from an empty list', () {
      expect(pickDefaultOffer([]), isNull);
    });
  });

  test('history parses into ordered moves', () {
    final offer = ListingOffer.fromRow(
      _row(
        history: [
          {
            'actor': 'buyer',
            'action': 'offer',
            'price': 80000,
            'at': DateTime(2026, 8, 1).toIso8601String(),
          },
          {
            'actor': 'seller',
            'action': 'counter',
            'price': 90000,
            'message': 'Segini ya',
            'at': DateTime(2026, 8, 2).toIso8601String(),
          },
        ],
      ),
    );

    expect(offer.history, hasLength(2));
    expect(offer.history.first.actor, OfferActor.buyer);
    expect(offer.history.last.action, OfferAction.counter);
    expect(offer.history.last.message, 'Segini ya');
  });

  test('a null history is empty, not a crash', () {
    // The column is nullable jsonb and old rows predate it.
    expect(ListingOffer.fromRow(_row(history: null)).history, isEmpty);
  });

  test('priceDropped marks an offer under the listing price', () {
    expect(
      ListingOffer.fromRow(
        _row(currentPrice: 80000, listingPrice: 100000),
      ).priceDropped,
      isTrue,
    );
    expect(
      ListingOffer.fromRow(
        _row(currentPrice: 100000, listingPrice: 100000),
      ).priceDropped,
      isFalse,
    );
  });
}
