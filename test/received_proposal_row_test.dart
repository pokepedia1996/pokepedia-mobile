import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/bid_proposal_model.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// A buyer deciding on a proposal is deciding on one specific copy at one
/// specific price. The row showed neither: `proposed_price` was selected and
/// dropped on the floor, and `photos` was never asked for at all.
BidProposalModel _proposal({int? proposed, int? bid, List<String>? photos}) =>
    BidProposalModel(
      slug: 'p1',
      card: const CardModel(
        id: 1,
        category: CardCategory.pokemon,
        nameId: 'Lugia',
        expansionCode: 'MA6',
        packSlug: 'ma6',
        collectorNumber: '173/130',
        rarity: 'AR',
      ),
      condition: CardCondition.nm,
      proposedQuantity: 1,
      sellerStoreName: 'Young',
      status: BidProposalStatus.pending,
      createdAt: DateTime(2026, 9, 26),
      expiresAt: DateTime(2026, 9, 28),
      proposedPrice: proposed,
      bidPrice: bid,
      photos: photos ?? const [],
    );

void main() {
  test('a proposal carries the price and the photos of the copy', () {
    final proposal = _proposal(
      proposed: 799999,
      bid: 799999,
      photos: const ['a.jpg', 'b.jpg'],
    );

    expect(proposal.proposedPrice, 799999);
    expect(proposal.photos, hasLength(2));
  });

  group('whether the ask is a counter', () {
    test('at the bid price it is the buyer own offer, taken up', () {
      expect(_proposal(proposed: 799999, bid: 799999).isAboveBid, isFalse);
    });

    test('above the bid price it is a counter the buyer never committed to', () {
      // This is what decides whether rejecting should cost the bid.
      expect(_proposal(proposed: 900000, bid: 799999).isAboveBid, isTrue);
    });

    test('below the bid price is not a counter either', () {
      expect(_proposal(proposed: 700000, bid: 799999).isAboveBid, isFalse);
    });

    test('an unpriced proposal claims nothing', () {
      // Older rows predate `proposed_price`; they must not read as counters.
      expect(_proposal(bid: 799999).isAboveBid, isFalse);
      expect(_proposal(proposed: 900000).isAboveBid, isFalse);
    });
  });
}
