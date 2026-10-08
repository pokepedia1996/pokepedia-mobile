import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/bid_proposal_model.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/proposal_card_group.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/sent_proposal.dart';

const _card = <String, dynamic>{
  'id': 7,
  'name_id': 'Charizard ex',
  'expansion_code': 'SV2a',
  'collector_number': '201/165',
  'rarity': 'SAR',
  'category': 'Pokemon',
  'language': 'id',
  'variant': 'normal',
  'details': <String, dynamic>{},
};

/// The row shape `fetchSentProposals` selects, with both left-joined embeds.
Map<String, dynamic> _row({
  Map<String, dynamic>? bid,
  Map<String, dynamic>? match,
  String status = 'accepted',
  Object? proposedPrice = 150000,
}) => {
  'slug': 'prop-1',
  'status': status,
  'proposed_quantity': 2,
  'proposed_price': proposedPrice,
  'condition': 'NM',
  'message': null,
  'seen_at': null,
  'photos': const ['https://x/a.jpg'],
  'created_at': '2026-09-01T09:00:00+00:00',
  'expires_at': '2026-09-03T09:00:00+00:00',
  'bid': bid,
  'match': match,
};

void main() {
  group('a sent proposal whose bid the seller can no longer read', () {
    test('recovers card and buyer from the match it produced', () {
      final row = _row(match: {'bid_user_id': 'buyer-9', 'card': _card});
      final p = SentProposalModel.fromRow(row, buyerUsername: 'ash');

      expect(p.hasCard, isTrue);
      expect(p.card.id, 7);
      expect(p.bidPrice, isNull);
      expect(p.effectivePrice, 150000);
      expect(SentProposalModel.buyerIdOf(row), 'buyer-9');
    });

    test('still maps, onto the unavailable card, with neither embed', () {
      final row = _row(status: 'expired');
      final p = SentProposalModel.fromRow(row);

      expect(p.hasCard, isFalse);
      expect(p.card, same(unavailableProposalCard));
      expect(p.status, BidProposalStatus.expired);
      expect(p.proposedQuantity, 2);
      expect(p.photos, ['https://x/a.jpg']);
      expect(SentProposalModel.buyerIdOf(row), isNull);
    });

    test('has no price to show when it accepted the bid price as-is', () {
      final p = SentProposalModel.fromRow(_row(proposedPrice: null));
      expect(p.effectivePrice, isNull);
      expect(p.isCounterOffer, isFalse);
    });
  });

  test('a readable bid still wins over the match', () {
    final row = _row(
      bid: {
        'id': 5,
        'price': 120000,
        'user_id': 'buyer-1',
        'cards': {..._card, 'id': 8},
      },
      match: {'bid_user_id': 'buyer-9', 'card': _card},
    );
    final p = SentProposalModel.fromRow(row);

    expect(p.card.id, 8);
    expect(p.bidPrice, 120000);
    expect(p.isCounterOffer, isTrue);
    expect(SentProposalModel.buyerIdOf(row), 'buyer-1');
  });

  test('card-less proposals fold into one group instead of vanishing', () {
    final groups = groupProposalsByCard(
      bids: const [],
      sent: [
        SentProposalModel.fromRow(_row(status: 'expired')),
        SentProposalModel.fromRow(_row(status: 'rejected')),
        SentProposalModel.fromRow(
          _row(match: {'bid_user_id': 'b', 'card': _card}),
        ),
      ],
    );

    final unavailable = groups.singleWhere(
      (g) => g.card.id == unavailableProposalCard.id,
    );
    expect(unavailable.sentTotal, 2);
    expect(unavailable.sentSettled, 2);
    expect(groups.singleWhere((g) => g.card.id == 7).sentTotal, 1);
  });
}
