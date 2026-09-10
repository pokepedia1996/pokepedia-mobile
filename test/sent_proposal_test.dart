import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/bid_proposal_model.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/sent_proposal.dart';

Map<String, dynamic> _row({
  String status = 'pending',
  Object? proposedPrice = 120000,
  int bidPrice = 100000,
  int quantity = 2,
  String? expiresAt = '2099-09-01T10:00:00+00:00',
}) {
  return {
    'slug': 'c0ffee00-0000-4000-8000-000000000001',
    'status': status,
    'proposed_quantity': quantity,
    'proposed_price': proposedPrice,
    'condition': 'LP',
    'message': 'Ada stok NM juga',
    'created_at': '2026-08-20T09:00:00+00:00',
    'expires_at': expiresAt,
    'bid': {
      'id': 42,
      'price': bidPrice,
      'user_id': 'buyer-1',
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
    },
  };
}

void main() {
  group('SentProposalModel.fromRow', () {
    test('maps the proposal and the bid it answers', () {
      final proposal = SentProposalModel.fromRow(_row(), buyerUsername: 'ash');
      expect(proposal.card.name, 'Charizard ex');
      expect(proposal.bidPrice, 100000);
      expect(proposal.proposedPrice, 120000);
      expect(proposal.proposedQuantity, 2);
      expect(proposal.buyerUsername, 'ash');
      expect(proposal.status, BidProposalStatus.pending);
    });

    test('a buyer with no username still renders', () {
      expect(SentProposalModel.fromRow(_row()).buyerUsername, isNull);
    });
  });

  group('price presentation', () {
    test('no counter-offer means the bid price stands', () {
      // Accepting the bid as-is stores no proposed_price.
      final proposal = SentProposalModel.fromRow(_row(proposedPrice: null));
      expect(proposal.effectivePrice, 100000);
      expect(proposal.isCounterOffer, isFalse);
    });

    test('asking more than the bid strikes the bid price through', () {
      final proposal = SentProposalModel.fromRow(_row(proposedPrice: 120000));
      expect(proposal.effectivePrice, 120000);
      expect(proposal.isCounterOffer, isTrue);
    });

    test('asking less is not a counter-offer for display purposes', () {
      // Web only strikes through when the seller asked for *more*; a lower
      // ask needs no comparison drawn.
      final proposal = SentProposalModel.fromRow(_row(proposedPrice: 90000));
      expect(proposal.effectivePrice, 90000);
      expect(proposal.isCounterOffer, isFalse);
    });
  });

  group('dismissal', () {
    test('a pending proposal cannot be cleared', () {
      // `dismiss_bid_proposal` returns proposal_still_pending, so the button
      // must not be offered.
      expect(SentProposalModel.fromRow(_row()).isDismissible, isFalse);
    });

    test('every settled status can be cleared', () {
      for (final status in ['accepted', 'rejected', 'expired', 'withdrawn']) {
        expect(
          SentProposalModel.fromRow(_row(status: status)).isDismissible,
          isTrue,
          reason: status,
        );
      }
    });
  });

  group('BidProposalStatusX.fromRaw', () {
    test('maps every status the table stores', () {
      expect(
        BidProposalStatusX.fromRaw('accepted'),
        BidProposalStatus.accepted,
      );
      expect(
        BidProposalStatusX.fromRaw('rejected'),
        BidProposalStatus.rejected,
      );
      expect(BidProposalStatusX.fromRaw('expired'), BidProposalStatus.expired);
      expect(
        BidProposalStatusX.fromRaw('withdrawn'),
        BidProposalStatus.withdrawn,
      );
    });

    test('an unknown status reads as pending, not a crash', () {
      expect(BidProposalStatusX.fromRaw(null), BidProposalStatus.pending);
      expect(
        BidProposalStatusX.fromRaw('renegotiating'),
        BidProposalStatus.pending,
      );
    });
  });
}
